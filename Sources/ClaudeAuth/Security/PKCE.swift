import Foundation
import CryptoKit

/// PKCE (Proof Key for Code Exchange) implementation for OAuth 2.0
public struct PKCE: Sendable {
    /// Code verifier for PKCE flow
    public let codeVerifier: String
    
    /// Code challenge derived from verifier
    public let codeChallenge: String
    
    /// Generate new PKCE parameters
    public init() throws {
        // Generate code verifier (43-128 characters, base64url)
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        
        guard result == errSecSuccess else {
            throw AuthError.keychainError(result)
        }
        
        self.codeVerifier = Data(bytes).base64URLEncodedString()
        
        // Generate code challenge using SHA256
        let challengeData = Data(SHA256.hash(data: Data(codeVerifier.utf8)))
        self.codeChallenge = challengeData.base64URLEncodedString()
    }
    
    /// Initialize with existing verifier (for testing or restoration)
    init(codeVerifier: String) {
        self.codeVerifier = codeVerifier
        let challengeData = Data(SHA256.hash(data: Data(codeVerifier.utf8)))
        self.codeChallenge = challengeData.base64URLEncodedString()
    }
}

// MARK: - Data Extension for Base64URL

extension Data {
    /// Encode data as base64url string (RFC 4648)
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// State parameter generator for CSRF protection
public struct StateGenerator {
    /// Generate cryptographically secure random state
    public static func generate() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        
        guard result == errSecSuccess else {
            throw AuthError.keychainError(result)
        }
        
        return Data(bytes).base64URLEncodedString()
    }
}