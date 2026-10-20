/// User-facing strings for the menu bar and the onboarding prompt.
public enum AppCopy {
    public static let quitMenuTitle = "Quit \(AppInfo.name)"
    public static let openSettingsMenuTitle = "Open Accessibility Settings…"
    /// The checkable menu item for `ReadingMode.continuous`.
    public static let continueReadingMenuTitle = "Continue Reading Below"

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

    // MARK: - Voices

    public static let voiceMenuTitle = "Voice"
    /// `VoiceSelection.automatic`, in the Voice menu and the Settings window.
    public static let automaticVoiceTitle = "Automatic (best for the text's language)"
    public static let moreVoicesMenuTitle = "More Voices in Settings…"
    /// Opens `SystemSettingsLinks.spokenContent`.
    public static let downloadMoreVoicesTitle = "Download More Voices…"
    /// "Manage Voices…" is the voice picker's own item (macOS 26.2, TextToSpeechVoiceBankingUI).
    public static let voiceQualityHint = """
        Premium and Enhanced voices sound much better. Download them in System Settings > \
        Accessibility > Spoken Content > System voice > Manage Voices…
        """
    /// The same hint in two short lines, for the Voice menu.
    public static let voiceQualityMenuHint = """
        Premium and Enhanced voices sound much better.
        Download them in Spoken Content > System voice > Manage Voices…
        """

    // MARK: - Settings window

    public static let settingsMenuTitle = "Settings…"
    public static let settingsWindowTitle = "\(AppInfo.name) Settings"
    public static let voiceSectionTitle = "Voice"
    public static let voiceSearchPlaceholder = "Search voices or languages"
    public static let previewVoiceButton = "Preview"
    public static let speedSectionTitle = "Speed"
    public static let readingSectionTitle = "Reading"
    /// The toggle for `ReadingMode.continuous`.
    public static let continuousReadingSettingTitle = "Continue reading below the picked paragraph"
    public static let voiceServerSectionTitle = "Voice Server"
    public static let voiceServerPlaceholder = "Not available yet. Reading with a speech server you host yourself comes in a later version."
}
