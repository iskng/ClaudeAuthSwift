import Foundation

/// Protocol for token storage implementations
public protocol TokenStorage: Sendable {
    /// Retrieve stored token
    func getToken() async throws -> OAuthToken?
    
    /// Store token
    func setToken(_ token: OAuthToken) async throws
    
    /// Remove stored token
    func removeToken() async throws
    
    /// Check if token exists
    func hasToken() async throws -> Bool
}

/// Default implementation for hasToken
public extension TokenStorage {
    func hasToken() async throws -> Bool {
        let token = try await getToken()
        return token != nil
    }
}