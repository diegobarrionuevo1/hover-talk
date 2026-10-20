/// A voice the user can choose, independent of the engine that speaks with it.
public struct VoiceDescriptor: Equatable, Hashable, Sendable, Identifiable {
    /// How natural a voice sounds, as the system reports it. Ordered from worst to best.
    public enum Quality: Int, Comparable, CaseIterable, Sendable {
        case `default`
        case enhanced
        case premium

        public static func < (lhs: Quality, rhs: Quality) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// The engine that owns the voice.
    public enum Source: Equatable, Hashable, Sendable {
        /// An `AVSpeechSynthesisVoice`; `id` is its identifier.
        case system
    }

    public let id: String
    /// The name the source reports, which may already end in a quality suffix such as
    /// " (Premium)"; `displayName` handles that.
    public let name: String
    /// BCP-47 language tag, for example "es-MX".
    public let language: String
    public let quality: Quality
    public let source: Source
    /// Whether the source itself flags the voice as a novelty (character) voice.
    /// `VoiceCatalog.isNovelty(_:)` also applies its own identifier rules.
    public let isNovelty: Bool

    public init(id: String, name: String, language: String, quality: Quality, source: Source = .system, isNovelty: Bool = false) {
        self.id = id
        self.name = name
        self.language = language
        self.quality = quality
        self.source = source
        self.isNovelty = isNovelty
    }

    /// `name` without a trailing " (Premium)" or " (Enhanced)", which the system may already
    /// include: macOS 26.2 reports the premium voice Marisol as "Marisol (Premium)".
    public var baseName: String {
        for suffix in Quality.allCases.compactMap(\.label).map({ " (\($0))" }) where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    /// The base name followed by the quality, for example "Paulina (Premium)"; a default-quality
    /// voice shows its base name alone.
    public var displayName: String {
        quality.label.map { "\(baseName) (\($0))" } ?? baseName
    }
}

extension VoiceDescriptor.Quality {
    /// The word the system uses for the quality; nil for `.default`, which shows no label.
    public var label: String? {
        switch self {
        case .default: nil
        case .enhanced: "Enhanced"
        case .premium: "Premium"
        }
    }
}
