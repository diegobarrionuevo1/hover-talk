/// Where `Preferences` keeps its values: `UserDefaults` in the app, `InMemorySettingsStorage`
/// in tests.
public protocol SettingsStorage {
    func string(forKey key: String) -> String?
    func setString(_ value: String, forKey key: String)
}

/// Settings kept in memory only, for tests and previews.
public final class InMemorySettingsStorage: SettingsStorage {
    private var values: [String: String] = [:]

    public init() {}

    public func string(forKey key: String) -> String? {
        values[key]
    }

    public func setString(_ value: String, forKey key: String) {
        values[key] = value
    }
}

/// The user's settings, read from and written to a `SettingsStorage` on every access, so
/// several owners of one storage always see the same values.
@MainActor
public final class Preferences {
    public static let readingModeKey = "readingMode"
    public static let voiceSelectionKey = "voiceSelection"
    public static let speechRateKey = "speechRate"

    private let storage: any SettingsStorage

    public init(storage: any SettingsStorage) {
        self.storage = storage
    }

    /// Stored as the mode's raw value; `ReadingMode.default` while nothing is stored, or when
    /// the stored value is not a mode this version knows.
    public var readingMode: ReadingMode {
        get { storage.string(forKey: Self.readingModeKey).flatMap(ReadingMode.init(rawValue:)) ?? .default }
        set { storage.setString(newValue.rawValue, forKey: Self.readingModeKey) }
    }

    /// Stored as `VoiceSelection.storedValue`; `.automatic` while nothing is stored. Whether the
    /// chosen voice is still installed is checked when it is used (`VoiceCatalog.resolve`).
    public var voiceSelection: VoiceSelection {
        get { VoiceSelection(storedValue: storage.string(forKey: Self.voiceSelectionKey)) }
        set { storage.setString(newValue.storedValue, forKey: Self.voiceSelectionKey) }
    }

    /// The rate the player starts with, stored as the multiplier's decimal text. A stored number
    /// goes through `SpeechRate`'s clamping; normal speed while nothing, or no number, is stored.
    public var speechRate: SpeechRate {
        get { storage.string(forKey: Self.speechRateKey).flatMap(Double.init).map(SpeechRate.init) ?? .default }
        set { storage.setString(String(newValue.multiplier), forKey: Self.speechRateKey) }
    }

    public static let remoteVoiceEnabledKey = "remoteVoiceEnabled"
    public static let remoteVoiceURLKey = "remoteVoiceURL"
    public static let remoteVoiceSelectionKey = "remoteVoiceSelection"

    /// Stored under three keys: "true" or "false", the base URL's text ("" for no address), and
    /// the server voice as `VoiceSelection.storedValue`. Anything but "true" reads as off, and a
    /// stored URL that no longer validates reads as no address.
    public var remoteVoiceServer: RemoteVoiceServerConfig {
        get {
            RemoteVoiceServerConfig(
                enabled: storage.string(forKey: Self.remoteVoiceEnabledKey) == "true",
                address: storage.string(forKey: Self.remoteVoiceURLKey).flatMap { try? RemoteVoiceServerAddress(validating: $0) },
                voice: VoiceSelection(storedValue: storage.string(forKey: Self.remoteVoiceSelectionKey))
            )
        }
        set {
            storage.setString(newValue.enabled ? "true" : "false", forKey: Self.remoteVoiceEnabledKey)
            storage.setString(newValue.address?.baseURL.absoluteString ?? "", forKey: Self.remoteVoiceURLKey)
            storage.setString(newValue.voice.storedValue, forKey: Self.remoteVoiceSelectionKey)
        }
    }
}
