import Foundation

/// OAuth client for token operations
public actor OAuthClient {
    private let configuration: AuthConfiguration
    private let urlSession: URLSession
    
    /// Initialize OAuth client
    /// - Parameters:
    ///   - configuration: OAuth configuration
    ///   - urlSession: URL session for network requests
    public init(configuration: AuthConfiguration = .claude,
                urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }
    
    /// Exchange authorization code for access token
    /// - Parameters:
    ///   - code: Authorization code
    ///   - codeVerifier: PKCE code verifier
    ///   - state: OAuth state parameter
    /// - Returns: OAuth token
    public func exchangeCodeForToken(code: String,
                                    codeVerifier: String,
                                    state: String) async throws -> OAuthToken {
        var request = URLRequest(url: configuration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if !configuration.betaHeader.isEmpty {
            request.setValue(configuration.betaHeader, forHTTPHeaderField: "anthropic-beta")
        }
        
        let body: [String: Any] = [
            "grant_type": "authorization_code",
            "code": code,
            "state": state,
            "code_verifier": codeVerifier,
            "redirect_uri": configuration.redirectURI,
            "client_id": configuration.clientId
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse("Invalid response type")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AuthError.tokenExchangeFailed(
                AuthError.invalidResponse("HTTP \(httpResponse.statusCode): \(errorMessage)")
            )
        }
        
        do {
            let decoder = JSONDecoder()
            var token = try decoder.decode(OAuthToken.self, from: data)
            
            // Ensure createdAt is set
            if token.createdAt == 0 {
                token = OAuthToken(
                    accessToken: token.accessToken,
                    tokenType: token.tokenType,
                    expiresIn: token.expiresIn,
                    refreshToken: token.refreshToken,
                    scope: token.scope,
                    createdAt: Date().timeIntervalSince1970 * 1000
                )
            }
            
            return token
        } catch {
            throw AuthError.tokenExchangeFailed(error)
        }
    }
    
    /// Refresh access token using refresh token
    /// - Parameter refreshToken: Refresh token
    /// - Returns: New OAuth token
    public func refreshAccessToken(refreshToken: String) async throws -> OAuthToken {
        var request = URLRequest(url: configuration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if !configuration.betaHeader.isEmpty {
            request.setValue(configuration.betaHeader, forHTTPHeaderField: "anthropic-beta")
        }
        
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": configuration.clientId
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse("Invalid response type")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AuthError.tokenRefreshFailed(
                AuthError.invalidResponse("HTTP \(httpResponse.statusCode): \(errorMessage)")
            )
        }
        
        do {
            let decoder = JSONDecoder()
            var token = try decoder.decode(OAuthToken.self, from: data)
            
            // Keep the refresh token if not provided in response
            if token.refreshToken == nil {
                token = OAuthToken(
                    accessToken: token.accessToken,
                    tokenType: token.tokenType,
                    expiresIn: token.expiresIn,
                    refreshToken: refreshToken,
                    scope: token.scope,
                    createdAt: Date().timeIntervalSince1970 * 1000
                )
            }
            
            return token
        } catch {
            throw AuthError.tokenRefreshFailed(error)
        }
    }
    
    /// Parse authorization code from Claude's manual code entry format
    /// - Parameters:
    ///   - codeString: The pasted code in format "code#state"
    ///   - expectedState: Expected state for validation
    /// - Returns: Tuple of (code, state)
    public static func parseAuthorizationCode(_ codeString: String,
                                             expectedState: String) throws -> (code: String, state: String) {
        let components = codeString.split(separator: "#").map(String.init)
        
        guard components.count == 2 else {
            throw AuthError.invalidAuthCode(codeString)
        }
        
        let code = components[0]
        let state = components[1]
        
        guard state == expectedState else {
            throw AuthError.stateMismatch(expected: expectedState, received: state)
        }
        
        return (code, state)
    }
}