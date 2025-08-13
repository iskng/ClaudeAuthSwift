import XCTest
@testable import ClaudeAuth

final class ClaudeAuthTests: XCTestCase {
    
    // MARK: - Token Tests
    
    func testOAuthTokenExpiration() {
        // Test non-expired token
        let futureToken = OAuthToken(
            accessToken: "test_token",
            tokenType: "Bearer",
            expiresIn: 3600,
            refreshToken: "refresh_token",
            scope: "test",
            createdAt: Date().timeIntervalSince1970 * 1000
        )
        XCTAssertFalse(futureToken.isExpired)
        
        // Test expired token
        let pastToken = OAuthToken(
            accessToken: "test_token",
            tokenType: "Bearer",
            expiresIn: 3600,
            refreshToken: "refresh_token",
            scope: "test",
            createdAt: (Date().timeIntervalSince1970 - 7200) * 1000 // 2 hours ago
        )
        XCTAssertTrue(pastToken.isExpired)
        
        // Test token without expiration
        let noExpiryToken = OAuthToken(
            accessToken: "test_token",
            tokenType: "Bearer",
            expiresIn: nil,
            refreshToken: "refresh_token",
            scope: "test",
            createdAt: Date().timeIntervalSince1970 * 1000
        )
        XCTAssertFalse(noExpiryToken.isExpired)
    }
    
    func testOAuthTokenExpirationDate() {
        let now = Date().timeIntervalSince1970 * 1000
        let token = OAuthToken(
            accessToken: "test_token",
            tokenType: "Bearer",
            expiresIn: 3600,
            refreshToken: "refresh_token",
            scope: "test",
            createdAt: now
        )
        
        let expectedDate = Date(timeIntervalSince1970: (now / 1000) + 3600)
        if let expirationDate = token.expirationDate {
            XCTAssertEqual(expirationDate.timeIntervalSince1970,
                          expectedDate.timeIntervalSince1970,
                          accuracy: 1.0)
        } else {
            XCTFail("Expected expiration date")
        }
    }
    
    // MARK: - PKCE Tests
    
    func testPKCEGeneration() throws {
        let pkce = try PKCE()
        
        // Verify code verifier length (should be 43 characters for base64url of 32 bytes)
        XCTAssertGreaterThanOrEqual(pkce.codeVerifier.count, 43)
        XCTAssertLessThanOrEqual(pkce.codeVerifier.count, 128)
        
        // Verify code challenge is not empty
        XCTAssertFalse(pkce.codeChallenge.isEmpty)
        
        // Verify base64url encoding (no +, /, or = characters)
        XCTAssertFalse(pkce.codeVerifier.contains("+"))
        XCTAssertFalse(pkce.codeVerifier.contains("/"))
        XCTAssertFalse(pkce.codeVerifier.contains("="))
        XCTAssertFalse(pkce.codeChallenge.contains("+"))
        XCTAssertFalse(pkce.codeChallenge.contains("/"))
        XCTAssertFalse(pkce.codeChallenge.contains("="))
    }
    
    func testPKCEConsistency() {
        let verifier = "test_verifier_12345"
        let pkce1 = PKCE(codeVerifier: verifier)
        let pkce2 = PKCE(codeVerifier: verifier)
        
        // Same verifier should produce same challenge
        XCTAssertEqual(pkce1.codeChallenge, pkce2.codeChallenge)
    }
    
    // MARK: - State Generator Tests
    
    func testStateGeneration() throws {
        let state1 = try StateGenerator.generate()
        let state2 = try StateGenerator.generate()
        
        // States should be unique
        XCTAssertNotEqual(state1, state2)
        
        // State should be base64url encoded
        XCTAssertFalse(state1.contains("+"))
        XCTAssertFalse(state1.contains("/"))
        XCTAssertFalse(state1.contains("="))
        
        // State should have reasonable length
        XCTAssertGreaterThanOrEqual(state1.count, 32)
    }
    
    // MARK: - Configuration Tests
    
