import Foundation
import Testing
@testable import HoverTalkCore

@Suite("RemoteVoiceServerAddress")
struct RemoteVoiceServerAddressTests {
    @Test("A valid base URL is kept without trailing slashes or a trailing /v1, with a lowercase scheme", arguments: [
        ("http://192.168.1.20:8880", "http://192.168.1.20:8880"),
        ("http://192.168.1.20:8880/", "http://192.168.1.20:8880"),
        ("  https://voices.example.org/kokoro//  ", "https://voices.example.org/kokoro"),
        ("HTTP://Studio.local:8880", "http://Studio.local:8880"),
        ("http://studio.local:8880/v1", "http://studio.local:8880"),
        ("http://studio.local:8880/v1/", "http://studio.local:8880"),
        ("http://studio.local/api/v1", "http://studio.local/api"),
        ("http://[::1]:8880", "http://[::1]:8880"),
    ])
    func normalizes(input: String, expected: String) throws {
        let address = try RemoteVoiceServerAddress(validating: input)
        #expect(address.baseURL.absoluteString == expected)
    }

    @Test("An invalid base URL is rejected with a typed error", arguments: [
        ("", RemoteVoiceServerAddress.ValidationError.empty),
        (" \n ", .empty),
        ("ftp://studio.local", .unsupportedScheme),
        ("studio.local", .unsupportedScheme),
        ("studio.local:8880", .unsupportedScheme),
        ("http://", .missingHost),
        ("http:///v1", .missingHost),
        ("http://studio.local:8880?key=1", .queryOrFragment),
        ("http://studio.local:8880/?", .queryOrFragment),
        ("http://studio.local:8880/#top", .queryOrFragment),
        ("http://studio.local:88a0", .malformed),
    ])
    func rejects(input: String, error: RemoteVoiceServerAddress.ValidationError) {
        #expect(throws: error) { try RemoteVoiceServerAddress(validating: input) }
    }

    @Test("The speech and voices endpoints are under /v1/audio of the base URL")
    func endpoints() throws {
        let root = try RemoteVoiceServerAddress(validating: "http://studio.local:8880/")
        #expect(root.speechURL.absoluteString == "http://studio.local:8880/v1/audio/speech")
        #expect(root.voicesURL.absoluteString == "http://studio.local:8880/v1/audio/voices")

        let nested = try RemoteVoiceServerAddress(validating: "https://example.org/tts/v1")
        #expect(nested.speechURL.absoluteString == "https://example.org/tts/v1/audio/speech")
        #expect(nested.voicesURL.absoluteString == "https://example.org/tts/v1/audio/voices")
    }
}

@Suite("RemoteVoiceServerConfig")
struct RemoteVoiceServerConfigTests {
    @Test("The default config is off, has no address and picks the voice automatically")
    func defaults() {
        let config = RemoteVoiceServerConfig.default
        #expect(config.enabled == false)
        #expect(config.address == nil)
        #expect(config.voice == .automatic)
        #expect(RemoteVoiceServerConfig() == config)
    }
}

@MainActor
@Suite("Preferences voice server")
struct PreferencesRemoteVoiceTests {
    @Test("The voice server config defaults to off while nothing is stored")
    func defaultConfig() {
        #expect(Preferences(storage: InMemorySettingsStorage()).remoteVoiceServer == .default)
    }

    @Test("A config that is set is stored and read back by later preferences on the same storage")
    func persists() throws {
        let storage = InMemorySettingsStorage()
        let address = try RemoteVoiceServerAddress(validating: "http://studio.local:8880/")
        let config = RemoteVoiceServerConfig(enabled: true, address: address, voice: .voice(id: "ef_dora"))

        Preferences(storage: storage).remoteVoiceServer = config

        #expect(storage.string(forKey: Preferences.remoteVoiceEnabledKey) == "true")
        #expect(storage.string(forKey: Preferences.remoteVoiceURLKey) == "http://studio.local:8880")
        #expect(storage.string(forKey: Preferences.remoteVoiceSelectionKey) == "voice:ef_dora")
        #expect(Preferences(storage: storage).remoteVoiceServer == config)

        Preferences(storage: storage).remoteVoiceServer = RemoteVoiceServerConfig(enabled: false, address: nil, voice: .automatic)
        #expect(Preferences(storage: storage).remoteVoiceServer == .default)
    }

    @Test("A stored URL that no longer validates reads as no address; an unknown flag reads as off")
    func invalidStoredValues() {
        let storage = InMemorySettingsStorage()
        storage.setString("ftp://studio.local", forKey: Preferences.remoteVoiceURLKey)
        storage.setString("yes", forKey: Preferences.remoteVoiceEnabledKey)

        let config = Preferences(storage: storage).remoteVoiceServer
        #expect(config.address == nil)
        #expect(config.enabled == false)
    }

    @Test("The voice server settings do not touch the system voice settings")
    func separateKeys() {
        let storage = InMemorySettingsStorage()
        let preferences = Preferences(storage: storage)
        preferences.voiceSelection = .voice(id: "com.apple.voice.compact.es-MX.Paulina")

        preferences.remoteVoiceServer = RemoteVoiceServerConfig(enabled: true, address: nil, voice: .voice(id: "af_heart"))

        #expect(preferences.voiceSelection == .voice(id: "com.apple.voice.compact.es-MX.Paulina"))
        #expect(preferences.remoteVoiceServer.voice == .voice(id: "af_heart"))
    }
}
