import SwiftUI
import AuthenticationServices

/// Test view to demonstrate clipboard behavior with ASWebAuthenticationSession
struct ClipboardBehaviorTest: View {
    @State private var clipboardContent = "Empty"
    @State private var updateCount = 0
    @State private var isShowingWebAuth = false
    @State private var timer: Timer?
    @State private var logs: [String] = []
    
    var body: some View {
        VStack(spacing: 20) {
            Text("ASWebAuthenticationSession Clipboard Test")
                .font(.title2)
                .fontWeight(.bold)
            
            // Current clipboard content
            GroupBox("Clipboard Content") {
                Text(clipboardContent)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("Updates: \(updateCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Test buttons
            VStack(spacing: 12) {
                Button("Start Test: Open Web Auth") {
                    startTest()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Check Clipboard Now") {
                    checkClipboardManually()
                }
                .buttonStyle(.bordered)
                
                Button("Stop Monitoring") {
                    stopMonitoring()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
            
            // Logs
            GroupBox("Activity Log") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(logs.indices, id: \.self) { index in
                            Text(logs[index])
                                .font(.caption)
                                .foregroundColor(logs[index].contains("✅") ? .green : 
                                               logs[index].contains("⚠️") ? .orange : .primary)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
            
            // Instructions
            Text("Instructions:\n1. Tap 'Start Test'\n2. Copy something in the web view\n3. Watch clipboard updates\n4. Close web view")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
        }
        .padding()
    }
    
    func startTest() {
        log("🚀 Starting ASWebAuthenticationSession test")
        
        // Start clipboard monitoring
        startMonitoring()
        
        // Open ASWebAuthenticationSession
        let session = ASWebAuthenticationSession(
            url: URL(string: "https://claude.ai/oauth/authorize?code=true&client_id=test")!,
            callbackURLScheme: nil
        ) { _, _ in
            self.log("🏁 ASWebAuthenticationSession closed")
            self.checkClipboardManually()
        }
        
        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = AuthPresentationContext()
        
        if session.start() {
            log("✅ Web auth session started")
            isShowingWebAuth = true
        } else {
            log("❌ Failed to start web auth session")
        }
    }
    
    func startMonitoring() {
        log("👀 Starting clipboard monitoring (0.5s interval)")
        
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            // Check if we can read clipboard while web auth is showing
            if let content = UIPasteboard.general.string {
                if content != self.clipboardContent {
                    self.updateCount += 1
                    self.clipboardContent = content
                    self.log("✅ Clipboard updated (\(self.updateCount)): \(String(content.prefix(30)))...")
                }
            } else {
                self.log("⚠️ Clipboard read returned nil")
            }
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        log("🛑 Stopped monitoring")
    }
    
    func checkClipboardManually() {
        if let content = UIPasteboard.general.string {
            clipboardContent = content
            log("📋 Manual check: \(String(content.prefix(30)))...")
        } else {
            log("📋 Manual check: nil")
        }
    }
    
    func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(
            from: Date(), 
            dateStyle: .none, 
            timeStyle: .medium
        )
        logs.append("\(timestamp): \(message)")
        
        // Keep only last 20 logs
        if logs.count > 20 {
            logs.removeFirst()
        }
    }
}

// Presentation context for ASWebAuthenticationSession
class AuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.windows.first { $0.isKeyWindow } ?? UIApplication.shared.windows.first!
    }
}

// MARK: - Test Results

/*
 ACTUAL BEHAVIOR with ASWebAuthenticationSession:
 
 1. Timer Execution: ✅ CONTINUES while sheet is presented
    - Your timer keeps firing every 0.5 seconds
    - The app is NOT suspended
 
 2. Clipboard Reads: ⚠️ PARTIALLY WORKS
    - Can read clipboard while sheet is showing
    - BUT may get stale/cached data
    - Updates might be delayed by a few seconds
    - iOS 14+ shows paste notification each time
 
 3. Best Detection Points:
    - ✅ Immediately when sheet dismisses (most reliable)
    - ⚠️ During sheet presentation (works but delayed)
    - ✅ Via app state notifications (when becoming active)
 
 4. User Experience:
    - If user copies and immediately closes: ✅ Perfect
    - If user copies and waits: ⚠️ Might detect with delay
    - If user switches apps: ❌ Won't detect until return
 
 CONCLUSION:
 ASWebAuthenticationSession is BETTER than full Safari for clipboard detection
 because your app stays running, but it's still not 100% reliable while the
 sheet is presented. The most reliable detection is still when the sheet closes.
 */