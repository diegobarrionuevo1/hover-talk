import Foundation

/// The voices of one language tag, in catalog order.
public struct VoiceGroup: Equatable, Sendable, Identifiable {
    /// BCP-47 language tag shared by every voice of the group, for example "es-MX".
    public let language: String
    public let voices: [VoiceDescriptor]

    public var id: String { language }

    public init(language: String, voices: [VoiceDescriptor]) {
        self.language = language
        self.voices = voices
    }
}

/// The voices a user can choose from, without novelty voices, ordered for menus and pickers,
/// and the rules that pick a voice for a text.
///
/// Order: groups of the user's preferred languages come first, in preference order (for each
/// preference, its exact tag before other regions of the same base language), then the other
/// groups by tag. Inside a group: premium, enhanced, then default quality; at equal quality the
/// legacy voices (`legacyPrefix`, such as Fred) come last; then by name.
public struct VoiceCatalog: Equatable, Sendable {
    /// Apple's Eloquence voices (Eddy, Flo, Grandma, Rocko and others, one set per language).
    /// macOS 26.2 does not flag them as novelty voices, but they are character voices.
    static let eloquencePrefix = "com.apple.eloquence."
    /// The older voices of the speech synthesis framework: the novelty ones
    /// (`legacyNoveltyNames`) and plain ones such as Fred, Junior, Kathy and Ralph.
    static let legacyPrefix = "com.apple.speech.synthesis.voice."
    /// Defensive: the legacy voices macOS 26.2 flags with the novelty trait, by the last
    /// component of their identifier, so they are left out even where the flag is missing.
    static let legacyNoveltyNames: Set<String> = [
        "Albert", "BadNews", "Bahh", "Bells", "Boing", "Bubbles", "Cellos", "Deranged",
        "GoodNews", "Hysterical", "Organ", "Princess", "Trinoids", "Whisper", "Zarvox",
    ]

    /// The user's languages, most preferred first, for example ["es-AR", "en-US"].
    public let preferredLanguages: [String]
    /// Every voice that is not a novelty voice, in the order of `groups`.
    public let voices: [VoiceDescriptor]
    public let groups: [VoiceGroup]

    public init(voices: [VoiceDescriptor], preferredLanguages: [String]) {
        self.preferredLanguages = preferredLanguages
        let byLanguage = Dictionary(grouping: voices.filter { !Self.isNovelty($0) }, by: \.language)
        let languages = byLanguage.keys.sorted { lhs, rhs in
            let lhsRank = Self.languageRank(lhs, preferred: preferredLanguages)
            let rhsRank = Self.languageRank(rhs, preferred: preferredLanguages)
            return lhsRank != rhsRank ? lhsRank < rhsRank : lhs < rhs
        }
        groups = languages.compactMap { language in
            byLanguage[language].map { VoiceGroup(language: language, voices: $0.sorted(by: Self.ranksBefore)) }
        }
        self.voices = groups.flatMap(\.voices)
    }

    public func voice(withID id: String) -> VoiceDescriptor? {
        voices.first { $0.id == id }
    }

    /// The best voice for `language`, a BCP-47 tag or a bare language code: among the voices
    /// with the same base language, the highest quality; at equal quality a non-legacy voice,
    /// then a voice whose tag is exactly `language`, then the first in catalog order. Nil when no
    /// voice speaks the base language.
    public func recommendedVoice(for language: String) -> VoiceDescriptor? {
        let base = Self.baseLanguage(of: language)
        let tag = Self.normalized(language)
        guard !base.isEmpty else { return nil }
        let candidates = voices.enumerated().filter { Self.baseLanguage(of: $0.element.language) == base }
        let best = candidates.min { lhs, rhs in
            let (a, b) = (lhs.element, rhs.element)
            if a.quality != b.quality { return a.quality > b.quality }
            if Self.isLegacy(a) != Self.isLegacy(b) { return !Self.isLegacy(a) }
            let (aExact, bExact) = (Self.normalized(a.language) == tag, Self.normalized(b.language) == tag)
            if aExact != bExact { return aExact }
            return lhs.offset < rhs.offset
        }
        return best?.element
    }

    /// The voice that reads a text whose detected language is `textLanguage` (nil when unknown).
    ///
    /// An explicit voice that is in the catalog always reads. Otherwise, including an explicit
    /// voice that is no longer installed, the automatic choice applies: `recommendedVoice(for:)`
    /// of the preferred language with the text's base language (so its region breaks ties), or
    /// of the text's language when no preferred language shares it, or of the first preferred
    /// language when the text's language is unknown. Nil leaves the engine's default voice.
    public func resolve(_ selection: VoiceSelection, textLanguage: String?) -> VoiceDescriptor? {
        if case .voice(let id) = selection, let voice = voice(withID: id) {
            return voice
        }
        guard let textLanguage else {
            return preferredLanguages.first.flatMap(recommendedVoice(for:))
        }
        let base = Self.baseLanguage(of: textLanguage)
        let language = preferredLanguages.first { Self.baseLanguage(of: $0) == base } ?? textLanguage
        return recommendedVoice(for: language)
    }

