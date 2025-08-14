import SwiftUI
import ClaudeAuth

/// Test view to verify the continuation misuse fix
struct ContinuationTestView: View {
    @State private var status = "Ready"
    @State private var isAuthenticating = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Continuation Fix Test")
                .font(.title)
            
            Text(status)
                .font(.headline)
                .foregroundColor(status.contains("Error") ? .red : .green)
            
            Button("Test Authentication") {
                testAuth()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating)
            
            if isAuthenticating {
                ProgressView()
            }
        }
        .padding()
    }
    
    func testAuth() {
        isAuthenticating = true
        status = "Authenticating..."
        
        Task {
            do {
                // This should no longer cause continuation misuse
                let token = try await ClaudeAuth.shared.authenticate()
                
                await MainActor.run {
                    status = "✅ Success! Token obtained"
                    isAuthenticating = false
                }
            } catch {
                await MainActor.run {
                    // Even if there's an error, it shouldn't crash with continuation misuse
                    status = "Error: \(error.localizedDescription)"
                    isAuthenticating = false
                }
            }
        }
    }
}

// MARK: - What Was Fixed

/*
 THE PROBLEM:
 - The continuation in startWebSession was being resumed multiple times
 - This happened when both clipboard detection AND error handling tried to complete
 
 THE FIX:
 1. Added `hasCompleted` flag to track if continuation was already resumed
 2. Guard all completion calls with `guard !hasCompleted else { return }`
 3. Set `hasCompleted = true` before resuming continuation
 
 RESULT:
 - Continuation can only be resumed once
 - Subsequent attempts are safely ignored
 - No more "SWIFT TASK CONTINUATION MISUSE" crash
 
 The specific error you saw:
 "Invalid \"code\" in request" (HTTP 400)
 
 This means the authorization code was invalid or expired, but the crash
 was because the error tried to resume the continuation after clipboard
 detection already had.
 */