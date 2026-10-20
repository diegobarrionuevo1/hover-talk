/// The sentence the Settings window's Preview button speaks.
public enum VoicePreview {
    /// Spoken content, not UI copy: a voice previewed with a sentence in another language
    /// sounds wrong, so each sample is in the language it demonstrates. Keyed by base language.
    private static let samples: [String: String] = [
        "en": "This is how I sound when I read your text aloud.",
        "es": "Así sueno cuando leo tu texto en voz alta.",
        "pt": "É assim que eu soo quando leio o seu texto em voz alta.",
        "fr": "Voici ma voix quand je lis votre texte à voix haute.",
        "de": "So klinge ich, wenn ich Ihren Text vorlese.",
        "it": "Ecco come suono quando leggo il tuo testo ad alta voce.",
    ]

    /// A short sample in the base language of `language` (a BCP-47 tag), or in English when no
    /// sample exists for it.
    public static func sampleSentence(for language: String) -> String {
        samples[VoiceCatalog.baseLanguage(of: language)] ?? samples["en", default: ""]
    }
}
