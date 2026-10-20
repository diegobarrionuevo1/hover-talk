import Foundation

/// Deep links into System Settings for voice downloads.
///
/// Found on disk in macOS 26.2, never opened: the Accessibility settings extension
/// (`/System/Library/ExtensionKit/Extensions/AccessibilitySettingsExtension.appex`) declares
/// `legacyBundleIdentifier` "com.apple.preference.universalaccess" and
/// `allowsXAppleSystemPreferencesURLScheme` in its Info.plist, and its binary holds the string
/// "TextToSpeech" in one list with "Seeing_Display", "Seeing_Zoom" and other anchor names.
/// Whether System Settings scrolls to Spoken Content for that anchor is not verified.
public enum SystemSettingsLinks {
    /// System Settings > Accessibility > Spoken Content, where Manage Voices… downloads voices.
    public static let spokenContent = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?TextToSpeech")!
    /// System Settings > Accessibility, for when the Spoken Content link does not open.
    public static let accessibility = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess")!
}
