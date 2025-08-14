import SwiftUI
import ClaudeAuth

/// Comprehensive example demonstrating all authentication methods
struct ComprehensiveAuthExample: View {
    @StateObject private var auth = ClaudeAuth.shared
    @State private var showAuthOptions = false
    @State private var authMethod: AuthMethod = .automatic
    @State private var manualCode = ""
    @State private var status = "Not authenticated"
    @State private var isAuthenticating = false
    @State private var showManualEntry = false
    @State private var errorMessage: String?
    
    enum AuthMethod: String, CaseIterable {
        case automatic = "Automatic (Clipboard Detection)"
        case skipClipboard = "Skip Clipboard (Manual Only)"
        case directManual = "Direct Manual Entry"
        
        var description: String {
            switch self {
            case .automatic:
                return "Opens browser and automatically detects when you copy the auth code"
            case .skipClipboard:
                return "Opens browser but skips clipboard monitoring, goes straight to manual entry"
            case .directManual:
                return "For when you already have a code or clipboard permission was denied"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    // Status Section
                    statusSection
                    
                    // Authentication Methods
                    authMethodsSection
                    
                    // Manual Entry Section (if needed)
                    if showManualEntry {
                        manualEntrySection
                    }
                    
                    // Token Info (if authenticated)
                    if auth.isAuthenticated, let token = auth.currentToken {
                        tokenInfoSection(token)
                    }
                    
                    // Actions
                    actionsSection
                }
                .padding()
            }
            .navigationTitle("Claude Auth Example")
        }
    }
    
    // MARK: - View Components
    
    private var statusSection: some View {
        VStack(spacing: 10) {
            Label(status, systemImage: auth.isAuthenticated ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.headline)
                .foregroundColor(auth.isAuthenticated ? .green : .red)
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
            
            if isAuthenticating {
                ProgressView("Authenticating...")
                    .padding(.top, 5)
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(10)
    }
    
    private var authMethodsSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Authentication Methods")
                .font(.headline)
            
            ForEach(AuthMethod.allCases, id: \.self) { method in
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: { authenticateWith(method) }) {
                        HStack {
                            Text(method.rawValue)
                                .fontWeight(.medium)
                            Spacer()
                            Image(systemName: "arrow.right.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAuthenticating)
                    
                    Text(method.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var manualEntrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Manual Code Entry")
                .font(.headline)
            
            Text("Copy the entire code from Claude (including #state)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            TextField("code#state", text: $manualCode)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)
            
            HStack {
                Button("Cancel") {
                    showManualEntry = false
                    manualCode = ""
                }
                .buttonStyle(.bordered)
                
                Button("Submit Code") {
                    submitManualCode()
                }
                .buttonStyle(.borderedProminent)
                .disabled(manualCode.isEmpty)
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(10)
    }
    
    private func tokenInfoSection(_ token: OAuthToken) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Token Information")
                .font(.headline)
            
            Group {
                HStack {
                    Text("Access Token:")
                        .fontWeight(.medium)
                    Text(String(token.accessToken.prefix(20)) + "...")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                if let refreshToken = token.refreshToken {
                    HStack {
                        Text("Refresh Token:")
                            .fontWeight(.medium)
                        Text(String(refreshToken.prefix(20)) + "...")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Text("Expires:")
                        .fontWeight(.medium)
                    Text(token.isExpired ? "Expired" : "Valid")
                        .foregroundColor(token.isExpired ? .red : .green)
                }
            }
            .font(.caption)
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(10)
    }
    
    private var actionsSection: some View {
        VStack(spacing: 10) {
            if auth.isAuthenticated {
                Button("Verify Token") {
                    verifyToken()
                }
                .buttonStyle(.bordered)
                
                Button("Logout") {
                    logout()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }
    
    // MARK: - Authentication Methods
    
    private func authenticateWith(_ method: AuthMethod) {
        errorMessage = nil
        isAuthenticating = true
        
        Task {
            do {
                switch method {
                case .automatic:
                    try await authenticateAutomatic()
                    
                case .skipClipboard:
                    try await authenticateSkipClipboard()
                    
                case .directManual:
                    await MainActor.run {
                        showManualEntry = true
                        isAuthenticating = false
                    }
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }
    
    private func authenticateAutomatic() async throws {
        // Standard flow with clipboard detection
        let session = ClaudeAuthSession(auth: auth)
        let token = try await session.authenticate()
        
        await MainActor.run {
            status = "✅ Authenticated successfully!"
            isAuthenticating = false
        }
    }
    
    private func authenticateSkipClipboard() async throws {
        // Configure to skip clipboard and go straight to manual
        var config = ClaudeAuthSession.Configuration()
        config.skipClipboard = true
        config.showManualEntryFallback = true
        
        let session = ClaudeAuthSession(auth: auth, configuration: config)
        
        do {
            let token = try await session.authenticate()
            await MainActor.run {
                status = "✅ Authenticated successfully!"
                isAuthenticating = false
            }
        } catch {
            // Session will trigger manual entry
            await MainActor.run {
                if session.needsManualCodeEntry {
                    showManualEntry = true
                    status = "📋 Please enter the code manually"
                } else {
                    handleError(error)
                }
                isAuthenticating = false
            }
        }
    }
    
    private func submitManualCode() {
        guard !manualCode.isEmpty else { return }
        
        isAuthenticating = true
        errorMessage = nil
        
        Task {
            do {
                // First ensure we have an active session
                if auth.currentToken == nil {
                    // Start a new session first
                    _ = try await auth.startAuthentication()
                }
                
                // Now complete with manual code
                let token = try await auth.completeAuthenticationManually(code: manualCode)
                
                await MainActor.run {
                    status = "✅ Authenticated with manual code!"
                    showManualEntry = false
                    manualCode = ""
                    isAuthenticating = false
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func verifyToken() {
        Task {
            do {
                let isValid = try await auth.verifyToken()
                await MainActor.run {
                    status = isValid ? "✅ Token is valid!" : "❌ Token verification failed"
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Verification error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func logout() {
        Task {
            try await auth.logout()
            await MainActor.run {
                status = "Not authenticated"
                errorMessage = nil
                showManualEntry = false
                manualCode = ""
            }
        }
    }
    
    private func handleError(_ error: Error) {
        isAuthenticating = false
        
        if case AuthError.userCancelled = error {
            status = "❌ Authentication cancelled"
            errorMessage = "User cancelled the authentication"
        } else if case AuthError.invalidAuthCode = error {
            errorMessage = "Invalid code format. Must be: code#state"
            if !showManualEntry {
                showManualEntry = true
            }
        } else {
            status = "❌ Authentication failed"
            errorMessage = error.localizedDescription
            
            // Show manual entry as fallback
            if !showManualEntry {
                showManualEntry = true
            }
        }
    }
}

// MARK: - Usage Instructions

/*
 COMPREHENSIVE AUTHENTICATION EXAMPLE
 ====================================
 
 This example demonstrates all authentication methods available in ClaudeAuthSwift:
 
 1. AUTOMATIC (CLIPBOARD DETECTION)
    - Opens browser for authentication
    - Automatically monitors clipboard for auth code
    - Falls back to manual entry if clipboard fails
    - Best for: Normal flow when clipboard access is available
 
 2. SKIP CLIPBOARD (MANUAL ONLY)
    - Opens browser but skips clipboard monitoring entirely
    - Goes straight to manual entry after browser closes
    - Best for: When you know clipboard won't work or prefer manual entry
 
 3. DIRECT MANUAL ENTRY
    - Doesn't open browser at all
    - For entering a code you already have
    - Best for: When clipboard permission was denied or you have an existing code
 
 ERROR HANDLING
 --------------
 - All methods handle errors gracefully
 - Falls back to manual entry when appropriate
 - Shows clear error messages to guide users
 
 CLIPBOARD PERMISSION SCENARIOS
 ------------------------------
 
 Scenario 1: Clipboard Access Granted (iOS 16+)
 - Automatic detection works seamlessly
 - Code is captured when copied from browser
 
 Scenario 2: Clipboard Access Denied
 - App detects no clipboard content
 - Automatically shows manual entry UI
 - User can paste or type the code
 
 Scenario 3: iOS 14+ Clipboard Notification
 - User sees system notification when app reads clipboard
 - Can choose to allow or deny per-use
 - Manual fallback available if denied
 
 INTEGRATION TIPS
 ----------------
 
 1. Store auth method preference:
    @AppStorage("preferredAuthMethod") var method = AuthMethod.automatic
 
 2. Custom clipboard wait time:
    var config = ClaudeAuthSession.Configuration()
    config.clipboardWaitTime = 5.0 // Wait 5 seconds
 
 3. Disable manual fallback:
    config.showManualEntryFallback = false
 
 4. Pre-populate manual code (e.g., from deep link):
    manualCode = deepLinkCode
    showManualEntry = true
 */

// MARK: - Preview

struct ComprehensiveAuthExample_Previews: PreviewProvider {
    static var previews: some View {
        ComprehensiveAuthExample()
    }
}