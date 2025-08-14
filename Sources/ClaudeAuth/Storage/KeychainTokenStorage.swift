import Foundation
import Security

/// Keychain-based token storage for secure persistence
public actor KeychainTokenStorage: TokenStorage {
    private let service: String
    private let account: String
    private let accessGroup: String?
    
    /// Initialize keychain storage
    /// - Parameters:
    ///   - service: Keychain service identifier (default: bundle identifier or "com.vibekit.claude-auth")
    ///   - account: Account identifier (default: "oauth-token")
    ///   - accessGroup: Optional keychain access group for app sharing
    public init(service: String? = nil,
                account: String = "oauth-token",
                accessGroup: String? = nil) {
        self.service = service ?? Bundle.main.bundleIdentifier ?? "com.vibekit.claude-auth"
        self.account = account
        self.accessGroup = accessGroup
    }
    
    public func getToken() async throws -> OAuthToken? {
        var query = buildQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw AuthError.keychainError(status)
            }
            let decoder = JSONDecoder()
            return try decoder.decode(OAuthToken.self, from: data)
            
        case errSecItemNotFound:
            return nil
            
        default:
            throw AuthError.keychainError(status)
        }
    }
    
    public func setToken(_ token: OAuthToken) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(token)
        
        // Try to update existing item first
        let query = buildQuery()
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrModificationDate as String: Date()
        ]
        
        var status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        
        // If item doesn't exist, add it
        if status == errSecItemNotFound {
            var addQuery = buildQuery()
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrCreationDate as String] = Date()
            addQuery[kSecAttrModificationDate as String] = Date()
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        
        guard status == errSecSuccess else {
            throw AuthError.keychainError(status)
        }
    }
    
    public func removeToken() async throws {
        let query = buildQuery()
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthError.keychainError(status)
        }
    }
    
    private func buildQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        // Add access group if specified
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        return query
    }
}

/// In-memory token storage for testing or temporary use
public actor MemoryTokenStorage: TokenStorage {
    private var token: OAuthToken?
    
    public init(token: OAuthToken? = nil) {
        self.token = token
    }
    
    public func getToken() async throws -> OAuthToken? {
        return token
    }
    
    public func setToken(_ token: OAuthToken) async throws {
        self.token = token
    }
    
    public func removeToken() async throws {
        self.token = nil
    }
}