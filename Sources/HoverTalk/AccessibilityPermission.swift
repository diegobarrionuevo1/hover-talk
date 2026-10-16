// AXUIElement.h declares kAXTrustedCheckOptionPrompt as a non-const C global, which Swift 6
// rejects as shared mutable state; @preconcurrency limits that check to this file's AX calls.
@preconcurrency import ApplicationServices
import HoverTalkCore

/// Thin wrapper over the macOS Accessibility trust API.
enum AccessibilityPermission {
    static func currentStatus() -> AccessibilityStatus {
        AccessibilityStatus(isTrusted: AXIsProcessTrusted())
    }

    /// Asks macOS to show its own permission prompt, which also adds the app to the
    /// Privacy & Security > Accessibility list. The prompt is asynchronous; the returned
    /// status reflects trust at call time.
    @discardableResult
    static func requestWithSystemPrompt() -> AccessibilityStatus {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AccessibilityStatus(isTrusted: AXIsProcessTrustedWithOptions(options))
    }
}
