import SwiftUI
#if canImport(WebKit)
import WebKit
#endif

/// SwiftUI view for Claude authentication
@available(iOS 14.0, macOS 11.0, *)
public struct ClaudeAuthenticationView: View {
    @StateObject private var auth = ClaudeAuth.shared
    @State private var authSession: AuthenticationSession?
    @State private var authCode: String = ""
    @State private var isLoading = false
    @State private var error: Error?
    @State private var showingWebView = false
    
    /// Completion handler
    private let onCompletion: (Result<OAuthToken, Error>) -> Void
    
    /// Initialize authentication view
    /// - Parameter onCompletion: Callback when authentication completes
    public init(onCompletion: @escaping (Result<OAuthToken, Error>) -> Void) {
        self.onCompletion = onCompletion
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                
                Text("Claude Authentication")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Sign in with your Claude account")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)
            
            Spacer()
            
            // Authentication flow
            VStack(spacing: 16) {
                if authSession != nil {
                    // Show instructions
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Browser opened", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        
                        Label("Click 'Authorize' in browser", systemImage: "hand.tap")
                        
                        Label("Copy the authentication code", systemImage: "doc.on.clipboard")
                        
                        Label("Paste the code below", systemImage: "arrow.down.circle")
                    }
                    .font(.callout)
                    .padding()
                    #if os(iOS) || os(tvOS)
                    .background(Color(.systemGray6))
                    #else
                    .background(Color.gray.opacity(0.1))
                    #endif
                    .cornerRadius(12)
                    
                    // Code input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Authentication Code")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("Paste code#state here", text: $authCode)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            #if os(iOS) || os(tvOS)
                            .autocapitalization(.none)
                            .keyboardType(.asciiCapable)
                            #endif
                            .disableAutocorrection(true)
                    }
                    
                    // Actions
                    HStack(spacing: 12) {
                        Button("Cancel") {
                            cancelAuthentication()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Continue") {
                            completeAuthentication()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(authCode.isEmpty || isLoading)
                    }
                } else {
                    // Start button
                    Button(action: startAuthentication) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "person.badge.key")
                            }
                            Text("Sign in with Claude")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Error display
            if let error = error {
                ErrorView(error: error) {
                    self.error = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 500)
        #if os(iOS)
        .navigationBarHidden(true)
        #endif
    }
    
    private func startAuthentication() {
        isLoading = true
        error = nil
        
        Task {
            do {
                let session = try await auth.startAuthentication()
                await MainActor.run {
                    self.authSession = session
                    self.isLoading = false
                }
                
                // Open browser
                #if os(iOS)
                await UIApplication.shared.open(session.url)
                #elseif os(macOS)
                NSWorkspace.shared.open(session.url)
                #endif
            } catch {
                await MainActor.run {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }
    
    private func completeAuthentication() {
        isLoading = true
        error = nil
        
        Task {
            do {
                let token = try await auth.completeAuthentication(authCode: authCode)
                await MainActor.run {
                    onCompletion(.success(token))
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }
    
    private func cancelAuthentication() {
        authSession = nil
        authCode = ""
        error = nil
        onCompletion(.failure(AuthError.userCancelled))
    }
}

// MARK: - Error View

@available(iOS 14.0, macOS 11.0, *)
struct ErrorView: View {
    let error: Error
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                
                Text("Authentication Error")
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            if let authError = error as? AuthError,
               let suggestion = authError.recoverySuggestion {
                Text(suggestion)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

// MARK: - View Modifier

@available(iOS 14.0, macOS 11.0, *)
public extension View {
    /// Present Claude authentication sheet
    /// - Parameters:
    ///   - isPresented: Binding to control presentation
    ///   - onCompletion: Callback when authentication completes
    func claudeAuthenticationSheet(
        isPresented: Binding<Bool>,
        onCompletion: @escaping (Result<OAuthToken, Error>) -> Void
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            ClaudeAuthenticationView { result in
                isPresented.wrappedValue = false
                onCompletion(result)
            }
        }
    }
}