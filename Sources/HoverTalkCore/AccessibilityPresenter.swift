import Foundation

/// Whether the process holds the macOS Accessibility permission.
public enum AccessibilityStatus: Equatable, Sendable {
    case granted
    case notGranted

    public init(isTrusted: Bool) {
        self = isTrusted ? .granted : .notGranted
    }
}

/// What the menu-bar app shows and does for a given permission status.
public struct AccessibilityPresentation: Equatable, Sendable {
    /// Title of the status line in the menu.
    public let statusTitle: String
    /// Whether the status line is enabled and opens the app's explanation of the permission.
    public let statusOpensExplanation: Bool
    /// Whether to ask macOS for its permission prompt at launch. The app's own explanation is
    /// not shown at launch, so a first launch shows one dialog; it stays one click away in the
    /// status line (`statusOpensExplanation`).
    public let requestsSystemPrompt: Bool
    /// Whether the app must keep polling for trust until the permission is granted.
    public let keepsPolling: Bool

    public init(statusTitle: String, statusOpensExplanation: Bool, requestsSystemPrompt: Bool, keepsPolling: Bool) {
        self.statusTitle = statusTitle
        self.statusOpensExplanation = statusOpensExplanation
        self.requestsSystemPrompt = requestsSystemPrompt
        self.keepsPolling = keepsPolling
    }
}

public enum AccessibilityPresenter {
    /// Deep link to System Settings > Privacy & Security > Accessibility.
    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    public static func presentation(for status: AccessibilityStatus) -> AccessibilityPresentation {
        switch status {
        case .granted:
            AccessibilityPresentation(
                statusTitle: "Accessibility: Granted",
                statusOpensExplanation: false,
                requestsSystemPrompt: false,
                keepsPolling: false
            )
        case .notGranted:
            AccessibilityPresentation(
                statusTitle: "Accessibility: Not granted — Open Settings…",
                statusOpensExplanation: true,
                requestsSystemPrompt: true,
                keepsPolling: true
            )
        }
    }
}
