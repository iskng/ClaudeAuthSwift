import SwiftUI
import SafariServices
import ClaudeAuth

// MARK: - Complete iOS Authentication Flow Example
// NOTE: This example shows BOTH approaches:
// 1. NEW: Automatic clipboard detection (recommended) - just call authenticate()
// 2. OLD: Manual code entry UI (for reference) - no longer needed!

/// Main iOS app showing complete auth flow
struct ClaudeAuthiOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Main content view with authentication
struct ContentView: View {
    @StateObject private var authManager = AuthenticationManager()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if authManager.isAuthenticated {
                    AuthenticatedView(authManager: authManager)
                } else {
                    UnauthenticatedView(authManager: authManager)
                }
            }
            .navigationTitle("Claude Auth")
            .alert("Authentication Error", 
                   isPresented: $authManager.showError) {
                Button("OK") { }
            } message: {
                Text(authManager.errorMessage)
            }
        }
        // NOTE: Manual code entry sheet no longer needed!
        // The package handles it automatically with clipboard detection
        .task {
            await authManager.checkExistingAuth()
        }
    }
}

// MARK: - Authentication Manager

/// Manages the authentication flow
@MainActor
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var showingCodeEntry = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var isLoading = false
    
    private let auth = ClaudeAuth.shared
    private var currentSession: AuthenticationSession?
    
    /// Check if user is already authenticated
    func checkExistingAuth() async {
        await auth.loadExistingToken()
        isAuthenticated = auth.isAuthenticated
    }
    
    /// Start authentication flow - Now uses automatic clipboard detection!
    func startAuthentication() async {
        isLoading = true
        
        do {
            // NEW: Just call authenticate() - handles everything!
            let token = try await auth.authenticate()
            
            // Success - token obtained automatically
            isAuthenticated = true
            currentSession = nil
        } catch {
            // Only show error if not manual entry related
            if case AuthError.invalidResponse = error {
                // Manual entry might be needed - handled by package
            } else {
                showError(error)
            }
        }
        
        isLoading = false
    }
    
    /// Complete authentication with code
    /// NOTE: This is now handled automatically by the package!
    /// Only needed if you want custom manual entry UI
    func completeAuthentication(code: String) async {
        isLoading = true
        showingCodeEntry = false
        
        do {
            _ = try await auth.completeAuthentication(authCode: code)
            isAuthenticated = true
        } catch {
            showError(error)
            // Re-show code entry on error
            showingCodeEntry = true
        }
        
        isLoading = false
    }
    
    /// Logout
    func logout() async {
        do {
            try await auth.logout()
            isAuthenticated = false
            currentSession = nil
        } catch {
            showError(error)
        }
    }
    
    private func openAuthURL(_ url: URL) {
        // Option 1: Open in Safari app (simpler)
        UIApplication.shared.open(url)
        
        // Option 2: Use SFSafariViewController (in-app)
        // See SafariAuthView implementation below
    }
    
    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}

// MARK: - Unauthenticated View

struct UnauthenticatedView: View {
    @ObservedObject var authManager: AuthenticationManager
    
    var body: some View {
        VStack(spacing: 30) {
            // Logo/Icon
            Image(systemName: "brain.head.profile")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("Claude AI Authentication")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Sign in with your Claude account to continue")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            // Sign In Button
            Button(action: {
                Task {
                    await authManager.startAuthentication()
                }
            }) {
                HStack {
                    Image(systemName: "person.badge.key")
                    Text("Sign in with Claude")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(authManager.isLoading)
            .padding(.horizontal)
            
            if authManager.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            }
        }
        .padding()
    }
}

// MARK: - Code Entry View

struct CodeEntryView: View {
    @ObservedObject var authManager: AuthenticationManager
    @State private var authCode = ""
    @FocusState private var isCodeFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Instructions
                VStack(alignment: .leading, spacing: 15) {
                    InstructionRow(
                        number: "1",
                        text: "Safari opened with Claude sign-in",
                        icon: "safari",
                        status: .completed
                    )
                    
                    InstructionRow(
                        number: "2",
                        text: "Sign in and click 'Authorize'",
                        icon: "hand.tap",
                        status: .active
                    )
                    
                    InstructionRow(
                        number: "3",
                        text: "Copy the code shown (including #state)",
                        icon: "doc.on.clipboard",
                        status: .pending
                    )
                    
                    InstructionRow(
                        number: "4",
                        text: "Paste the code below",
                        icon: "arrow.down.doc",
                        status: .pending
                    )
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Code Input Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Authentication Code")
                        .font(.headline)
                    
                    TextField("Paste code#state here", text: $authCode)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .focused($isCodeFieldFocused)
                        .font(.system(.body, design: .monospaced))
                    
                    Text("Format: code#state")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Action Buttons
                HStack(spacing: 15) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                    
                    Button("Continue") {
                        Task {
                            await authManager.completeAuthentication(code: authCode)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(authCode.isEmpty ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(authCode.isEmpty || authManager.isLoading)
                }
                
                if authManager.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                }
            }
            .padding()
            .navigationTitle("Enter Authentication Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Help") {
                        // Show help
                    }
                }
            }
        }
        .onAppear {
            isCodeFieldFocused = true
        }
    }
}

