import Foundation

/// OAuth configuration for Claude authentication
public struct AuthConfiguration: Sendable {
    /// OAuth client ID
    public let clientId: String
    
    /// Authorization endpoint URL
    public let authorizationURL: URL
    
    /// Token exchange endpoint URL
    public let tokenURL: URL
    
    /// OAuth redirect URI
    public let redirectURI: String
    
    /// OAuth scopes
    public let scope: String
    
    /// Beta header for Anthropic OAuth
    public let betaHeader: String
    
    /// Use manual code entry (adds ?code=true to auth URL)
    public let useManualCodeEntry: Bool
    
    /// Default Claude OAuth configuration
    public static let claude = AuthConfiguration(
        clientId: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        authorizationURL: URL(string: "https://claude.ai/oauth/authorize")!,
        tokenURL: URL(string: "https://console.anthropic.com/v1/oauth/token")!,
        redirectURI: "https://console.anthropic.com/oauth/code/callback",
        scope: "org:create_api_key user:profile user:inference",
        betaHeader: "oauth-2025-04-20",
        useManualCodeEntry: true
    )
    
    /// Initialize with custom configuration
    public init(clientId: String,
                authorizationURL: URL,
                tokenURL: URL,
                redirectURI: String,
                scope: String,
                betaHeader: String = "",
                useManualCodeEntry: Bool = true) {
        self.clientId = clientId
        self.authorizationURL = authorizationURL
        self.tokenURL = tokenURL
        self.redirectURI = redirectURI
        self.scope = scope
        self.betaHeader = betaHeader
        self.useManualCodeEntry = useManualCodeEntry
    }
    
    /// Build authorization URL with PKCE parameters
    func buildAuthorizationURL(codeChallenge: String, state: String) -> URL {
        var components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)!
        
        var queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        
        if useManualCodeEntry {
            queryItems.insert(URLQueryItem(name: "code", value: "true"), at: 0)
        }
        
        components.queryItems = queryItems
        return components.url!
    }
}