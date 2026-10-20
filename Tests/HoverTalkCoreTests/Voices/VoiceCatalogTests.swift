import Testing
@testable import HoverTalkCore

private func voice(
    _ id: String,
    _ name: String,
    _ language: String,
    _ quality: VoiceDescriptor.Quality = .default,
    novelty: Bool = false
) -> VoiceDescriptor {
    VoiceDescriptor(id: id, name: name, language: language, quality: quality, isNovelty: novelty)
}

// Identifiers and names follow the voices macOS 26.2 reports (`AVSpeechSynthesisVoice.speechVoices()`).
private let marisol = voice("com.apple.voice.premium.es-ES.Marisol", "Marisol (Premium)", "es-ES", .premium)
private let jorge = voice("com.apple.voice.compact.es-ES.Jorge", "Jorge", "es-ES")
private let monica = voice("com.apple.voice.compact.es-ES.Monica", "Mónica", "es-ES")
private let paulina = voice("com.apple.voice.compact.es-MX.Paulina", "Paulina", "es-MX")
private let ava = voice("com.apple.voice.enhanced.en-US.Ava", "Ava (Enhanced)", "en-US", .enhanced)
private let samantha = voice("com.apple.voice.compact.en-US.Samantha", "Samantha", "en-US")
private let fred = voice("com.apple.speech.synthesis.voice.Fred", "Fred", "en-US")
private let daniel = voice("com.apple.voice.super-compact.en-GB.Daniel", "Daniel", "en-GB")
private let anna = voice("com.apple.voice.compact.de-DE.Anna", "Anna", "de-DE")
private let thomas = voice("com.apple.voice.super-compact.fr-FR.Thomas", "Thomas", "fr-FR")
private let tingting = voice("com.apple.voice.super-compact.zh-CN.Tingting", "Tingting", "zh-CN")

/// The system flags these four kinds differently; the catalog must drop every one.
private let eloquenceEddy = voice("com.apple.eloquence.es-MX.Eddy", "Eddy", "es-MX")
private let flaggedZarvox = voice("com.apple.speech.synthesis.voice.Zarvox", "Zarvox", "en-US", novelty: true)
private let unflaggedBells = voice("com.apple.speech.synthesis.voice.Bells", "Bells", "en-US")
private let flaggedOther = voice("com.example.voice.Robot", "Robot", "en-US", novelty: true)
private let novelties = [eloquenceEddy, flaggedZarvox, unflaggedBells, flaggedOther]

private let installed = [
    thomas, eloquenceEddy, fred, monica, tingting, flaggedZarvox, ava, daniel, unflaggedBells,
    paulina, anna, samantha, flaggedOther, jorge, marisol,
]

private func catalog(_ voices: [VoiceDescriptor] = installed, preferred: [String] = ["es-AR", "en-US"]) -> VoiceCatalog {
    VoiceCatalog(voices: voices, preferredLanguages: preferred)
}

@Suite("VoiceDescriptor names")
struct VoiceDescriptorNameTests {
    @Test("A quality suffix the system already put in the name is not repeated")
    func suffixInName() {
        #expect(marisol.baseName == "Marisol")
        #expect(marisol.displayName == "Marisol (Premium)")
        #expect(ava.baseName == "Ava")
        #expect(ava.displayName == "Ava (Enhanced)")
    }

    @Test("Premium and Enhanced voices without a suffix get one; default voices show the name alone")
    func suffixAdded() {
        #expect(voice("v.zoe", "Zoe", "en-US", .premium).displayName == "Zoe (Premium)")
        #expect(voice("v.evan", "Evan", "en-US", .enhanced).displayName == "Evan (Enhanced)")
        #expect(samantha.displayName == "Samantha")
        #expect(monica.baseName == "Mónica")
    }
}

@Suite("VoiceCatalog ordering and filtering")
struct VoiceCatalogOrderingTests {
    @Test("Groups: languages of the preferred list first (exact tag, then same base language), then the rest by tag")
    func groupOrder() {
        #expect(catalog().groups.map(\.language) == ["es-ES", "es-MX", "en-US", "en-GB", "de-DE", "fr-FR", "zh-CN"])
    }

    @Test("An exact preferred tag ranks above the same base language of that preference")
    func exactBeforeBase() {
        let groups = catalog(preferred: ["en-GB", "es-MX"]).groups.map(\.language)
        #expect(groups == ["en-GB", "en-US", "es-MX", "es-ES", "de-DE", "fr-FR", "zh-CN"])
    }