// MARK: - Instruction Row

struct InstructionRow: View {
    enum Status {
        case completed, active, pending
    }
    
    let number: String
    let text: String
    let icon: String
    let status: Status
    
    var body: some View {
        HStack(spacing: 12) {
            // Number badge
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 30, height: 30)
                
                Text(number)
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(textColor)
            }
            
            // Icon
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 20)
            
            // Text
            Text(text)
                .font(.subheadline)
                .foregroundColor(textColor)
            
            Spacer()
            
            // Status indicator
            if status == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
    }
    
    private var backgroundColor: Color {
        switch status {
        case .completed: return .green
        case .active: return .blue
        case .pending: return Color(.systemGray4)
        }
    }
    
    private var textColor: Color {
        switch status {
        case .completed, .active: return .white
        case .pending: return Color(.systemGray)
        }
    }
    
    private var iconColor: Color {
        switch status {
        case .completed: return .green
        case .active: return .blue
        case .pending: return Color(.systemGray)
        }
    }
}

// MARK: - Authenticated View

struct AuthenticatedView: View {
    @ObservedObject var authManager: AuthenticationManager
    @State private var tokenInfo = ClaudeAuth.shared.tokenInfo
    
    var body: some View {
        VStack(spacing: 20) {
            // Success indicator
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Authenticated!")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Token info
            if let info = tokenInfo {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Token Status")
                            .font(.headline)
                        Spacer()
                        if let timeRemaining = info.formattedTimeRemaining {
                            Text(timeRemaining)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    
                    Label(
                        info.hasRefreshToken ? "Refresh token available" : "No refresh token",
                        systemImage: info.hasRefreshToken ? "arrow.clockwise.circle.fill" : "xmark.circle"
                    )
                    .font(.caption)
                    .foregroundColor(info.hasRefreshToken ? .green : .orange)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }
            
            Spacer()
            
            // Test API button
            Button(action: testAPI) {
                Label("Test Claude API", systemImage: "network")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            
            // Logout button
            Button(action: {
                Task {
                    await authManager.logout()
                }
            }) {
                Label("Sign Out", systemImage: "arrow.right.square")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundColor(.red)
                    .cornerRadius(10)
            }
        }
        .padding()
        .task {
            // Refresh token info periodically
            Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                tokenInfo = ClaudeAuth.shared.tokenInfo
            }
        }
    }
    
    private func testAPI() {
        Task {
            do {
                let token = try await ClaudeAuth.shared.getValidAccessToken()
                print("Got valid token: \(token.prefix(20))...")
                // Make API call...
            } catch {
                print("Error: \(error)")
            }
        }
    }
}

// MARK: - Alternative: SFSafariViewController (In-App Browser)

import SafariServices

struct SafariAuthView: UIViewControllerRepresentable {
    let url: URL
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = false
        
        let safari = SFSafariViewController(url: url, configuration: config)
        safari.dismissButtonStyle = .close
        safari.preferredControlTintColor = .systemBlue
        return safari
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// Usage for in-app Safari:
struct ContentViewWithSafari: View {
    @State private var showingSafari = false
    @State private var authURL: URL?
    
    var body: some View {
        Button("Authenticate") {
            Task {
                let session = try await ClaudeAuth.shared.startAuthentication()
                authURL = session.url
                showingSafari = true
            }
        }
        .sheet(isPresented: $showingSafari) {
            if let url = authURL {
                SafariAuthView(url: url, isPresented: $showingSafari)
            }
        }
    }
}