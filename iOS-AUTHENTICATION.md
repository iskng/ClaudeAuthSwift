# iOS Authentication with Automatic Clipboard Detection

The ClaudeAuth Swift package now includes **automatic clipboard detection** for iOS, making authentication incredibly simple.

## How It Works

### Automatic Flow (New! 🎉)

1. **User taps authenticate** → Your app calls `ClaudeAuth.shared.authenticate()`
2. **Safari opens in-app** → ASWebAuthenticationSession presents Claude's login
3. **User authorizes** → Clicks "Authorize" in Claude
4. **Code displayed** → Claude shows `code#state` on screen
5. **User copies code** → Taps copy button in Claude
6. **User closes Safari** → Swipes down or taps Done
7. **Magic happens** ✨:
   - Package detects Safari closed
   - Waits 3 seconds for user to return to app
   - Checks clipboard for valid auth code
   - If found: **Completes authentication automatically!**
   - If not found: Shows manual entry UI as fallback

## Implementation

### Simplest Possible (One Line!)

```swift
import ClaudeAuth

// That's it! This handles EVERYTHING
let token = try await ClaudeAuth.shared.authenticate()
```

### With SwiftUI

```swift
import SwiftUI
import ClaudeAuth

struct MyApp: View {
    @StateObject private var auth = ClaudeAuth.shared
    
    var body: some View {
        Button("Sign in with Claude") {
            Task {
                do {
                    let token = try await auth.authenticate()
                    print("Authenticated!")
                } catch {
                    print("Error: \(error)")
                }
            }
        }
    }
}
```

### Using the SwiftUI Modifier

```swift
struct ContentView: View {
    @State private var showAuth = false
    
    var body: some View {
        Button("Authenticate") {
            showAuth = true
        }
        .claudeAuthentication(isPresented: $showAuth) { result in
            switch result {
            case .success(let token):
                print("Got token: \(token.accessToken)")
            case .failure(let error):
                print("Failed: \(error)")
            }
        }
    }
}
```

## Advanced Configuration

```swift
// Customize the behavior
var config = ClaudeAuthSession.Configuration()
config.clipboardWaitTime = 5.0          // Wait 5 seconds after Safari closes
config.autoMonitorClipboard = true      // Monitor clipboard while Safari is open
config.showManualEntryFallback = true   // Show manual entry if clipboard fails
config.clipboardCheckInterval = 0.3     // Check clipboard every 300ms

let session = ClaudeAuthSession(configuration: config)
let token = try await session.authenticate()
```

## What Happens Behind the Scenes

### Clipboard Monitoring
- Starts monitoring when Safari opens
- Checks clipboard every 0.5 seconds (configurable)
- Validates format: `code#state`
- Verifies state matches for security

### Smart Fallback
- If clipboard detection fails → Shows manual entry UI
- If user cancels → Returns cancellation error
- If network fails → Returns network error

### Security
- State parameter validation (CSRF protection)
- PKCE code verification
- Secure Keychain storage
- No passwords or secrets in clipboard

## Manual Entry Fallback

If clipboard detection fails, users see a simple UI:

```
┌─────────────────────────────┐
│ Enter Authentication Code   │
│                             │
│ [code#state_______________] │
│                             │
│ [Cancel]        [Continue]  │
└─────────────────────────────┘
```

## Benefits Over Manual Implementation

| Feature | Manual | ClaudeAuth Package |
|---------|--------|--------------------|
| Lines of code | 200+ | 1 |
| Clipboard detection | ❌ | ✅ Automatic |
| Fallback UI | ❌ | ✅ Built-in |
| Token refresh | ❌ | ✅ Automatic |
| Keychain storage | ❌ | ✅ Secure |
| Error handling | ❌ | ✅ Complete |
| PKCE implementation | ❌ | ✅ Built-in |

## Testing

Test the flow with the included CLI tool:

```bash
cd ClaudeAuthSwift
swift run claude-auth-test
```

## Requirements

- iOS 14.0+ (for SwiftUI helpers)
- iOS 13.0+ (for core functionality)
- Swift 5.9+

## Tips

1. **Educate users**: Show them that copying the code is important
2. **Clear instructions**: Display "Copy the code and close Safari"
3. **Test the flow**: Try both clipboard success and manual entry paths
4. **Handle errors**: Check for `AuthError.userCancelled` specifically

## Troubleshooting

**Clipboard not detected?**
- User might not have copied the code
- Clipboard might have other content
- Increase `clipboardWaitTime` in configuration

**Manual entry not showing?**
- Set `showManualEntryFallback = true` in configuration

**Authentication fails?**
- Check network connection
- Verify Claude account has access
- Ensure state matches (don't modify the code string)

## Example Apps

See `/Examples` folder for:
- `SimpleiOSExample.swift` - Minimal implementation
- `iOSAuthExample.swift` - Full featured example
- `TokenManagementExample.swift` - Token refresh handling