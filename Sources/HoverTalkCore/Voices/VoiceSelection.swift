/// Which voice reads: one the user chose, or the best voice for each text's language. Used for
/// system voices (`Preferences.voiceSelection`) and for the voice server's voices
/// (`RemoteVoiceServerConfig.voice`).
public enum VoiceSelection: Equatable, Hashable, Sendable {
    /// The best voice for the language detected in the text being read
    /// (`VoiceCatalog.resolve(_:textLanguage:)` for system voices,
    /// `RemoteVoiceCatalog.resolve(_:textLanguage:)` for server voices).
    case automatic
    /// The voice with this `VoiceDescriptor.id`.
    case voice(id: String)

    public static let `default`: VoiceSelection = .automatic

    private static let automaticValue = "automatic"
    private static let voicePrefix = "voice:"

    /// Reads a value written by `storedValue`. Anything else, including nil and "voice:" with an
    /// empty ID, is `.automatic`.
    public init(storedValue: String?) {
        guard let storedValue, storedValue.hasPrefix(Self.voicePrefix) else {
            self = .automatic
            return
        }
        let id = String(storedValue.dropFirst(Self.voicePrefix.count))
        self = id.isEmpty ? .automatic : .voice(id: id)
    }

    /// "automatic", or "voice:" followed by the voice ID.
    public var storedValue: String {
        switch self {
        case .automatic: Self.automaticValue
        case .voice(let id): Self.voicePrefix + id
        }
    }
}
