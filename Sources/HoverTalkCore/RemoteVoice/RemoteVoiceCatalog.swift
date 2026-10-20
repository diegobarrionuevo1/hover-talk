import Foundation

/// The voices a voice server offers, and the rules that pick one for a text.
///
/// Voice names in Kokoro's shape, `<language letter><f|m>_<name>` such as "ef_dora", carry their
/// language and gender. Other names, and Kokoro-shaped names with a language letter not in
/// `kokoroLanguages`, get the BCP-47 tag "und" (undetermined): the automatic choice never picks
/// them (`automaticVoice(for:)`), but they can still be chosen explicitly.
public struct RemoteVoiceCatalog: Equatable, Sendable {
    public enum ParseError: Error, Equatable, Sendable {
        /// Not JSON, or no `voices` list at the top level.
        case invalidResponse
    }

    /// Kokoro's language letters.
    static let kokoroLanguages: [Character: String] = [
        "a": "en-US", "b": "en-GB", "e": "es", "f": "fr-FR", "h": "hi",
        "i": "it", "j": "ja", "p": "pt-BR", "z": "zh",
    ]

    /// The preferred automatic voices chosen in the T6d plan: "af_heart" for American English and
    /// "ef_dora" for Spanish. The automatic choice takes them when the server lists them.
    static let qualityPicks: Set<String> = ["af_heart", "ef_dora"]

    static let undeterminedLanguage = "und"

    /// In server order.
    public let voices: [VoiceDescriptor]
    /// The user's languages, most preferred first, for example ["es-AR", "en-US"].
    public let preferredLanguages: [String]

    public init(voices: [VoiceDescriptor], preferredLanguages: [String]) {
        self.voices = voices
        self.preferredLanguages = preferredLanguages
    }

    /// Parses `GET /v1/audio/voices`: `{"voices": [...]}` whose entries are voice names or
    /// objects with an `id` (and optionally a `name`). Other entries, empty names and repeated
    /// names are skipped; the rest keep the server's order.
    public static func parseVoices(from data: Data) throws(ParseError) -> [VoiceDescriptor] {
        guard let response = try? JSONDecoder().decode(VoicesResponse.self, from: data) else {
            throw .invalidResponse
        }
        var seen: Set<String> = []
        return response.voices.compactMap { entry in
            guard let id = entry.id, !id.isEmpty, seen.insert(id).inserted else { return nil }
            return descriptor(forVoiceID: id, name: entry.name)
        }
    }

    /// The language of a Kokoro-shaped voice name; nil for any other name or an unknown letter.
    public static func language(forVoiceID id: String) -> String? {
        kokoroParts(of: id).flatMap { kokoroLanguages[$0.language] }
    }

    /// A remote descriptor for the voice `id`, named as `descriptor(forVoiceID:name:)` names it
    /// without a server-given name.
    public static func descriptor(forVoiceID id: String) -> VoiceDescriptor {
        descriptor(forVoiceID: id, name: nil)
    }

    /// A remote descriptor for the voice `id`. Without a `name`, a Kokoro name shows its name part
    /// capitalized ("af_heart" → "Heart") and any other name shows itself.
    static func descriptor(forVoiceID id: String, name: String?) -> VoiceDescriptor {
        let parts = kokoroParts(of: id)
        let derivedName = parts.map { $0.name.prefix(1).uppercased() + $0.name.dropFirst() } ?? id
        return VoiceDescriptor(
            id: id,
            name: name ?? derivedName,
            language: language(forVoiceID: id) ?? undeterminedLanguage,
            quality: .default,
            source: .remote
        )
    }

    /// The automatic voice for `language`, a BCP-47 tag or a bare language code. Candidates are
    /// the voices of the same base language, narrowed to those of exactly `language` when the
    /// server has any. Among them: a quality pick, else the first female voice, else the first
    /// male voice, in server order. Nil when none qualifies.
    public func automaticVoice(for language: String) -> VoiceDescriptor? {
        let base = VoiceCatalog.baseLanguage(of: language)
        let tag = VoiceCatalog.normalized(language)
        guard !base.isEmpty, base != Self.undeterminedLanguage else { return nil }
        let sameBase = voices.filter { VoiceCatalog.baseLanguage(of: $0.language) == base }
        let exact = sameBase.filter { VoiceCatalog.normalized($0.language) == tag }
        let candidates = exact.isEmpty ? sameBase : exact
        return candidates.first { Self.qualityPicks.contains($0.id) }
            ?? candidates.first { Self.kokoroParts(of: $0.id)?.gender == "f" }
            ?? candidates.first { Self.kokoroParts(of: $0.id)?.gender == "m" }
    }

    /// The voice that reads a text whose detected language is `textLanguage` (nil when unknown),
    /// with the same rules as `VoiceCatalog.resolve(_:textLanguage:)`: an explicit voice the
    /// server lists always reads; otherwise the automatic voice of the preferred language sharing
    /// the text's base language, else of the text's language, else of the first preferred
    /// language when the text's language is unknown.
    public func resolve(_ selection: VoiceSelection, textLanguage: String?) -> VoiceDescriptor? {
        if case .voice(let id) = selection, let voice = voices.first(where: { $0.id == id }) {
            return voice
        }
        guard let textLanguage else {
            return preferredLanguages.first.flatMap(automaticVoice(for:))
        }
        let base = VoiceCatalog.baseLanguage(of: textLanguage)
        let language = preferredLanguages.first { VoiceCatalog.baseLanguage(of: $0) == base } ?? textLanguage
        return automaticVoice(for: language)
    }

    // MARK: - Helpers

    /// Splits a Kokoro-shaped name: a lowercase ASCII letter, "f" or "m", "_", then one or more
    /// ASCII letters, digits or underscores.
    private static func kokoroParts(of id: String) -> (language: Character, gender: Character, name: Substring)? {
        let characters = Array(id)
        guard characters.count >= 4,
              characters[0].isASCII, characters[0].isLowercase,
              characters[1] == "f" || characters[1] == "m",
              characters[2] == "_"
        else { return nil }
        let name = id.dropFirst(3)
        guard name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { return nil }
        return (characters[0], characters[1], name)
    }

    private struct VoicesResponse: Decodable {
        let voices: [Entry]
    }

    /// A voice name, or an object with `id` and `name`; anything else decodes with no `id`.
    private struct Entry: Decodable {
        let id: String?
        let name: String?

        private enum CodingKeys: String, CodingKey {
            case id, name
        }

        init(from decoder: any Decoder) throws {
            if let id = try? decoder.singleValueContainer().decode(String.self) {
                self.id = id
                name = nil
                return
            }
            let object = try? decoder.container(keyedBy: CodingKeys.self)
            id = (try? object?.decodeIfPresent(String.self, forKey: .id)) ?? nil
            name = (try? object?.decodeIfPresent(String.self, forKey: .name)) ?? nil
        }
    }
}

/// Which engine reads.
public enum RemoteRouting {
    /// True only when the voice server is enabled and has an address, a server voice resolved for
    /// the reading, and the server is `.available`. Otherwise the system voice reads.
    public static func shouldUseRemote(
        config: RemoteVoiceServerConfig,
        availability: RemoteVoiceAvailability.State,
        resolvedRemoteVoice: VoiceDescriptor?
    ) -> Bool {
        guard config.enabled, config.address != nil, resolvedRemoteVoice != nil,
              case .available = availability
        else { return false }
        return true
    }
}
