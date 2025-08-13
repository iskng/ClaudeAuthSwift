# ClaudeAuth Swift

Native Swift/iOS OAuth authentication library for Claude AI MAX subscriptions. Secure, modern implementation using Keychain storage, PKCE flow, and SwiftUI integration.

## Features

- **Native Swift Implementation**: Built specifically for Apple platforms
- **Secure Token Storage**: Keychain integration with biometric protection support
- **PKCE OAuth 2.0**: Industry-standard secure authentication flow
- **SwiftUI & UIKit Support**: Ready-to-use views and integration helpers
- **Automatic Token Refresh**: Seamless token management
- **Actor-based Concurrency**: Thread-safe with modern Swift concurrency
- **Zero Dependencies**: Uses only native Apple frameworks

## Requirements

- iOS 15.0+ / macOS 12.0+ / tvOS 15.0+ / watchOS 8.0+
- Swift 5.9+
- Xcode 15.0+

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/ClaudeAuthSwift.git", from: "1.0.0")
]
```

Or in Xcode: File → Add Package Dependencies → Enter package URL

## Usage

### Quick Start

```swift
import ClaudeAuth

// Simple authentication
let token = try await ClaudeAuth.shared.authenticate()

// Get valid access token (auto-refreshes)
let accessToken = try await ClaudeAuth.shared.getValidAccessToken()

// Check authentication status
if await ClaudeAuth.shared.isAuthenticated {
    // User is authenticated
}
```

### SwiftUI Integration

```swift
import SwiftUI
import ClaudeAuth

struct ContentView: View {
    @StateObject private var auth = ClaudeAuth.shared
    @State private var showAuth = false
    
    var body: some View {
        VStack {
            if auth.isAuthenticated {
                Text("Authenticated!")
                Button("Logout") {
                    Task {
                        try await auth.logout()
                    }
                }
            } else {
                Button("Sign in with Claude") {
                    showAuth = true
                }
            }
        }
        .claudeAuthenticationSheet(isPresented: $showAuth) { result in
            switch result {
            case .success(let token):
                print("Authenticated with token: \(token.accessToken)")
            case .failure(let error):
                print("Authentication failed: \(error)")
            }
        }
    }
}
```

### Manual Authentication Flow

For custom UI implementations:

```swift
import ClaudeAuth

class AuthenticationViewModel: ObservableObject {
    private let auth = ClaudeAuth.shared
    
    func startAuth() async throws {
        // 1. Start authentication session
        let session = try await auth.startAuthentication()
        
        // 2. Open browser with auth URL
        await UIApplication.shared.open(session.url)
        
        // 3. User authorizes and copies code
        // Show UI for code entry...
        
        // 4. Complete authentication with pasted code
        let authCode = "code123#state456" // From user input
        let token = try await auth.completeAuthentication(authCode: authCode)
        
        print("Access token: \(token.accessToken)")
    }
}
```

### Custom Token Storage

Implement the `TokenStorage` protocol for custom storage:

```swift
actor CustomTokenStorage: TokenStorage {
    func getToken() async throws -> OAuthToken? {
        // Your implementation
    }
    
    func setToken(_ token: OAuthToken) async throws {
        // Your implementation
    }
    
    func removeToken() async throws {
        // Your implementation
    }
}

// Use custom storage
let auth = ClaudeAuth(storage: CustomTokenStorage())
```

### Using with Claude API

```swift
import ClaudeAuth

func callClaudeAPI() async throws {
    // Get valid token
    let accessToken = try await ClaudeAuth.shared.getValidAccessToken()
    
    // Make API request
    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("", forHTTPHeaderField: "X-API-Key") // Leave empty for OAuth
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    
    // ... rest of API call
}
```

## Architecture

### Core Components

- **ClaudeAuth**: Main authentication manager (MainActor)
- **OAuthClient**: Handles token exchange and refresh (Actor)
- **KeychainTokenStorage**: Secure token persistence (Actor)
- **PKCE**: Cryptographic code generation
- **AuthenticationView**: SwiftUI authentication UI

### Security Features

- **Keychain Storage**: Tokens stored securely in iOS Keychain
- **PKCE Protection**: Prevents authorization code interception
- **State Validation**: CSRF protection via state parameter
- **Automatic Refresh**: Tokens refreshed 1 hour before expiry
- **Biometric Protection**: Optional Face ID/Touch ID for token access

## API Reference

### ClaudeAuth

```swift
@MainActor
class ClaudeAuth: ObservableObject {
    // Singleton instance
    static let shared: ClaudeAuth
    
