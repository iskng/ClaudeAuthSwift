import Foundation

/// Events related to token lifecycle
public enum TokenEvent: Sendable {
    /// New token obtained from initial authentication
    case authenticated(OAuthToken)
    
    /// Token refreshed automatically
    case refreshed(old: OAuthToken, new: OAuthToken)
    
    /// Token refresh failed
    case refreshFailed(error: Error)
    
    /// Token expired and cannot be refreshed
    case expired(OAuthToken)
    
    /// User logged out
    case loggedOut
    
    /// Token manually updated (e.g., from manual code entry)
    case manuallyUpdated(OAuthToken)
}

/// Token event context with additional metadata
public struct TokenEventContext: Sendable {
    public let event: TokenEvent
    public let timestamp: Date
    public let source: TokenEventSource
    
    public enum TokenEventSource: String, Sendable {
        case automatic = "automatic"
        case manual = "manual"
        case background = "background"
    }
    
    init(event: TokenEvent, source: TokenEventSource = .automatic) {
        self.event = event
        self.timestamp = Date()
        self.source = source
    }
}

/// Token event observer protocol for delegate pattern
public protocol TokenEventObserver: AnyObject {
    func tokenEventOccurred(_ event: TokenEventContext)
}

/// Notification names for token events
public extension Notification.Name {
    static let claudeAuthTokenRefreshed = Notification.Name("ClaudeAuth.tokenRefreshed")
    static let claudeAuthTokenExpired = Notification.Name("ClaudeAuth.tokenExpired")
    static let claudeAuthAuthenticated = Notification.Name("ClaudeAuth.authenticated")
    static let claudeAuthLoggedOut = Notification.Name("ClaudeAuth.loggedOut")
}

/// Notification userInfo keys
public struct TokenEventKeys {
    public static let token = "token"
    public static let oldToken = "oldToken"
    public static let newToken = "newToken"
    public static let error = "error"
    public static let source = "source"
}