import SwiftUI
import ClaudeAuth

// MARK: - Simplest Possible iOS Authentication

struct SimpleiOSApp: View {
    @StateObject private var auth = ClaudeAuth.shared
    @State private var showAuth = false
    @State private var message = ""
    
    var body: some View {
        VStack(spacing: 30) {
            // Status
            Image(systemName: auth.isAuthenticated ? "checkmark.circle.fill" : "person.crop.circle.badge.questionmark")
                .font(.system(size: 80))
                .foregroundColor(auth.isAuthenticated ? .green : .gray)
            
            Text(auth.isAuthenticated ? "Authenticated!" : "Not Authenticated")
                .font(.title)
                .fontWeight(.bold)
            
            // Simple authenticate button
            Button(action: authenticateSimple) {
                Label("Sign in with Claude", systemImage: "brain.head.profile")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(auth.isAuthenticated ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(auth.isAuthenticated)
            .padding(.horizontal)
            
            // Message display
            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            
            // Logout button
            if auth.isAuthenticated {
                Button("Sign Out") {
                    Task {
                        try? await auth.logout()
                        message = "Signed out"
                    }
                }
                .foregroundColor(.red)
            }
        }
        .padding()
    }
    
    /// Super simple authentication - just one line!
    func authenticateSimple() {
        Task {
            do {
                // THIS IS ALL YOU NEED! 🎉
                let token = try await ClaudeAuth.shared.authenticate()
                
                message = "Success! Token expires \(token.expirationDate?.formatted() ?? "never")"
            } catch {
                message = "Error: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Using the SwiftUI Modifier (Even Simpler!)

struct ModifierExample: View {
    @State private var showAuth = false
    @State private var isAuthenticated = false
    
    var body: some View {
        VStack {
            if isAuthenticated {
                Text("✅ Authenticated!")
            } else {
                Button("Authenticate") {
                    showAuth = true
                }
            }
        }
        // Just add this modifier - handles EVERYTHING!
        .claudeAuthentication(isPresented: $showAuth) { result in
            switch result {
            case .success:
                isAuthenticated = true
            case .failure(let error):
                print("Auth failed: \(error)")
            }
        }
    }
}

// MARK: - Advanced Configuration Example

struct AdvancedExample: View {
    @StateObject private var authSession: ClaudeAuthSession
    @State private var status = "Ready to authenticate"
    
    init() {
        // Configure the session behavior
        var config = ClaudeAuthSession.Configuration()
        config.clipboardWaitTime = 5.0 // Wait 5 seconds for clipboard
        config.autoMonitorClipboard = true // Auto-detect clipboard changes
        config.showManualEntryFallback = true // Show manual entry if needed
        config.clipboardCheckInterval = 0.3 // Check every 300ms
        
        _authSession = StateObject(wrappedValue: ClaudeAuthSession(configuration: config))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text(status)
                .font(.headline)
            
            // Loading state
            if authSession.isAuthenticating {
                ProgressView("Authenticating...")
            }
            
            // Manual entry needed
            if authSession.needsManualCodeEntry {
                VStack {
                    Text("📋 Paste the code from Claude")
                        .font(.caption)
                    
                    ManualCodeEntryInline(session: authSession) { result in
                        switch result {
                        case .success(let token):
                            status = "✅ Authenticated! Token: \(token.accessToken.prefix(10))..."
                        case .failure(let error):
                            status = "❌ Error: \(error.localizedDescription)"
                        }
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
            }
            
            // Authenticate button
            Button("Authenticate with Clipboard Detection") {
                Task {
                    do {
                        let token = try await authSession.authenticate()
                        status = "✅ Success! Got token automatically from clipboard!"
                    } catch {
                        if !authSession.needsManualCodeEntry {
                            status = "❌ \(error.localizedDescription)"
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(authSession.isAuthenticating)
            
            // Error display
            if let error = authSession.error {
                Text(error.localizedDescription)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
    }
}

// MARK: - Inline Manual Code Entry

struct ManualCodeEntryInline: View {
    @ObservedObject var session: ClaudeAuthSession
    @State private var code = ""
    let onCompletion: (Result<OAuthToken, Error>) -> Void
    
    var body: some View {
        HStack {
            TextField("code#state", text: $code)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)
            
            Button("Submit") {
                Task {
                    do {
                        let token = try await session.completeWithManualCode(code)
                        onCompletion(.success(token))
                    } catch {
                        onCompletion(.failure(error))
                    }
                }
            }
            .disabled(code.isEmpty)
        }
    }
}

// MARK: - How It Works

/*
 The Enhanced Authentication Flow:
 
 1. User taps "Sign in with Claude"
 2. ASWebAuthenticationSession opens Safari in-app
 3. User signs in and clicks "Authorize"
 4. Claude shows the code#state on screen
 5. User copies the code
 6. User closes Safari (swipe down or tap Done)
 7. Package automatically:
    - Detects Safari closed
    - Waits 3 seconds for user to return
    - Checks clipboard for valid code
    - If found: completes authentication automatically! ✨
    - If not found: shows manual entry UI as fallback
 
 Benefits:
 - No need to design your own UI
 - Automatic clipboard detection
 - Fallback to manual entry
 - Handles all edge cases
 - One line of code: try await ClaudeAuth.shared.authenticate()
 
 Configuration Options:
 - clipboardWaitTime: How long to wait after Safari closes
 - autoMonitorClipboard: Enable/disable clipboard monitoring
 - showManualEntryFallback: Show/hide manual entry UI
 - clipboardCheckInterval: How often to check clipboard
 */