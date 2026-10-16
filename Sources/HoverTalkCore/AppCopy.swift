/// User-facing strings for the menu bar and the onboarding prompt.
public enum AppCopy {
    public static let quitMenuTitle = "Quit \(AppInfo.name)"
    public static let openSettingsMenuTitle = "Open Accessibility Settings…"

    public static let onboardingTitle = "\(AppInfo.name) needs Accessibility access"
    public static let onboardingMessage = """
        \(AppInfo.name) uses the macOS Accessibility API to read the text under the pointer \
        so it can speak it aloud. Nothing leaves your Mac: there are no network calls and no telemetry.

        Turn on \(AppInfo.name) in System Settings > Privacy & Security > Accessibility.
        """
    public static let onboardingOpenSettingsButton = "Open System Settings"
    public static let onboardingLaterButton = "Later"
}
