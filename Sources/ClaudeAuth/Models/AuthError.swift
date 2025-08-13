import Foundation

/// Authentication errors that can occur during OAuth flow
public enum AuthError: LocalizedError, Sendable {
    /// Invalid authorization code format
    case invalidAuthCode(String)
    
    /// State mismatch during OAuth flow (CSRF protection)
    case stateMismatch(expected: String, received: String)
    
    /// Token exchange failed
    case tokenExchangeFailed(Error)
    
    /// Token refresh failed
    case tokenRefreshFailed(Error)
    
    /// No refresh token available
    case noRefreshToken
    
    /// No valid token found
    case noValidToken
    
    /// Network request failed
    case networkError(Error)
    
    /// Invalid response from server
    case invalidResponse(String)
    
    /// Keychain operation failed
    case keychainError(OSStatus)
    
    /// User cancelled authentication
    case userCancelled
    
    /// Authentication session failed
    case sessionFailed(Error)
    
    /// Token is expired and cannot be refreshed
    case tokenExpired
    
    public var errorDescription: String? {
        switch self {
        case .invalidAuthCode(let code):
            return "Invalid authentication code format: \(code). Expected format: code#state"
        case .stateMismatch(let expected, let received):
            return "State mismatch. Expected: \(expected), Received: \(received)"
        case .tokenExchangeFailed(let error):
            return "Failed to exchange code for token: \(error.localizedDescription)"
        case .tokenRefreshFailed(let error):
            return "Failed to refresh token: \(error.localizedDescription)"
        case .noRefreshToken:
            return "No refresh token available for token renewal"
        case .noValidToken:
            return "No valid authentication token found"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse(let message):
            return "Invalid server response: \(message)"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .userCancelled:
            return "Authentication cancelled by user"
        case .sessionFailed(let error):
            return "Authentication session failed: \(error.localizedDescription)"
        case .tokenExpired:
            return "Token is expired and cannot be refreshed"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .invalidAuthCode:
            return "Ensure you copy the entire authentication code including the '#' separator"
        case .stateMismatch:
            return "Try authenticating again. This error prevents CSRF attacks."
        case .tokenExchangeFailed, .tokenRefreshFailed:
            return "Check your network connection and try again"
        case .noRefreshToken, .tokenExpired:
            return "Please authenticate again to get a new token"
        case .noValidToken:
            return "Call authenticate() to obtain a valid token"
        case .networkError:
            return "Check your internet connection and try again"
        case .invalidResponse:
            return "The server response was unexpected. Please try again later."
        case .keychainError:
            return "Check device settings and keychain access permissions"
        case .userCancelled:
            return "Complete the authentication process to continue"
        case .sessionFailed:
            return "Try authenticating again or check your browser settings"
        }
    }
}