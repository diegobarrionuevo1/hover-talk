import Testing
@testable import HoverTalkCore

private let paulinaID = "com.apple.voice.compact.es-MX.Paulina"

@Suite("VoiceSelection")
struct VoiceSelectionTests {
    @Test("Automatic is the default and round-trips through its stored value")
    func automatic() {
        #expect(VoiceSelection.default == .automatic)
        #expect(VoiceSelection.automatic.storedValue == "automatic")
        #expect(VoiceSelection(storedValue: "automatic") == .automatic)
    }

    @Test("An explicit voice round-trips through its stored value")
    func explicitVoice() {
        let selection = VoiceSelection.voice(id: paulinaID)
        #expect(selection.storedValue == "voice:\(paulinaID)")
        #expect(VoiceSelection(storedValue: selection.storedValue) == selection)
    }

    @Test("Nothing stored, an unknown value, or an empty voice ID reads as automatic", arguments: [nil, "", "sideways", "voice:"])
    func unknown(stored: String?) {
        #expect(VoiceSelection(storedValue: stored) == .automatic)
    }
}

@MainActor
@Suite("Preferences voice and rate")
struct PreferencesVoiceTests {
    @Test("Voice selection defaults to automatic and persists an explicit voice")
    func voiceSelection() {
        let storage = InMemorySettingsStorage()
        let preferences = Preferences(storage: storage)
        #expect(preferences.voiceSelection == .automatic)

        preferences.voiceSelection = .voice(id: paulinaID)

        #expect(storage.string(forKey: Preferences.voiceSelectionKey) == "voice:\(paulinaID)")
        #expect(Preferences(storage: storage).voiceSelection == .voice(id: paulinaID))
        preferences.voiceSelection = .automatic
        #expect(Preferences(storage: storage).voiceSelection == .automatic)
    }

    @Test("Speech rate defaults to normal and persists the rate that is set")
    func speechRate() {
        let storage = InMemorySettingsStorage()
        let preferences = Preferences(storage: storage)
        #expect(preferences.speechRate == .default)

        preferences.speechRate = SpeechRate(1.75)

        #expect(Preferences(storage: storage).speechRate == SpeechRate(1.75))
    }

    @Test("A stored rate is read through SpeechRate's clamping; garbage reads as normal speed")
    func storedRate() {
        let storage = InMemorySettingsStorage()
        storage.setString("9", forKey: Preferences.speechRateKey)
        #expect(Preferences(storage: storage).speechRate == SpeechRate(SpeechRate.maximum))

        storage.setString("fast", forKey: Preferences.speechRateKey)
        #expect(Preferences(storage: storage).speechRate == .default)
    }
}
