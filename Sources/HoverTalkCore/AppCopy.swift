/// User-facing strings for the menu bar and the onboarding prompt.
public enum AppCopy {
    public static let quitMenuTitle = "Quit \(AppInfo.name)"
    public static let openSettingsMenuTitle = "Open Accessibility Settings…"

    /// The menu item that starts the picker, with its hotkey after two spaces, or alone when
    /// the hotkey could not be registered (`nil`).
    public static func pickTextMenuTitle(for hotkey: Hotkey?) -> String {
        let title = "Pick Text to Read"
        return hotkey.map { "\(title)  \($0.displayString)" } ?? title
    }

    /// Explains why picking stopped or did not start, with the onboarding title and buttons.
    public static let pickerNeedsAccessibilityMessage = """
        Picking text needs the Accessibility permission. Turn on \(AppInfo.name) in \
        System Settings > Privacy & Security > Accessibility.

        If it is already on, turn it off and on again: macOS can keep an outdated permission \
        after \(AppInfo.name) is rebuilt or updated.
        """

    public static let onboardingTitle = "\(AppInfo.name) needs Accessibility access"
    public static let onboardingMessage = """
        \(AppInfo.name) uses the macOS Accessibility API to read the text under the pointer \
        so it can speak it aloud. Nothing leaves your Mac: there are no network calls and no telemetry.

        Turn on \(AppInfo.name) in System Settings > Privacy & Security > Accessibility.
        """
    public static let onboardingOpenSettingsButton = "Open System Settings"
    public static let onboardingLaterButton = "Later"
}
