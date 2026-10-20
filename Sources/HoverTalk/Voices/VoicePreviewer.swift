import AVFoundation
import HoverTalkCore

/// Speaks `VoicePreview`'s sample sentence through a synthesizer of its own, so a preview never
/// touches the reading player's utterances. Only the Settings window's Preview button uses it.
@MainActor
final class VoicePreviewer {
    private let synthesizer = AVSpeechSynthesizer()

    /// Stops the previous preview, then speaks the sample for `voice`'s language with that
    /// voice, or the English sample with the default voice when `voice` is nil.
    func preview(_ voice: VoiceDescriptor?, rate: SpeechRate) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: VoicePreview.sampleSentence(for: voice?.language ?? "en"))
        utterance.voice = voice.flatMap(AVSpeechEngine.synthesisVoice(for:))
        utterance.rate = AVSpeechEngine.utteranceRate(for: rate)
        synthesizer.speak(utterance)
    }
}
