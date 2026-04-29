import AppKit
import ApplicationServices

@MainActor
enum AccessibilityPrompt {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func ensureTrusted(prompt: Bool = true) -> Bool {
        // kAXTrustedCheckOptionPrompt's documented value is "AXTrustedCheckOptionPrompt".
        // Using the literal sidesteps Swift 6 strict-concurrency on the C global.
        let opts: CFDictionary = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func openPrivacyPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