    @Test("Inside a group: premium, enhanced, default; legacy voices after the rest of their quality; then name")
    func voiceOrder() throws {
        let groups = catalog().groups
        try #require(groups.count == 7)
        #expect(groups[0].voices == [marisol, jorge, monica])
        #expect(groups[2].voices == [ava, samantha, fred])
        #expect(catalog().voices == [marisol, jorge, monica, paulina, ava, samantha, fred, daniel, anna, thomas, tingting])
    }

    @Test("The input order does not change the catalog")
    func inputOrderIrrelevant() {
        #expect(catalog(installed.reversed()) == catalog())
    }

    @Test("Novelty voices are left out: system-flagged, Eloquence, and legacy novelty identifiers")
    func noveltyFiltered() {
        let ids = Set(catalog().voices.map(\.id))
        for novelty in novelties {
            #expect(VoiceCatalog.isNovelty(novelty), "\(novelty.id)")
            #expect(!ids.contains(novelty.id), "\(novelty.id)")
        }
        for regular in [marisol, samantha, fred, paulina, tingting] {
            #expect(!VoiceCatalog.isNovelty(regular), "\(regular.id)")
        }
    }

    @Test("voice(withID:) finds catalog voices only")
    func lookup() {
        #expect(catalog().voice(withID: paulina.id) == paulina)
        #expect(catalog().voice(withID: eloquenceEddy.id) == nil)
        #expect(catalog().voice(withID: "missing") == nil)
    }
}

@Suite("VoiceCatalog recommendation")
struct VoiceCatalogRecommendationTests {
    @Test("The best quality of the base language wins, even over an exact region of lower quality")
    func bestQuality() {
        #expect(catalog().recommendedVoice(for: "es") == marisol)
        #expect(catalog().recommendedVoice(for: "es-MX") == marisol)
        #expect(catalog().recommendedVoice(for: "es_mx") == marisol)
        #expect(catalog().recommendedVoice(for: "en") == ava)
        #expect(catalog().recommendedVoice(for: "en-GB") == ava)
    }

    @Test("At equal quality legacy voices lose, then the exact region wins, then catalog order")
    func ties() {
        let defaults = catalog([monica, jorge, paulina, samantha, fred])
        #expect(defaults.recommendedVoice(for: "es-MX") == paulina)
        #expect(defaults.recommendedVoice(for: "es") == jorge)
        #expect(defaults.recommendedVoice(for: "en-US") == samantha)
        #expect(catalog([fred, daniel]).recommendedVoice(for: "en-US") == daniel)
    }

    @Test("Script subtags and languages without a voice")
    func otherLanguages() {
        #expect(catalog().recommendedVoice(for: "zh-Hans") == tingting)
        #expect(catalog().recommendedVoice(for: "it") == nil)
        #expect(catalog().recommendedVoice(for: "") == nil)
    }
}

@Suite("VoiceCatalog resolution")
struct VoiceCatalogResolutionTests {
    @Test("An explicit voice reads every text, whatever its language")
    func explicitVoice() {
        #expect(catalog().resolve(.voice(id: paulina.id), textLanguage: "en") == paulina)
        #expect(catalog().resolve(.voice(id: paulina.id), textLanguage: nil) == paulina)
    }

    @Test("A voice that is no longer installed, or is a novelty voice, falls back to automatic")
    func missingVoice() {
        #expect(catalog().resolve(.voice(id: "com.apple.voice.premium.en-US.Gone"), textLanguage: "en") == ava)
        #expect(catalog().resolve(.voice(id: eloquenceEddy.id), textLanguage: "es") == marisol)
    }

    @Test("Automatic picks the best voice for the text's language, or for the first preferred language without one")
    func automatic() {
        #expect(catalog().resolve(.automatic, textLanguage: "en") == ava)
        #expect(catalog().resolve(.automatic, textLanguage: "es") == marisol)
        #expect(catalog().resolve(.automatic, textLanguage: "fr") == thomas)
        #expect(catalog().resolve(.automatic, textLanguage: nil) == marisol)
        #expect(catalog(preferred: ["en-US"]).resolve(.automatic, textLanguage: nil) == ava)
    }

