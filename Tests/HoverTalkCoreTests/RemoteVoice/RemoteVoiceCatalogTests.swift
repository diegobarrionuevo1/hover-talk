import Foundation
import Testing
@testable import HoverTalkCore

/// The shape Kokoro-FastAPI's `GET /v1/audio/voices` returns: a list of voice names.
private let kokoroJSON = Data("""
{"voices": ["af_alloy", "af_heart", "am_adam", "bf_emma", "bm_george", "ef_dora", "em_alex",
            "ff_siwis", "hf_alpha", "if_sara", "jf_alpha", "pm_alex", "zf_xiaobei"]}
""".utf8)

private func catalog(_ ids: [String], preferred: [String] = ["es-AR", "en-US"]) -> RemoteVoiceCatalog {
    RemoteVoiceCatalog(voices: ids.map(RemoteVoiceCatalog.descriptor(forVoiceID:)), preferredLanguages: preferred)
}

@Suite("RemoteVoiceCatalog parsing")
struct RemoteVoiceCatalogParsingTests {
    @Test("Kokoro voice names map to their language by prefix", arguments: [
        ("af_heart", "en-US"), ("am_adam", "en-US"), ("bf_emma", "en-GB"), ("ef_dora", "es"),
        ("ff_siwis", "fr-FR"), ("hf_alpha", "hi"), ("if_sara", "it"), ("jf_alpha", "ja"),
        ("pm_alex", "pt-BR"), ("zf_xiaobei", "zh"), ("af_v0bella", "en-US"),
    ])
    func kokoroLanguage(id: String, language: String) {
        #expect(RemoteVoiceCatalog.language(forVoiceID: id) == language)
    }

    @Test("Names without the Kokoro shape, or with an unknown language letter, have no language", arguments: [
        "alloy", "xf_test", "ax_heart", "af_", "af-heart", "AF_heart", "a", "", "af_heart+bf_emma",
    ])
    func unknownLanguage(id: String) {
        #expect(RemoteVoiceCatalog.language(forVoiceID: id) == nil)
    }

    @Test("A voice becomes a remote descriptor; its name comes from the voice name, and an unknown language is 'und'")
    func descriptors() {
        let heart = RemoteVoiceCatalog.descriptor(forVoiceID: "af_heart")
        #expect(heart == VoiceDescriptor(id: "af_heart", name: "Heart", language: "en-US", quality: .default, source: .remote))

        let custom = RemoteVoiceCatalog.descriptor(forVoiceID: "studio-voice")
        #expect(custom == VoiceDescriptor(id: "studio-voice", name: "studio-voice", language: "und", quality: .default, source: .remote))
    }

    @Test("The voices list parses from Kokoro's list of names, in server order")
    func parsesNames() throws {
        let voices = try RemoteVoiceCatalog.parseVoices(from: kokoroJSON)

        #expect(voices.count == 13)
        #expect(voices.prefix(3).map(\.id) == ["af_alloy", "af_heart", "am_adam"])
        #expect(voices.allSatisfy { $0.source == .remote })
    }

    @Test("Objects with an id parse too, using their name when present; unusable entries and repeats are skipped")
    func parsesObjects() throws {
        let json = Data("""
        {"voices": [{"id": "ef_dora", "name": "Dora"}, {"id": "studio-voice"}, {"name": "no id"},
                    42, null, "ef_dora", "af_heart", {"id": ""}]}
        """.utf8)

        let voices = try RemoteVoiceCatalog.parseVoices(from: json)

        #expect(voices == [
            VoiceDescriptor(id: "ef_dora", name: "Dora", language: "es", quality: .default, source: .remote),
            VoiceDescriptor(id: "studio-voice", name: "studio-voice", language: "und", quality: .default, source: .remote),
            VoiceDescriptor(id: "af_heart", name: "Heart", language: "en-US", quality: .default, source: .remote),
        ])
    }

    @Test("A response that is not JSON, or has no voices list, is an invalid response", arguments: [
        "not json", "{}", "{\"voices\": \"af_heart\"}", "[\"af_heart\"]", "",
    ])
    func invalidResponse(body: String) {
        #expect(throws: RemoteVoiceCatalog.ParseError.invalidResponse) {
            try RemoteVoiceCatalog.parseVoices(from: Data(body.utf8))
        }
    }

    @Test("An empty voices list is an empty catalog, not an error")
    func emptyList() throws {
        #expect(try RemoteVoiceCatalog.parseVoices(from: Data("{\"voices\": []}".utf8)).isEmpty)
    }
}

@Suite("RemoteVoiceCatalog automatic voice")
struct RemoteVoiceCatalogAutomaticTests {
    private let kokoro = RemoteVoiceCatalog(voices: try! RemoteVoiceCatalog.parseVoices(from: kokoroJSON), preferredLanguages: [])

