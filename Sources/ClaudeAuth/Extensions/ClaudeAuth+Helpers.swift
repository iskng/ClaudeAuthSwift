import Foundation

// MARK: - Token Management Helpers

extension ClaudeAuth {
    
    
    /// Time remaining until token expiration
    public var tokenTimeRemaining: TimeInterval? {
        guard let token = currentToken,
              let expirationDate = token.expirationDate else {
            return nil
        }
        return expirationDate.timeIntervalSinceNow
    }
    
    /// Check if token will expire soon (within specified interval)
    /// - Parameter within: Time interval in seconds (default: 5 minutes)
    public func tokenExpiringWithin(_ interval: TimeInterval = 300) -> Bool {
        guard let remaining = tokenTimeRemaining else { return true }
        return remaining < interval
    }
    
    /// Perform an authenticated request with automatic retry on token expiration
    /// - Parameters:
    ///   - request: URLRequest to perform
    ///   - session: URLSession to use
    ///   - maxRetries: Maximum number of retries for token refresh
    /// - Returns: Data and URLResponse
    public func performAuthenticatedRequest(
        _ request: inout URLRequest,
        session: URLSession = .shared,
        maxRetries: Int = 1
    ) async throws -> (Data, URLResponse) {
        var retries = 0
        
        while retries <= maxRetries {
            // Get valid token (auto-refreshes if needed)
            let accessToken = try await getValidAccessToken()
            
            // Set authorization header
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("", forHTTPHeaderField: "X-API-Key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            
            // Perform request
            let (data, response) = try await session.data(for: request)
            
            // Check if we got 401 (unauthorized)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 401 && retries < maxRetries {
                // Token might have just expired, retry
                retries += 1
                continue
            }
            
            return (data, response)
        }
        
        throw AuthError.tokenExpired
    }
}

// MARK: - Convenience Methods

extension ClaudeAuth {
    
    /// Quick check if we need user to re-authenticate
    /// Returns true if no token or no refresh token available
    public var needsAuthentication: Bool {
        get async {
            await loadExistingToken()
            guard let token = currentToken else { return true }
            
            // If token is expired and no refresh token, need auth
            if token.isExpired && token.refreshToken == nil {
                return true
            }
            
            return false
        }
    }
    
    /// Get token info for debugging/display
    public var tokenInfo: TokenInfo? {
        guard let token = currentToken else { return nil }
        
        return TokenInfo(
            hasAccessToken: !token.accessToken.isEmpty,
            hasRefreshToken: token.refreshToken != nil,
            isExpired: token.isExpired,
            expirationDate: token.expirationDate,
            timeRemaining: tokenTimeRemaining,
            scope: token.scope
        )
    }
}

/// Token information for UI display
public struct TokenInfo: Sendable {
    public let hasAccessToken: Bool
    public let hasRefreshToken: Bool
    public let isExpired: Bool
    public let expirationDate: Date?
    public let timeRemaining: TimeInterval?
    public let scope: String?
    
    public var formattedTimeRemaining: String? {
        guard let timeRemaining = timeRemaining, timeRemaining > 0 else {
            return nil
        }
        
        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}