    @Test("Automatic uses the preferred region of the text's language to break ties")
    func preferredRegion() {
        let defaults = catalog([jorge, monica, paulina], preferred: ["es-MX"])
        #expect(defaults.resolve(.automatic, textLanguage: "es") == paulina)
    }

    @Test("Without a voice for the language, or without any language, automatic leaves the engine's default voice")
    func noVoice() {
        #expect(catalog().resolve(.automatic, textLanguage: "it") == nil)
        #expect(catalog(preferred: []).resolve(.automatic, textLanguage: nil) == nil)
    }
}

@Suite("VoiceCatalog menu and search")
struct VoiceCatalogMenuTests {
    @Test("The menu shows the preferred languages, then the last reading's language, without repeats")
    func menuLanguages() {
        #expect(catalog().menuGroups(lastReadingLanguage: nil, limit: 25).map(\.language) == ["es-ES", "es-MX", "en-US", "en-GB"])
        #expect(catalog().menuGroups(lastReadingLanguage: "fr", limit: 25).map(\.language) == ["es-ES", "es-MX", "en-US", "en-GB", "fr-FR"])
        #expect(catalog().menuGroups(lastReadingLanguage: "es", limit: 25).map(\.language) == ["es-ES", "es-MX", "en-US", "en-GB"])
    }

    @Test("The limit counts voices and cuts the lowest-ranked ones, never leaving an empty group")
    func menuLimit() {
        let four = catalog().menuGroups(lastReadingLanguage: nil, limit: 4)
        #expect(four == [VoiceGroup(language: "es-ES", voices: [marisol, jorge, monica]), VoiceGroup(language: "es-MX", voices: [paulina])])

        let five = catalog().menuGroups(lastReadingLanguage: nil, limit: 5)
        #expect(five.last == VoiceGroup(language: "en-US", voices: [ava]))

        #expect(catalog().menuGroups(lastReadingLanguage: nil, limit: 2) == [VoiceGroup(language: "es-ES", voices: [marisol, jorge])])
        #expect(catalog().menuGroups(lastReadingLanguage: nil, limit: 0) == [])
    }

    @Test("A chosen voice the menu would not show is added, so its check mark stays visible")
    func menuKeepsSelection() {
        let all = catalog()
        let german = all.menuGroups(lastReadingLanguage: nil, limit: 25, keeping: .voice(id: anna.id))
        #expect(german.map(\.language) == ["es-ES", "es-MX", "en-US", "en-GB", "de-DE"])
        #expect(german.last?.voices == [anna])

        let cut = all.menuGroups(lastReadingLanguage: nil, limit: 1, keeping: .voice(id: monica.id))
        #expect(cut == [VoiceGroup(language: "es-ES", voices: [marisol, monica])])

        let shown = all.menuGroups(lastReadingLanguage: nil, limit: 25, keeping: .voice(id: paulina.id))
        #expect(shown == all.menuGroups(lastReadingLanguage: nil, limit: 25))
        #expect(all.menuGroups(lastReadingLanguage: nil, limit: 25, keeping: .voice(id: "missing")) == shown)
        #expect(all.menuGroups(lastReadingLanguage: nil, limit: 25, keeping: .automatic) == shown)
    }

    @Test("Search matches voice names without case or accents, and language names or tags as whole groups")
    func search() {
        let names = ["fr-FR": "French (France)", "es-MX": "Spanish (Mexico)"]
        let languageName: (String) -> String = { names[$0] ?? $0 }
        let all = catalog()

        #expect(all.groups(matching: "", languageName: languageName) == all.groups)
        #expect(all.groups(matching: "  ", languageName: languageName) == all.groups)
        #expect(all.groups(matching: "PAU", languageName: languageName) == [VoiceGroup(language: "es-MX", voices: [paulina])])
        #expect(all.groups(matching: "monica", languageName: languageName) == [VoiceGroup(language: "es-ES", voices: [monica])])
        #expect(all.groups(matching: "french", languageName: languageName) == [VoiceGroup(language: "fr-FR", voices: [thomas])])
        #expect(all.groups(matching: "de-DE", languageName: languageName) == [VoiceGroup(language: "de-DE", voices: [anna])])
        #expect(all.groups(matching: "premium", languageName: languageName) == [VoiceGroup(language: "es-ES", voices: [marisol])])
        #expect(all.groups(matching: "zzz", languageName: languageName) == [])
    }
}
