/// Which voice reads: one the user chose, or the best voice for each text's language.
public enum VoiceSelection: Equatable, Hashable, Sendable {
    /// The best installed voice for the language detected in the text being read
    /// (`VoiceCatalog.resolve(_:textLanguage:)`).
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
