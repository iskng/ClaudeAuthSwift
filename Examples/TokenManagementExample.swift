import SwiftUI
import ClaudeAuth

/// Example showing proper token management with auto-refresh
struct TokenManagementExample: View {
    @StateObject private var auth = ClaudeAuth.shared
    @State private var isLoading = false
    @State private var apiResponse: String = ""
    @State private var error: Error?
    @State private var showingAuth = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Token Status Card
            if let tokenInfo = auth.tokenInfo {
                TokenStatusCard(tokenInfo: tokenInfo)
            } else {
                Text("Not authenticated")
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Actions
            VStack(spacing: 12) {
                if auth.isAuthenticated {
                    // API Call Button (auto-refreshes token)
                    Button(action: makeAPICall) {
                        Label("Call Claude API", systemImage: "network")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                    
                    // Force Refresh Button
                    Button(action: forceRefreshToken) {
                        Label("Force Refresh Token", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)
                    
                    // Logout Button
                    Button(action: logout) {
                        Label("Logout", systemImage: "arrow.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                } else {
                    // Authenticate Button
                    Button(action: { showingAuth = true }) {
                        Label("Authenticate", systemImage: "person.badge.key")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            // Response Display
            if !apiResponse.isEmpty {
                ScrollView {
                    Text(apiResponse)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                .frame(maxHeight: 200)
            }
            
            // Loading Indicator
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            }
            
            // Error Display
            if let error = error {
                Text(error.localizedDescription)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 500)
        .claudeAuthenticationSheet(isPresented: $showingAuth) { result in
            switch result {
            case .success:
                Task {
                    await auth.loadExistingToken()
                }
            case .failure(let error):
                self.error = error
            }
        }
        .task {
            // Load token on appear
            await auth.loadExistingToken()
            
            // Set up timer to refresh UI when token is about to expire
            startTokenExpirationTimer()
        }
    }
    
    // MARK: - Actions
    
    private func makeAPICall() {
        isLoading = true
        error = nil
        apiResponse = ""
        
        Task {
            do {
                // This automatically refreshes the token if needed!
                let accessToken = try await auth.getValidAccessToken()
                
                // Make API call
                var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue("", forHTTPHeaderField: "X-API-Key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
                
                let body: [String: Any] = [
                    "model": "claude-sonnet-4-20250514",
                    "max_tokens": 50,
                    "messages": [
                        ["role": "user", "content": "Say 'Hello from SwiftUI!' and mention the current time."]
                    ]
                ]
                
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                
                // Alternative: Use the helper method that handles retries
                // let (data, response) = try await auth.performAuthenticatedRequest(&request)
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    apiResponse = "Status: \(httpResponse.statusCode)\n"
                    
                    if httpResponse.statusCode == 200 {
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let content = (json["content"] as? [[String: Any]])?.first?["text"] as? String {
                            apiResponse += "Claude says: \(content)"
                        }
                    } else {
                        apiResponse += String(data: data, encoding: .utf8) ?? "Unknown error"
                    }
                }
                
                // Reload token info to show updated expiration
                await auth.loadExistingToken()
                
            } catch {
                self.error = error
                apiResponse = "Error: \(error.localizedDescription)"
            }
            
            isLoading = false
        }
    }
    
    private func forceRefreshToken() {
        isLoading = true
        error = nil
        
        Task {
            do {
                _ = try await auth.ensureValidToken(forceRefresh: true)
                apiResponse = "Token refreshed successfully!"
            } catch {
                self.error = error
                apiResponse = "Refresh failed: \(error.localizedDescription)"
            }
            
            isLoading = false
        }
    }
    
    private func logout() {
        Task {
            try? await auth.logout()
            apiResponse = ""
            error = nil
        }
    }
    
    private func startTokenExpirationTimer() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                // Check if token is expiring soon
                if auth.tokenExpiringWithin(300) { // 5 minutes
                    // You could show a warning or auto-refresh
                    print("Token expiring soon!")
                }
                
                // Force UI update
                objectWillChange.send()
            }
        }
    }
}

// MARK: - Token Status Card

struct TokenStatusCard: View {
    let tokenInfo: TokenInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: tokenInfo.isExpired ? "lock.open" : "lock.fill")
                    .foregroundColor(tokenInfo.isExpired ? .orange : .green)
                
                Text("Token Status")
                    .font(.headline)
                
                Spacer()
                
                if let timeRemaining = tokenInfo.formattedTimeRemaining {
                    Text(timeRemaining)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            
            Grid(alignment: .leading, spacing: 4) {
                GridRow {
                    Text("Access Token:")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Image(systemName: tokenInfo.hasAccessToken ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(tokenInfo.hasAccessToken ? .green : .red)
                }
                
                GridRow {
                    Text("Refresh Token:")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Image(systemName: tokenInfo.hasRefreshToken ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(tokenInfo.hasRefreshToken ? .green : .red)
                }
                
                if let expirationDate = tokenInfo.expirationDate {
                    GridRow {
                        Text("Expires:")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        Text(expirationDate, style: .relative)
                            .font(.caption)
                    }
                }
                
                if let scope = tokenInfo.scope {
                    GridRow {
                        Text("Scope:")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        Text(scope)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Usage Example

/*
 This example demonstrates:
 
 1. **Automatic Token Refresh**: When calling `getValidAccessToken()`, 
    the token is automatically refreshed if expired.
 
 2. **Manual Refresh**: Using `ensureValidToken(forceRefresh: true)` 
    to manually refresh even if not expired.
 
 3. **Token Status Monitoring**: Display token expiration time and 
    refresh token availability.
 
 4. **Retry Logic**: The `performAuthenticatedRequest` helper automatically 
    retries with a refreshed token if the API returns 401.
 
 5. **Proactive Refresh**: Timer checks if token expires within 5 minutes 
    and can trigger refresh before API calls fail.
 
 Best Practices:
 - Always use `getValidAccessToken()` for API calls
 - Monitor token expiration in long-running apps
 - Handle `AuthError.noRefreshToken` by re-authenticating
 - Use the `performAuthenticatedRequest` helper for automatic retry
 */