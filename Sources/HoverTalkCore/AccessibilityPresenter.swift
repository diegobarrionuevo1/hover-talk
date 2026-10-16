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
    /// Title of the disabled status line in the menu.
    public let statusTitle: String
    /// Whether the onboarding prompt must be shown.
    public let showsOnboarding: Bool
    /// Whether the app must keep polling for trust until the permission is granted.
    public let keepsPolling: Bool

    public init(statusTitle: String, showsOnboarding: Bool, keepsPolling: Bool) {
        self.statusTitle = statusTitle
        self.showsOnboarding = showsOnboarding
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
                showsOnboarding: false,
                keepsPolling: false
            )
        case .notGranted:
            AccessibilityPresentation(
                statusTitle: "Accessibility: Not granted",
                showsOnboarding: true,
                keepsPolling: true
            )
        }
    }
}
