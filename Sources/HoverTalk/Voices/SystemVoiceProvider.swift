import AppKit
import AVFoundation
import HoverTalkCore

/// The installed system voices as `VoiceDescriptor`s. The list is read again by `refresh()`,
/// which the app calls when the status menu opens and when the Settings window appears, and
/// whenever macOS posts `AVSpeechSynthesizer.availableVoicesDidChangeNotification` (voices
/// downloaded or removed while the app runs).
@MainActor
final class SystemVoiceProvider {
    /// Called after the notification refreshed the list.
    var onChange: (() -> Void)?
    private(set) var voices: [VoiceDescriptor] = []
    /// Kept for the app's lifetime; the block holds the provider weakly.
    private var observer: (any NSObjectProtocol)?

    init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // `queue: .main` runs the block on the main queue.
            MainActor.assumeIsolated {
                self?.refresh()
                self?.onChange?()
            }
        }
    }

    func refresh() {
        voices = AVSpeechSynthesisVoice.speechVoices().map(Self.descriptor(for:))
    }

    /// The catalog of `voices` for the user's languages (`Locale.preferredLanguages`).
    func catalog() -> VoiceCatalog {
        VoiceCatalog(voices: voices, preferredLanguages: Locale.preferredLanguages)
    }

    static func descriptor(for voice: AVSpeechSynthesisVoice) -> VoiceDescriptor {
        let quality: VoiceDescriptor.Quality = switch voice.quality {
        case .premium: .premium
        case .enhanced: .enhanced
        default: .default
        }
        return VoiceDescriptor(
            id: voice.identifier,
            name: voice.name,
            language: voice.language,
            quality: quality,
            source: .system,
            isNovelty: voice.voiceTraits.contains(.isNoveltyVoice)
        )
    }
}

/// Where voices are downloaded.
enum VoiceDownloads {
    /// Opens System Settings > Accessibility > Spoken Content, or the Accessibility pane when no
    /// app opened that link. `NSWorkspace.open(_:)` only reports whether an app opened the URL,
    /// not whether System Settings understood its anchor.
    static func openSystemSettings() {
        if !NSWorkspace.shared.open(SystemSettingsLinks.spokenContent) {
            NSWorkspace.shared.open(SystemSettingsLinks.accessibility)
        }
    }
}

/// Language names for headers and search, in English like the rest of the app's UI.
enum VoiceLanguageNames {
    private static let locale = Locale(identifier: "en_US")

    /// For example "Spanish (Mexico)" for "es-MX"; the tag itself when it has no name.
    static func name(for language: String) -> String {
        locale.localizedString(forIdentifier: language) ?? language
    }
}
