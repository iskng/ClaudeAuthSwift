import Foundation
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

/// Main authentication manager for Claude OAuth
@MainActor
public class ClaudeAuth: ObservableObject {
    /// Shared singleton instance
    public static let shared = ClaudeAuth()
    
    /// Published authentication state for SwiftUI
    @Published public private(set) var isAuthenticated: Bool = false
    
    /// Published current token for SwiftUI
    @Published public private(set) var currentToken: OAuthToken? = nil
    
    /// OAuth configuration
    public let configuration: AuthConfiguration
    
    /// Token storage
    internal let storage: TokenStorage
    
    /// OAuth client
    internal let client: OAuthClient
    
    /// Current PKCE parameters
    private var currentPKCE: PKCE?
    
    /// Current state parameter
    private var currentState: String?
    
    /// Initialize with custom configuration
    /// - Parameters:
    ///   - configuration: OAuth configuration
    ///   - storage: Token storage implementation
    public init(configuration: AuthConfiguration = .claude,
                storage: TokenStorage? = nil) {
        self.configuration = configuration
        self.storage = storage ?? KeychainTokenStorage()
        self.client = OAuthClient(configuration: configuration)
        
        // Load existing token on init
        Task {
            await loadExistingToken()
        }
    }
    
    /// Private initializer for singleton
    private convenience init() {
        self.init(configuration: .claude, storage: nil)
    }
    
    // MARK: - Authentication Flow
    
    /// Start authentication flow
    /// - Returns: Authorization URL and PKCE parameters for manual authentication
    public func startAuthentication() async throws -> AuthenticationSession {
        // Generate PKCE and state
        let pkce = try PKCE()
        let state = try StateGenerator.generate()
        
        // Store for later use
        self.currentPKCE = pkce
        self.currentState = state
        
        // Build authorization URL
        let authURL = configuration.buildAuthorizationURL(
            codeChallenge: pkce.codeChallenge,
            state: state
        )
        
        return AuthenticationSession(
            url: authURL,
            state: state,
            codeVerifier: pkce.codeVerifier
        )
    }
    
    /// Complete authentication with authorization code
    /// - Parameter authCode: Authorization code in format "code#state"
    /// - Returns: OAuth token
    @discardableResult
    public func completeAuthentication(authCode: String) async throws -> OAuthToken {
        guard let pkce = currentPKCE,
              let expectedState = currentState else {
            throw AuthError.invalidResponse("No active authentication session. Make sure startAuthentication() was called first.")
        }
        
        do {
            // Parse and validate code
            let (code, state) = try OAuthClient.parseAuthorizationCode(authCode, expectedState: expectedState)
            
            // Exchange for token
            let token = try await client.exchangeCodeForToken(
                code: code,
                codeVerifier: pkce.codeVerifier,
                state: state
            )
            
            // Store token
            try await storage.setToken(token)
            
            // Update state
            self.currentToken = token
            self.isAuthenticated = true
            
            // Clear temporary data only on success
            self.currentPKCE = nil
            self.currentState = nil
            
            return token
        } catch {
            // Don't clear session data on error - allow retry
            // Only clear if it's a final error like state mismatch
            if case AuthError.stateMismatch = error {
                self.currentPKCE = nil
                self.currentState = nil
            }
            throw error
        }
    }
    
    /// Complete authentication with manually provided code when clipboard access is denied
    /// This method maintains the session context from startAuthentication
    /// - Parameter manualCode: The authentication code copied manually by the user
    /// - Returns: OAuth token
    @discardableResult
    public func completeAuthenticationManually(code manualCode: String) async throws -> OAuthToken {
        // Validate we have an active session
        guard currentPKCE != nil, currentState != nil else {
            throw AuthError.invalidResponse("No active authentication session. Call startAuthentication() first.")
        }
        
        // Use the existing completeAuthentication method
        return try await completeAuthentication(authCode: manualCode)
    }
    
    /// Check if there's an active authentication session
    public var hasActiveSession: Bool {
        return currentPKCE != nil && currentState != nil
    }
    
    /// Authenticate with automatic browser presentation (iOS/macOS only)
    /// - Returns: OAuth token
    #if canImport(AuthenticationServices)
    @available(iOS 13.0, macOS 10.15, *)
    @discardableResult
    public func authenticate() async throws -> OAuthToken {
        #if os(iOS) || os(visionOS)
        // Use enhanced iOS session with clipboard monitoring
        let authSession = ClaudeAuthSession(auth: self)
        return try await authSession.authenticate()
        #else
        // Original implementation for macOS
        let session = try await startAuthentication()
        
        return try await withCheckedThrowingContinuation { continuation in
            let authSession = ASWebAuthenticationSession(
                url: session.url,
                callbackURLScheme: nil
            ) { callbackURL, error in
                Task { @MainActor in
                    if let error = error {
                        if case ASWebAuthenticationSessionError.canceledLogin = error {
                            continuation.resume(throwing: AuthError.userCancelled)
                        } else {
                            continuation.resume(throwing: AuthError.sessionFailed(error))
                        }
                        return
                    }
                    
                    // Since we use manual code entry, user needs to paste the code
                    // In a real app, you'd show UI for code entry here
                    // For now, this is a placeholder
                    continuation.resume(throwing: AuthError.invalidResponse("Manual code entry required"))
                }
            }
            
            
            authSession.start()
        }
        #endif
    }
    #endif
    
    // MARK: - Token Management
    
    /// Get valid access token (auto-refresh if needed)
    public func getValidAccessToken() async throws -> String {
        // Load token if not cached
        if currentToken == nil {
            await loadExistingToken()
        }
        
        guard var token = currentToken else {
            throw AuthError.noValidToken
        }
        
        // Check if token needs refresh
        if token.isExpired {
            guard let refreshToken = token.refreshToken else {
                throw AuthError.noRefreshToken
            }
            
            // Refresh token
            token = try await client.refreshAccessToken(refreshToken: refreshToken)
            
            // Store new token
            try await storage.setToken(token)
            
            // Update state
            self.currentToken = token
            self.isAuthenticated = true
        }
        
        return token.accessToken
    }
    
    /// Load existing token from storage
    public func loadExistingToken() async {
        do {
            if let token = try await storage.getToken() {
                self.currentToken = token
                self.isAuthenticated = !token.isExpired || token.refreshToken != nil
            }
        } catch {
            // Ignore errors when loading
            self.currentToken = nil
            self.isAuthenticated = false
        }
    }
    
    /// Clear authentication (logout)
    public func logout() async throws {
        try await storage.removeToken()
        self.currentToken = nil
        self.isAuthenticated = false
    }
    
    /// Verify token with Claude API
    public func verifyToken() async throws -> Bool {
        let accessToken = try await getValidAccessToken()
        
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("", forHTTPHeaderField: "X-API-Key")
        
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 10,
            "system": "You are Claude Code, Anthropic's official CLI for Claude.",
            "messages": [
                ["role": "user", "content": "Reply with OK only."]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}

// MARK: - Authentication Session

/// Authentication session data
public struct AuthenticationSession: Sendable {
    /// Authorization URL to open
    public let url: URL
    
    /// State parameter for CSRF protection
    public let state: String
    
    /// PKCE code verifier
    public let codeVerifier: String
}