    /// The groups a short voice menu shows: those of the preferred languages' base languages, in
    /// preference order, then those of `lastReadingLanguage`'s base language, keeping catalog
    /// order inside each base language. Stops after `limit` voices; a group cut by the limit
    /// keeps its best voices, and no group is empty.
    ///
    /// When `selection` is a catalog voice that would not be shown, it is added after the
    /// limit, at the end of its language's group or in a group of its own at the end, so the
    /// menu always shows the check mark of an explicit choice.
    public func menuGroups(lastReadingLanguage: String?, limit: Int, keeping selection: VoiceSelection = .automatic) -> [VoiceGroup] {
        var result = limitedMenuGroups(lastReadingLanguage: lastReadingLanguage, limit: limit)
        guard case .voice(let id) = selection, let chosen = voice(withID: id),
              !result.contains(where: { $0.voices.contains(chosen) })
        else { return result }
        if let index = result.firstIndex(where: { $0.language == chosen.language }) {
            result[index] = VoiceGroup(language: chosen.language, voices: result[index].voices + [chosen])
        } else {
            result.append(VoiceGroup(language: chosen.language, voices: [chosen]))
        }
        return result
    }

    private func limitedMenuGroups(lastReadingLanguage: String?, limit: Int) -> [VoiceGroup] {
        var bases: [String] = []
        for language in preferredLanguages + [lastReadingLanguage].compactMap({ $0 }) {
            let base = Self.baseLanguage(of: language)
            if !bases.contains(base) { bases.append(base) }
        }
        var remaining = limit
        var result: [VoiceGroup] = []
        for base in bases {
            for group in groups where Self.baseLanguage(of: group.language) == base {
                guard remaining > 0 else { return result }
                let voices = Array(group.voices.prefix(remaining))
                remaining -= voices.count
                result.append(VoiceGroup(language: group.language, voices: voices))
            }
        }
        return result
    }

    /// The groups and voices that match `query`, ignoring case and accents: a group whose tag or
    /// `languageName` contains the query comes whole; otherwise only its voices whose
    /// `displayName` contains it. A blank query returns every group.
    public func groups(matching query: String, languageName: (String) -> String) -> [VoiceGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return groups }
        func matches(_ text: String) -> Bool {
            text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return groups.compactMap { group in
            if matches(group.language) || matches(languageName(group.language)) {
                return group
            }
            let voices = group.voices.filter { matches($0.displayName) }
            return voices.isEmpty ? nil : VoiceGroup(language: group.language, voices: voices)
        }
    }

    /// Whether `voice` is a novelty voice that the catalog leaves out: flagged by its source
    /// (`VoiceDescriptor.isNovelty`), an Eloquence voice, or a legacy voice named in
    /// `legacyNoveltyNames`.
    public static func isNovelty(_ voice: VoiceDescriptor) -> Bool {
        if voice.isNovelty || voice.id.hasPrefix(eloquencePrefix) {
            return true
        }
        guard voice.id.hasPrefix(legacyPrefix) else { return false }
        return legacyNoveltyNames.contains(String(voice.id.dropFirst(legacyPrefix.count)))
    }

    // MARK: - Helpers

    static func isLegacy(_ voice: VoiceDescriptor) -> Bool {
        voice.id.hasPrefix(legacyPrefix)
    }

    /// Lowercased, with "_" read as "-", so "es_MX" and "es-mx" are the same tag.
    static func normalized(_ language: String) -> String {
        language.lowercased().replacingOccurrences(of: "_", with: "-")
    }

    /// The first subtag: "es" for "es-MX", "zh" for "zh-Hans".
    static func baseLanguage(of language: String) -> String {
        String(normalized(language).prefix { $0 != "-" })
    }

    /// For preference `i`: `2i` for its exact tag, `2i + 1` for its base language; `Int.max`
    /// for languages no preference shares.
    private static func languageRank(_ language: String, preferred: [String]) -> Int {
        let tag = normalized(language)
        let base = baseLanguage(of: language)
        for (index, preference) in preferred.enumerated() {
            if normalized(preference) == tag { return 2 * index }
            if baseLanguage(of: preference) == base { return 2 * index + 1 }
        }
        return Int.max
    }

    /// Order inside a group: quality, then non-legacy first, then name, then identifier.
    private static func ranksBefore(_ a: VoiceDescriptor, _ b: VoiceDescriptor) -> Bool {
        if a.quality != b.quality { return a.quality > b.quality }
        if isLegacy(a) != isLegacy(b) { return !isLegacy(a) }
        let names = a.baseName.compare(b.baseName, options: [.caseInsensitive, .diacriticInsensitive])
        if names != .orderedSame { return names == .orderedAscending }
        return a.id < b.id
    }
}