    func testDefaultConfiguration() {
        let config = AuthConfiguration.claude
        
        XCTAssertEqual(config.clientId, "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
        XCTAssertEqual(config.authorizationURL.absoluteString, "https://claude.ai/oauth/authorize")
        XCTAssertEqual(config.tokenURL.absoluteString, "https://console.anthropic.com/v1/oauth/token")
        XCTAssertEqual(config.redirectURI, "https://console.anthropic.com/oauth/code/callback")
        XCTAssertEqual(config.scope, "org:create_api_key user:profile user:inference")
        XCTAssertEqual(config.betaHeader, "oauth-2025-04-20")
        XCTAssertTrue(config.useManualCodeEntry)
    }
    
    func testAuthorizationURLBuilding() throws {
        let config = AuthConfiguration.claude
        let pkce = try PKCE()
        let state = try StateGenerator.generate()
        
        let url = config.buildAuthorizationURL(
            codeChallenge: pkce.codeChallenge,
            state: state
        )
        
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let queryItems = components.queryItems ?? []
        
        // Check required parameters
        XCTAssertTrue(queryItems.contains { $0.name == "code" && $0.value == "true" })
        XCTAssertTrue(queryItems.contains { $0.name == "client_id" && $0.value == config.clientId })
        XCTAssertTrue(queryItems.contains { $0.name == "response_type" && $0.value == "code" })
        XCTAssertTrue(queryItems.contains { $0.name == "scope" && $0.value == config.scope })
        XCTAssertTrue(queryItems.contains { $0.name == "redirect_uri" && $0.value == config.redirectURI })
        XCTAssertTrue(queryItems.contains { $0.name == "code_challenge" && $0.value == pkce.codeChallenge })
        XCTAssertTrue(queryItems.contains { $0.name == "code_challenge_method" && $0.value == "S256" })
        XCTAssertTrue(queryItems.contains { $0.name == "state" && $0.value == state })
    }
    
    // MARK: - OAuth Client Tests
    
    func testAuthCodeParsing() throws {
        let expectedState = "test_state_123"
        let code = "auth_code_456"
        let authString = "\(code)#\(expectedState)"
        
        let result = try OAuthClient.parseAuthorizationCode(authString, expectedState: expectedState)
        
        XCTAssertEqual(result.code, code)
        XCTAssertEqual(result.state, expectedState)
    }
    
    func testAuthCodeParsingInvalidFormat() {
        let expectedState = "test_state_123"
        let invalidString = "invalid_format_without_separator"
        
        XCTAssertThrowsError(
            try OAuthClient.parseAuthorizationCode(invalidString, expectedState: expectedState)
        ) { error in
            guard case AuthError.invalidAuthCode = error else {
                XCTFail("Expected invalidAuthCode error")
                return
            }
        }
    }
    
    func testAuthCodeParsingStateMismatch() {
        let expectedState = "expected_state"
        let actualState = "different_state"
        let authString = "code#\(actualState)"
        
        XCTAssertThrowsError(
            try OAuthClient.parseAuthorizationCode(authString, expectedState: expectedState)
        ) { error in
            guard case AuthError.stateMismatch = error else {
                XCTFail("Expected stateMismatch error")
                return
            }
        }
    }
    
    // MARK: - Storage Tests
    
    func testMemoryTokenStorage() async throws {
        let storage = MemoryTokenStorage()
        
        // Initially should have no token
        let initialToken = try await storage.getToken()
        XCTAssertNil(initialToken)
        let hasInitialToken = try await storage.hasToken()
        XCTAssertFalse(hasInitialToken)
        
        // Store a token
        let token = OAuthToken(
            accessToken: "test_token",
            tokenType: "Bearer",
            expiresIn: 3600,
            refreshToken: "refresh_token",
            scope: "test",
            createdAt: Date().timeIntervalSince1970 * 1000
        )
        try await storage.setToken(token)
        
        // Should retrieve the stored token
        let retrievedToken = try await storage.getToken()
        XCTAssertNotNil(retrievedToken)
        XCTAssertEqual(retrievedToken?.accessToken, token.accessToken)
        let hasStoredToken = try await storage.hasToken()
        XCTAssertTrue(hasStoredToken)
        
        // Remove token
        try await storage.removeToken()
        let removedToken = try await storage.getToken()
        XCTAssertNil(removedToken)
        let hasFinalToken = try await storage.hasToken()
        XCTAssertFalse(hasFinalToken)
    }
    
    // MARK: - Error Tests
    
    func testAuthErrorDescriptions() {
        let errors: [AuthError] = [
            .invalidAuthCode("test"),
            .stateMismatch(expected: "exp", received: "rec"),
            .noRefreshToken,
            .noValidToken,
            .userCancelled,
            .tokenExpired
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertNotNil(error.recoverySuggestion)
            XCTAssertFalse(error.errorDescription!.isEmpty)
            XCTAssertFalse(error.recoverySuggestion!.isEmpty)
        }
    }
    
    // MARK: - Integration Tests
    
    @MainActor
    func testClaudeAuthInitialization() async throws {
        let storage = MemoryTokenStorage()
        let auth = ClaudeAuth(storage: storage)
        
        // Should start unauthenticated
        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertNil(auth.currentToken)
        
        // Test starting authentication
        let session = try await auth.startAuthentication()
        XCTAssertNotNil(session.url)
        XCTAssertNotNil(session.state)
        XCTAssertNotNil(session.codeVerifier)
        
        // Verify URL contains expected parameters
        let components = URLComponents(url: session.url, resolvingAgainstBaseURL: false)!
        XCTAssertTrue(components.queryItems?.contains { $0.name == "code" && $0.value == "true" } ?? false)
    }
    
    @MainActor
    func testAuthenticationSession() async throws {
        let auth = ClaudeAuth(storage: MemoryTokenStorage())
        let session = try await auth.startAuthentication()
        
        // Verify session properties
        XCTAssertTrue(session.url.absoluteString.starts(with: "https://claude.ai/oauth/authorize"))
        XCTAssertFalse(session.state.isEmpty)
        XCTAssertFalse(session.codeVerifier.isEmpty)
        
        // Verify state is base64url encoded
        XCTAssertFalse(session.state.contains("+"))
        XCTAssertFalse(session.state.contains("/"))
        XCTAssertFalse(session.state.contains("="))
    }
}