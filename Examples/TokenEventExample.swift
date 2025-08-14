import SwiftUI
import ClaudeAuth
import Combine

/// Example demonstrating all three ways to observe token events
struct TokenEventExample: View {
    @StateObject private var auth = ClaudeAuth.shared
    @State private var eventLog: [String] = []
    @State private var cancellables = Set<AnyCancellable>()
    @State private var eventTask: Task<Void, Never>?
    
    var body: some View {
        NavigationView {
            VStack {
                // Status
                HStack {
                    Text("Authenticated:")
                    Text(auth.isAuthenticated ? "✅" : "❌")
                    Spacer()
                }
                .padding()
                
                // Event Log
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(eventLog.reversed(), id: \.self) { log in
                            Text(log)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(Color(UIColor.systemGray6))
                .cornerRadius(10)
                
                // Actions
                VStack(spacing: 10) {
                    Button("Authenticate") {
                        Task {
                            try? await auth.authenticate()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Force Token Refresh") {
                        Task {
                            try? await auth.getValidAccessToken()
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Logout") {
                        Task {
                            try? await auth.logout()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding()
            }
            .navigationTitle("Token Events")
            .onAppear {
                setupEventListeners()
            }
            .onDisappear {
                eventTask?.cancel()
                cancellables.removeAll()
            }
        }
    }
    
    private func setupEventListeners() {
        // Method 1: AsyncStream (Modern Swift Concurrency)
        eventTask = Task {
            for await event in auth.tokenEvents {
                await MainActor.run {
                    logEvent("🔄 AsyncStream: \(describeEvent(event))")
                }
            }
        }
        
        // Method 2: Combine Publisher
        auth.tokenEventPublisher
            .receive(on: DispatchQueue.main)
            .sink { event in
                logEvent("📡 Combine: \(describeEvent(event))")
            }
            .store(in: &cancellables)
        
        // Method 3: NotificationCenter
        NotificationCenter.default.addObserver(
            forName: .claudeAuthTokenRefreshed,
            object: auth,
            queue: .main
        ) { notification in
            if let oldToken = notification.userInfo?[TokenEventKeys.oldToken] as? OAuthToken,
               let newToken = notification.userInfo?[TokenEventKeys.newToken] as? OAuthToken {
                logEvent("📢 Notification: Token refreshed")
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .claudeAuthAuthenticated,
            object: auth,
            queue: .main
        ) { _ in
            logEvent("📢 Notification: Authenticated")
        }
        
        NotificationCenter.default.addObserver(
            forName: .claudeAuthLoggedOut,
            object: auth,
            queue: .main
        ) { _ in
            logEvent("📢 Notification: Logged out")
        }
    }
    
    private func logEvent(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        eventLog.append("[\(timestamp)] \(message)")
        
        // Keep only last 50 events
        if eventLog.count > 50 {
            eventLog.removeFirst()
        }
    }
    
    private func describeEvent(_ context: TokenEventContext) -> String {
        switch context.event {
        case .authenticated:
            return "Authenticated (source: \(context.source.rawValue))"
        case .refreshed:
            return "Token Refreshed (source: \(context.source.rawValue))"
        case .refreshFailed(let error):
            return "Refresh Failed: \(error.localizedDescription)"
        case .expired:
            return "Token Expired"
        case .loggedOut:
            return "Logged Out"
        case .manuallyUpdated:
            return "Manually Updated"
        }
    }
}

// MARK: - Usage in Your App

/*
 TOKEN EVENT SUBSCRIPTION PATTERNS
 ==================================
 
 1. ASYNCSTREAM (RECOMMENDED FOR MODERN APPS)
 --------------------------------------------
 Perfect for async/await code and SwiftUI:
 
 ```swift
 Task {
     for await event in ClaudeAuth.shared.tokenEvents {
         switch event.event {
         case .refreshed(let old, let new):
             print("Token refreshed!")
             // Update your API client headers
             apiClient.updateToken(new.accessToken)
             
         case .expired(let token):
             print("Token expired, showing login")
             showLoginScreen()
             
         case .refreshFailed(let error):
             print("Refresh failed: \(error)")
             // Handle refresh failure
         }
     }
 }
 ```
 
 2. COMBINE PUBLISHER
 --------------------
 Great for reactive programming and SwiftUI:
 
 ```swift
 ClaudeAuth.shared.tokenEventPublisher
     .filter { context in
         // Only care about refresh events
         if case .refreshed = context.event { return true }
         return false
     }
     .sink { context in
         print("Token was refreshed!")
     }
     .store(in: &cancellables)
 ```
 
 3. NOTIFICATIONCENTER (LEGACY/COMPATIBILITY)
 --------------------------------------------
 For older codebases or cross-framework compatibility:
 
 ```swift
 NotificationCenter.default.addObserver(
     forName: .claudeAuthTokenRefreshed,
     object: nil,
     queue: .main
 ) { notification in
     if let newToken = notification.userInfo?[TokenEventKeys.newToken] as? OAuthToken {
         // Handle new token
     }
 }
 ```
 
 4. SWIFTUI @PUBLISHED OBSERVATION
 ---------------------------------
 Simplest for basic SwiftUI apps:
 
 ```swift
 struct ContentView: View {
     @StateObject private var auth = ClaudeAuth.shared
     
     var body: some View {
         Text("Token: \(auth.currentToken?.accessToken ?? "none")")
             .onChange(of: auth.currentToken) { oldToken, newToken in
                 if oldToken != nil && newToken != nil {
                     print("Token changed!")
                 }
             }
     }
 }
 ```
 
 BEST PRACTICES
 --------------
 
 1. **Choose ONE method** - Don't mix multiple approaches in the same component
 2. **Handle all event types** - Don't just listen for success events
 3. **Clean up listeners** - Cancel tasks/subscriptions when done
 4. **Consider source** - Check event.source to know if it was automatic or manual
 5. **Update API clients** - When token refreshes, update your HTTP headers
 
 COMMON USE CASES
 ---------------
 
 **Auto-update API client on refresh:**
 ```swift
 Task {
     for await event in auth.tokenEvents {
         if case .refreshed(_, let newToken) = event.event {
             apiClient.setAuthHeader("Bearer \(newToken.accessToken)")
         }
     }
 }
 ```
 
 **Show login when token expires:**
 ```swift
 auth.tokenEventPublisher
     .compactMap { context in
         if case .expired = context.event { return true }
         if case .refreshFailed = context.event { return true }
         return nil
     }
     .sink { _ in
         presentLoginScreen()
     }
     .store(in: &cancellables)
 ```
 
 **Log all auth events:**
 ```swift
 Task {
     for await event in auth.tokenEvents {
         logger.info("Auth event: \(event)")
         analytics.track("auth_event", properties: [
             "type": String(describing: event.event),
             "source": event.source.rawValue
         ])
     }
 }
 ```
 */

// MARK: - Preview

struct TokenEventExample_Previews: PreviewProvider {
    static var previews: some View {
        TokenEventExample()
    }
}