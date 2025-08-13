import Foundation

/// OAuth token data structure
public struct OAuthToken: Codable, Sendable {
    /// Access token for API authentication
    public let accessToken: String
    
    /// Token type (typically "Bearer")
    public let tokenType: String
    
    /// Token expiration time in seconds
    public let expiresIn: Int?
    
    /// Refresh token for obtaining new access tokens
    public let refreshToken: String?
    
    /// OAuth scopes granted
    public let scope: String?
    
    /// Timestamp when token was created (Unix timestamp in milliseconds)
    public let createdAt: TimeInterval
    
    /// Computed property to check if token is expired
    public var isExpired: Bool {
        guard let expiresIn = expiresIn else { return false }
        // Convert createdAt from milliseconds to seconds if needed
        let createdAtSeconds = createdAt > 1_000_000_000_000 ? createdAt / 1000 : createdAt
        let expirationTime = createdAtSeconds + Double(expiresIn)
        // Add 1 hour buffer for early refresh
        return Date().timeIntervalSince1970 > (expirationTime - 3600)
    }
    
    /// Computed property for expiration date
    public var expirationDate: Date? {
        guard let expiresIn = expiresIn else { return nil }
        // Convert createdAt from milliseconds to seconds if needed
        let createdAtSeconds = createdAt > 1_000_000_000_000 ? createdAt / 1000 : createdAt
        return Date(timeIntervalSince1970: createdAtSeconds + Double(expiresIn))
    }
    
    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case createdAt = "created_at"
    }
    
    /// Initialize from API response
    init(accessToken: String,
         tokenType: String = "Bearer",
         expiresIn: Int? = nil,
         refreshToken: String? = nil,
         scope: String? = nil,
         createdAt: TimeInterval? = nil) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
        self.scope = scope
        self.createdAt = createdAt ?? Date().timeIntervalSince1970 * 1000
    }
    
    /// Initialize from decoder with automatic timestamp conversion
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType) ?? "Bearer"
        expiresIn = try container.decodeIfPresent(Int.self, forKey: .expiresIn)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        
        // Handle createdAt - if not present, use current timestamp
        if let timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .createdAt) {
            createdAt = timestamp
        } else {
            createdAt = Date().timeIntervalSince1970 * 1000
        }
    }
}