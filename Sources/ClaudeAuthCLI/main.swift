import Foundation
import ClaudeAuth

// ANSI color codes for terminal output
struct Colors {
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let blue = "\u{001B}[34m"
    static let red = "\u{001B}[31m"
    static let cyan = "\u{001B}[36m"
}

@main
struct ClaudeAuthCLI {
    static func main() async {
        print("\(Colors.bold)\(Colors.blue)🔐 Claude Auth Swift - OAuth Test Tool\(Colors.reset)")
        print("\(Colors.cyan)Testing OAuth authentication flow with Claude AI\(Colors.reset)\n")
        
        // Use memory storage for testing
        let storage = MemoryTokenStorage()
        let auth = ClaudeAuth(configuration: .claude, storage: storage)
        
        do {
            // Check if already authenticated
            await auth.loadExistingToken()
            if auth.isAuthenticated {
                print("\(Colors.green)✓ Found existing token\(Colors.reset)")
                if let token = auth.currentToken {
                    printTokenInfo(token)
                }
                
                print("\n\(Colors.yellow)Testing token validity...\(Colors.reset)")
                let isValid = try await auth.verifyToken()
                if isValid {
                    print("\(Colors.green)✓ Token is valid and working!\(Colors.reset)")
                } else {
                    print("\(Colors.red)✗ Token verification failed\(Colors.reset)")
                }
            } else {
                // Start new authentication
                print("\(Colors.yellow)Starting OAuth authentication flow...\(Colors.reset)\n")
                
                // Start authentication session
                let session = try await auth.startAuthentication()
                
                print("\(Colors.bold)Step 1:\(Colors.reset) Opening Claude authentication page...")
                print("\(Colors.cyan)URL:\(Colors.reset) \(session.url.absoluteString)\n")
                
                // Open browser
                #if os(macOS)
                let process = Process()
                process.launchPath = "/usr/bin/open"
                process.arguments = [session.url.absoluteString]
                process.launch()
                print("\(Colors.green)✓ Browser opened\(Colors.reset)\n")
                #else
                print("\(Colors.yellow)Please open this URL in your browser:\(Colors.reset)")
                print(session.url.absoluteString)
                print("")
                #endif
                
                print("\(Colors.bold)Step 2:\(Colors.reset) Authorize the application")
                print("  1. Click '\(Colors.green)Authorize\(Colors.reset)' in the browser")
                print("  2. Copy the authentication code shown\n")
                
                print("\(Colors.bold)Step 3:\(Colors.reset) Paste the authentication code below")
                print("\(Colors.cyan)Format: code#state\(Colors.reset)")
                print("Authentication Code: ", terminator: "")
                fflush(stdout)
                
                guard let authCode = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    print("\(Colors.red)✗ No code provided\(Colors.reset)")
                    return
                }
                
                print("\n\(Colors.yellow)Exchanging code for token...\(Colors.reset)")
                
                let token = try await auth.completeAuthentication(authCode: authCode)
                
                print("\(Colors.green)✓ Authentication successful!\(Colors.reset)\n")
                printTokenInfo(token)
                
                // Verify token works
                print("\n\(Colors.yellow)Verifying token with Claude API...\(Colors.reset)")
                let isValid = try await auth.verifyToken()
                
                if isValid {
                    print("\(Colors.green)✓ Token verified successfully!\(Colors.reset)")
                    print("\(Colors.cyan)You can now use this token to access Claude AI API.\(Colors.reset)")
                } else {
                    print("\(Colors.red)✗ Token verification failed\(Colors.reset)")
                }
            }
            
            // Test token refresh if we have a refresh token
            if let token = auth.currentToken, token.refreshToken != nil {
                print("\n\(Colors.yellow)Testing token refresh...\(Colors.reset)")
                
                // Force refresh by getting valid token
                let accessToken = try await auth.getValidAccessToken()
                print("\(Colors.green)✓ Token refresh successful\(Colors.reset)")
                print("\(Colors.cyan)Access Token (first 20 chars):\(Colors.reset) \(String(accessToken.prefix(20)))...")
            }
            
            // Export token for use with other tools
            if let token = auth.currentToken {
                print("\n\(Colors.bold)Export for Claude Code CLI:\(Colors.reset)")
                print("\(Colors.cyan)export CLAUDE_CODE_OAUTH_TOKEN=\"\(token.accessToken)\"\(Colors.reset)")
            }
            
        } catch AuthError.userCancelled {
            print("\(Colors.yellow)Authentication cancelled by user\(Colors.reset)")
        } catch AuthError.invalidAuthCode(let code) {
            print("\(Colors.red)✗ Invalid authentication code format: \(code)\(Colors.reset)")
            print("Expected format: code#state")
        } catch AuthError.stateMismatch(let expected, let received) {
            print("\(Colors.red)✗ State mismatch\(Colors.reset)")
            print("Expected: \(expected)")
            print("Received: \(received)")
        } catch {
            print("\(Colors.red)✗ Error: \(error.localizedDescription)\(Colors.reset)")
            if let authError = error as? AuthError {
                if let suggestion = authError.recoverySuggestion {
                    print("\(Colors.yellow)Suggestion: \(suggestion)\(Colors.reset)")
                }
            }
        }
    }
    
    static func printTokenInfo(_ token: OAuthToken) {
        print("\(Colors.bold)Token Information:\(Colors.reset)")
        print("  • Type: \(token.tokenType)")
        print("  • Scope: \(token.scope ?? "N/A")")
        print("  • Access Token: \(String(token.accessToken.prefix(20)))...")
        
        if let refreshToken = token.refreshToken {
            print("  • Refresh Token: \(String(refreshToken.prefix(20)))...")
        }
        
        if let expirationDate = token.expirationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            print("  • Expires: \(formatter.string(from: expirationDate))")
            
            let timeRemaining = expirationDate.timeIntervalSinceNow
            if timeRemaining > 0 {
                let hours = Int(timeRemaining) / 3600
                let minutes = (Int(timeRemaining) % 3600) / 60
                print("  • Time Remaining: \(hours)h \(minutes)m")
            }
        }
    }
}