    // Observable properties
    @Published var isAuthenticated: Bool
    @Published var currentToken: OAuthToken?
    
    // Authentication
    func authenticate() async throws -> OAuthToken
    func startAuthentication() async throws -> AuthenticationSession
    func completeAuthentication(authCode: String) async throws -> OAuthToken
    
    // Token management
    func getValidAccessToken() async throws -> String
    func loadExistingToken() async
    func logout() async throws
    func verifyToken() async throws -> Bool
}
```

### OAuthToken

```swift
struct OAuthToken: Codable, Sendable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int?
    let refreshToken: String?
    let scope: String?
    let createdAt: TimeInterval
    
    var isExpired: Bool { get }
    var expirationDate: Date? { get }
}
```

### AuthError

```swift
enum AuthError: LocalizedError {
    case invalidAuthCode(String)
    case stateMismatch(expected: String, received: String)
    case tokenExchangeFailed(Error)
    case tokenRefreshFailed(Error)
    case noRefreshToken
    case noValidToken
    case networkError(Error)
    case invalidResponse(String)
    case keychainError(OSStatus)
    case userCancelled
    case sessionFailed(Error)
    case tokenExpired
}
```

## Examples

### iOS App with Sign In Button

```swift
struct SignInView: View {
    @StateObject private var auth = ClaudeAuth.shared
    
    var body: some View {
        Button(action: signIn) {
            Label("Sign in with Claude", systemImage: "brain.head.profile")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(10)
        }
        .disabled(auth.isAuthenticated)
        .padding()
    }
    
    func signIn() {
        Task {
            do {
                let token = try await auth.authenticate()
                print("Signed in successfully")
            } catch {
                print("Sign in failed: \(error)")
            }
        }
    }
}
```

### macOS Menu Bar App

```swift
@main
struct MenuBarApp: App {
    @StateObject private var auth = ClaudeAuth.shared
    
    var body: some Scene {
        MenuBarExtra("Claude", systemImage: "brain.head.profile") {
            if auth.isAuthenticated {
                Text("Connected to Claude")
                Divider()
                Button("Disconnect") {
                    Task { try? await auth.logout() }
                }
            } else {
                Button("Connect to Claude") {
                    Task { try? await auth.authenticate() }
                }
            }
        }
    }
}
```

### Share Extension

```swift
class ShareViewController: UIViewController {
    let auth = ClaudeAuth.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        Task {
            guard let token = try? await auth.getValidAccessToken() else {
                // Show auth required UI
                return
            }
            
            // Process share with Claude API
            await processShare(with: token)
        }
    }
}
```

## Error Handling

```swift
do {
    let token = try await ClaudeAuth.shared.authenticate()
} catch AuthError.userCancelled {
    // User cancelled authentication
} catch AuthError.tokenExpired {
    // Token expired and couldn't be refreshed
} catch AuthError.keychainError(let status) {
    // Keychain access failed
} catch {
    // Other errors
}
```

## Testing

```swift
// Use in-memory storage for tests
let memoryStorage = MemoryTokenStorage()
let auth = ClaudeAuth(storage: memoryStorage)

// Mock token for testing
let mockToken = OAuthToken(
    accessToken: "test_token",
    tokenType: "Bearer",
    expiresIn: 3600,
    refreshToken: "refresh_token",
    scope: "test",
    createdAt: Date().timeIntervalSince1970 * 1000
)

try await memoryStorage.setToken(mockToken)
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details

## Security

- Never expose tokens in logs or UI
- Always use HTTPS for API calls
- Enable Keychain access control for sensitive apps
- Consider implementing certificate pinning for high-security apps

## Support

For issues and feature requests, please use the GitHub issue tracker.