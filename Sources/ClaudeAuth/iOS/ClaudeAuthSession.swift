#if os(iOS) || os(visionOS)
import Foundation
import AuthenticationServices
import UIKit
import SwiftUI

/// Enhanced authentication session with automatic clipboard detection
@MainActor
public class ClaudeAuthSession: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var isAuthenticating = false
    @Published public private(set) var error: Error?
    @Published public private(set) var needsManualCodeEntry = false
    
    // MARK: - Private Properties
    
    private var authSession: ASWebAuthenticationSession?
    private var currentPKCE: PKCE?
    private var currentState: String?
    private var clipboardMonitorTimer: Timer?
    private var previousClipboardContent: String?
    private var authCompletion: ((Result<OAuthToken, Error>) -> Void)?
    private var hasCompleted = false
    private let auth: ClaudeAuth
    
    // MARK: - Configuration
    
    public struct Configuration {
        /// Time to wait for clipboard content after session closes (seconds)
        public var clipboardWaitTime: TimeInterval = 3.0
        
        /// Whether to show manual entry UI if clipboard detection fails
        public var showManualEntryFallback: Bool = true
        
        /// Automatically start monitoring clipboard when session starts
        public var autoMonitorClipboard: Bool = true
        
        /// Check clipboard every N seconds while session is active
        public var clipboardCheckInterval: TimeInterval = 0.5
        
        /// Skip clipboard entirely and go straight to manual entry
        public var skipClipboard: Bool = false
        
        /// Presenting view controller for ASWebAuthenticationSession
        public weak var presentingViewController: UIViewController?
        
        public init() {}
    }
    
    private let configuration: Configuration
    
    // MARK: - Initialization
    
    public init(auth: ClaudeAuth = .shared, configuration: Configuration = Configuration()) {
        self.auth = auth
        self.configuration = configuration
        super.init()
        
        // Listen for app becoming active to check clipboard
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func appDidBecomeActive() {
        // App returned to foreground - check clipboard if we're waiting for code
        if isAuthenticating && currentState != nil && !needsManualCodeEntry {
            checkClipboard()
        }
    }
    
    // MARK: - Public Methods
    
    /// Start authentication with automatic clipboard detection
    @discardableResult
    public func authenticate() async throws -> OAuthToken {
        // Reset state
        error = nil
        needsManualCodeEntry = false
        isAuthenticating = true
        
        // Store current clipboard to detect changes
        if configuration.autoMonitorClipboard {
            previousClipboardContent = UIPasteboard.general.string
        }
        
        do {
            // Start OAuth session
            let session = try await auth.startAuthentication()
            self.currentPKCE = PKCE(codeVerifier: session.codeVerifier)
            self.currentState = session.state
            
            // Start web authentication session
            let token = try await startWebSession(with: session.url)
            
            isAuthenticating = false
            return token
            
        } catch {
            self.error = error
            isAuthenticating = false
            
            // Show manual entry if configured
            if configuration.showManualEntryFallback && !isUserCancellation(error) {
                needsManualCodeEntry = true
            }
            
            throw error
        }
    }
    
    /// Complete authentication with manually entered code
    public func completeWithManualCode(_ code: String) async throws -> OAuthToken {
        guard let state = currentState else {
            throw AuthError.invalidResponse("No active authentication session")
        }
        
        needsManualCodeEntry = false
        isAuthenticating = true
        
        do {
            // Validate code format
            let validatedCode = try validateAndFormatCode(code, expectedState: state)
            
            // Complete authentication
            let token = try await auth.completeAuthentication(authCode: validatedCode)
            
            isAuthenticating = false
            return token
            
        } catch {
            self.error = error
            isAuthenticating = false
            needsManualCodeEntry = true
            throw error
        }
    }
    
    /// Cancel the current authentication session
    public func cancel() {
        guard !hasCompleted else { return }
        
        authSession?.cancel()
        clipboardMonitorTimer?.invalidate()
        isAuthenticating = false
        needsManualCodeEntry = false
        hasCompleted = true
        authCompletion?(.failure(AuthError.userCancelled))
    }
    
    // MARK: - Private Methods
    
    private func startWebSession(with url: URL) async throws -> OAuthToken {
        // Reset completion flag
        hasCompleted = false
        
        return try await withCheckedThrowingContinuation { continuation in
            self.authCompletion = { result in
                // Ensure we only resume once
                guard !self.hasCompleted else { return }
                self.hasCompleted = true
                continuation.resume(with: result)
            }
            
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: nil, // Using manual code entry
                completionHandler: handleSessionCompletion
            )
            
            // Configure session
            session.prefersEphemeralWebBrowserSession = false // Allow saved logins
            session.presentationContextProvider = self
            
            self.authSession = session
            
            // Start clipboard monitoring if configured and not skipped
            if configuration.autoMonitorClipboard && !configuration.skipClipboard {
                startClipboardMonitoring()
            }
            
            // Start the session
            if !session.start() {
                continuation.resume(throwing: AuthError.sessionFailed(
                    NSError(domain: "ClaudeAuth", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to start authentication session"
                    ])
                ))
            }
        }
    }
    
    private func handleSessionCompletion(url: URL?, error: Error?) {
        // Session closed - check for errors first
        if let error = error {
            if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                // User cancelled - check clipboard unless skipped
                if configuration.skipClipboard {
                    handleNoCodeFound()
                } else {
                    checkClipboardImmediately()
                }
            } else {
                // Real error
                stopClipboardMonitoring()
                authCompletion?(.failure(AuthError.sessionFailed(error)))
            }
            return
        }
        
        // Session completed without callback URL (expected for manual code)
        if configuration.skipClipboard {
            handleNoCodeFound()
        } else {
            checkClipboardImmediately()
        }
    }
    
    private func checkClipboardImmediately() {
        // First, try immediate check (user might have already copied)
        if let currentContent = UIPasteboard.general.string,
           let state = currentState,
           isValidAuthCode(currentContent, expectedState: state) {
            // Found it immediately!
            stopClipboardMonitoring()
            completeWithClipboardContent(currentContent)
        } else {
            // Otherwise wait for clipboard
            waitForClipboardContent()
        }
    }
    
    private func completeWithClipboardContent(_ content: String) {
        // Check if already completed
        guard !hasCompleted else { return }
        
        Task { @MainActor in
            do {
                let token = try await auth.completeAuthentication(authCode: content)
                authCompletion?(.success(token))
            } catch {
                authCompletion?(.failure(error))
            }
        }
    }
    
    // MARK: - Clipboard Monitoring
    
    private func startClipboardMonitoring() {
        clipboardMonitorTimer?.invalidate()
        
        clipboardMonitorTimer = Timer.scheduledTimer(withTimeInterval: configuration.clipboardCheckInterval, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    private func stopClipboardMonitoring() {
        clipboardMonitorTimer?.invalidate()
        clipboardMonitorTimer = nil
    }
    
    private func checkClipboard() {
        guard let currentContent = UIPasteboard.general.string,
              currentContent != previousClipboardContent,
              let state = currentState else {
            return
        }
        
        // Check if clipboard contains valid auth code
        if isValidAuthCode(currentContent, expectedState: state) {
            stopClipboardMonitoring()
            
            // Complete authentication with clipboard content
            completeWithClipboardContent(currentContent)
        }
        
        previousClipboardContent = currentContent
    }
    
    private func waitForClipboardContent() {
        // Give user time to switch back to app with code in clipboard
        DispatchQueue.main.asyncAfter(deadline: .now() + configuration.clipboardWaitTime) { [weak self] in
            guard let self = self else { return }
            
            self.stopClipboardMonitoring()
            
            // Final clipboard check
            if let clipboardContent = UIPasteboard.general.string,
               let state = self.currentState,
               self.isValidAuthCode(clipboardContent, expectedState: state) {
                
                // Found valid code in clipboard
                self.completeWithClipboardContent(clipboardContent)
            } else {
                // No valid code found
                self.handleNoCodeFound()
            }
        }
    }
    
    private func handleNoCodeFound() {
        // Check if already completed
        guard !hasCompleted else { return }
        
        if configuration.showManualEntryFallback {
            // Trigger manual entry UI
            needsManualCodeEntry = true
            // Don't call completion yet - wait for manual entry
        } else {
            authCompletion?(.failure(AuthError.invalidResponse("No authentication code found in clipboard")))
        }
    }
    
    // MARK: - Validation
    
    private func isValidAuthCode(_ code: String, expectedState: String) -> Bool {
        // Check if code matches expected format: code#state
        let components = code.split(separator: "#").map(String.init)
        guard components.count == 2 else { return false }
        
        // Validate state matches
        return components[1] == expectedState
    }
    
    private func validateAndFormatCode(_ code: String, expectedState: String) throws -> String {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If already in correct format
        if isValidAuthCode(trimmedCode, expectedState: expectedState) {
            return trimmedCode
        }
        
        // Try to add state if missing
        if !trimmedCode.contains("#") {
            let formatted = "\(trimmedCode)#\(expectedState)"
            if isValidAuthCode(formatted, expectedState: expectedState) {
                return formatted
            }
        }
        
        throw AuthError.invalidAuthCode(code)
    }
    
    private func isUserCancellation(_ error: Error) -> Bool {
        if case AuthError.userCancelled = error {
            return true
        }
        if let nsError = error as NSError?,
           nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
            return true
        }
        return false
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension ClaudeAuthSession: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Try to use configured view controller
        if let window = configuration.presentingViewController?.view.window {
            return window
        }
        
        // Fallback to key window
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            return window
        }
        
        // Last resort - first window
        return UIApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

// MARK: - SwiftUI Integration

/// SwiftUI view modifier for easy authentication
@available(iOS 14.0, *)
public struct ClaudeAuthModifier: ViewModifier {
    @StateObject private var session = ClaudeAuthSession()
    @Binding var isPresented: Bool
    let onCompletion: (Result<OAuthToken, Error>) -> Void
    
    public func body(content: Content) -> some View {
        content
            .sheet(isPresented: $session.needsManualCodeEntry) {
                ManualCodeEntryView(session: session, onCompletion: onCompletion)
            }
            .onChange(of: isPresented) { newValue in
                if newValue {
                    Task {
                        do {
                            let token = try await session.authenticate()
                            await MainActor.run {
                                isPresented = false
                                onCompletion(.success(token))
                            }
                        } catch {
                            if !session.needsManualCodeEntry {
                                await MainActor.run {
                                    isPresented = false
                                    onCompletion(.failure(error))
                                }
                            }
                        }
                    }
                }
            }
    }
}

/// Manual code entry view for fallback
@available(iOS 14.0, *)
public struct ManualCodeEntryView: View {
    @ObservedObject var session: ClaudeAuthSession
    @State private var authCode = ""
    @Environment(\.dismiss) private var dismiss
    let onCompletion: (Result<OAuthToken, Error>) -> Void
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Enter Authentication Code")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Copy the code from Claude (including #state)")
                    .foregroundColor(.secondary)
                
                TextField("code#state", text: $authCode)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                if let error = session.error {
                    Text(error.localizedDescription)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                HStack {
                    Button("Cancel") {
                        dismiss()
                        onCompletion(.failure(AuthError.userCancelled))
                    }
                    .frame(maxWidth: .infinity)
                    
                    Button("Continue") {
                        Task {
                            do {
                                let token = try await session.completeWithManualCode(authCode)
                                await MainActor.run {
                                    dismiss()
                                    onCompletion(.success(token))
                                }
                            } catch {
                                // Error is shown in UI
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(authCode.isEmpty)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - View Extension

@available(iOS 14.0, *)
public extension View {
    /// Authenticate with Claude using automatic clipboard detection
    func claudeAuthentication(isPresented: Binding<Bool>,
                            onCompletion: @escaping (Result<OAuthToken, Error>) -> Void) -> some View {
        self.modifier(ClaudeAuthModifier(isPresented: isPresented, onCompletion: onCompletion))
    }
}

#endif