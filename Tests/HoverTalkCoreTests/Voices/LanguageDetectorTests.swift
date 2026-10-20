import Testing
@testable import HoverTalkCore

@Suite("LanguageDetector")
struct LanguageDetectorTests {
    @Test("Detects the dominant language of a sentence", arguments: [
        ("Hola, este es el primer paso de la tarea.", "es"),
        ("The report is ready for review.", "en"),
        ("Bonjour, comment ça va aujourd'hui?", "fr"),
        ("Primera oración del texto. The report is ready for review. ¿Tercera pregunta? Fourth and last.", "es"),
    ])
    func detects(text: String, language: String) {
        #expect(LanguageDetector().language(of: text) == language)
    }

    @Test("Empty, numeric or too short to tell reads as unknown", arguments: ["", "   ", "123 456", "OK."])
    func unknown(text: String) {
        #expect(LanguageDetector().language(of: text) == nil)
    }
}

@Suite("VoicePreview")
struct VoicePreviewTests {
    @Test("The sample sentence is in the voice's language, English when no sample exists")
    func sampleSentence() {
        let english = VoicePreview.sampleSentence(for: "en-US")
        #expect(!english.isEmpty)
        #expect(VoicePreview.sampleSentence(for: "en-GB") == english)
        #expect(VoicePreview.sampleSentence(for: "xx-YY") == english)

        let spanish = VoicePreview.sampleSentence(for: "es-MX")
        #expect(spanish != english)
        #expect(VoicePreview.sampleSentence(for: "es_ES") == spanish)
        #expect(LanguageDetector().language(of: spanish) == "es")
        #expect(LanguageDetector().language(of: english) == "en")
    }
}

@Suite("Voice settings links")
struct VoiceSettingsLinkTests {
    @Test("Download More Voices opens Spoken Content, with the Accessibility pane as the fallback")
    func links() {
        #expect(SystemSettingsLinks.spokenContent.absoluteString == "x-apple.systempreferences:com.apple.preference.universalaccess?TextToSpeech")
        #expect(SystemSettingsLinks.accessibility.absoluteString == "x-apple.systempreferences:com.apple.preference.universalaccess")
    }
}