    @Test("The documented quality picks win when present", arguments: [
        ("es", "ef_dora"), ("es-MX", "ef_dora"), ("es-AR", "ef_dora"),
        ("en", "af_heart"), ("en-US", "af_heart"), ("en-AU", "af_heart"), ("EN_us", "af_heart"),
    ])
    func qualityPicks(language: String, id: String) {
        #expect(kokoro.automaticVoice(for: language)?.id == id)
    }

    @Test("A tag with a region the server has prefers that region's voices", arguments: [
        ("en-GB", "bf_emma"), ("fr", "ff_siwis"), ("pt", "pm_alex"), ("zh-Hans", "zf_xiaobei"),
    ])
    func regionAndOtherLanguages(language: String, id: String) {
        #expect(kokoro.automaticVoice(for: language)?.id == id)
    }

    @Test("Without a quality pick: the first female voice, else the first male voice, in server order")
    func withoutPick() {
        #expect(catalog(["am_adam", "af_bella", "af_alloy"]).automaticVoice(for: "en-US")?.id == "af_bella")
        #expect(catalog(["em_alex", "em_santa"]).automaticVoice(for: "es")?.id == "em_alex")
        #expect(catalog(["bm_george", "af_sky"]).automaticVoice(for: "en-GB")?.id == "bm_george")
    }

    @Test("No voice for a language the server does not speak, for no language, or for unknown voices")
    func noVoice() {
        #expect(kokoro.automaticVoice(for: "de") == nil)
        #expect(kokoro.automaticVoice(for: "") == nil)
        #expect(catalog(["studio-voice"]).automaticVoice(for: "und") == nil)
        #expect(catalog([]).automaticVoice(for: "es") == nil)
    }

    @Test("resolve: an explicit voice on the server reads; a missing one falls back to the automatic choice")
    func resolveExplicit() {
        let voices = catalog(["af_heart", "em_alex", "ef_dora", "studio-voice"])

        #expect(voices.resolve(.voice(id: "em_alex"), textLanguage: "en")?.id == "em_alex")
        #expect(voices.resolve(.voice(id: "studio-voice"), textLanguage: "es")?.id == "studio-voice")
        #expect(voices.resolve(.voice(id: "gone_voice"), textLanguage: "es")?.id == "ef_dora")
    }

    @Test("resolve: automatic uses the preferred language sharing the text's language, else the text's, else the first preferred")
    func resolveAutomatic() {
        let voices = catalog(["af_heart", "bf_emma", "ef_dora"], preferred: ["en-GB", "es-AR"])

        #expect(voices.resolve(.automatic, textLanguage: "en")?.id == "bf_emma")
        #expect(voices.resolve(.automatic, textLanguage: "es")?.id == "ef_dora")
        #expect(voices.resolve(.automatic, textLanguage: nil)?.id == "bf_emma")
        #expect(catalog(["af_heart"], preferred: ["es-AR"]).resolve(.automatic, textLanguage: "en")?.id == "af_heart")
        #expect(catalog(["af_heart"], preferred: []).resolve(.automatic, textLanguage: nil) == nil)
    }
}

@Suite("RemoteRouting")
struct RemoteRoutingTests {
    private static let heart = RemoteVoiceCatalog.descriptor(forVoiceID: "af_heart")

    private static func config(enabled: Bool = true, address: Bool = true) -> RemoteVoiceServerConfig {
        RemoteVoiceServerConfig(
            enabled: enabled,
            address: address ? try! RemoteVoiceServerAddress(validating: "http://studio.local:8880") : nil
        )
    }

    @Test("The remote voice reads only when enabled, with an address, a resolved voice, and an available server")
    func usesRemote() {
        #expect(RemoteRouting.shouldUseRemote(config: Self.config(), availability: .available(latency: 0.1), resolvedRemoteVoice: Self.heart))
    }

    @Test("Any missing condition keeps the system voice", arguments: [
        (true, true, true, RemoteVoiceAvailability.State.unknown),
        (true, true, true, .checking),
        (true, true, true, .unavailable(retryAt: Date(timeIntervalSinceReferenceDate: 0), failures: 1)),
        (true, true, true, .disabled),
        (false, true, true, .available(latency: 0.1)),
        (true, false, true, .available(latency: 0.1)),
        (true, true, false, .available(latency: 0.1)),
    ])
    func keepsSystem(enabled: Bool, address: Bool, voice: Bool, availability: RemoteVoiceAvailability.State) {
        #expect(!RemoteRouting.shouldUseRemote(
            config: Self.config(enabled: enabled, address: address),
            availability: availability,
            resolvedRemoteVoice: voice ? Self.heart : nil
        ))
    }
}
