import AVFoundation
import HoverTalkCore

/// `SpeechEngine` backed by `AVSpeechSynthesizer`. Utterances leave `voice` unset, so the
/// synthesizer's default voice speaks.
@MainActor
final class AVSpeechEngine: NSObject, SpeechEngine {
    var onEvent: ((SpeechEngineEvent) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()

    /// Utterances handed to the synthesizer, keyed by object identity. An entry keeps its
    /// utterance alive until that utterance's own `.finished` or `.cancelled` is emitted on the
    /// main actor (`emit`), so no new utterance can reuse its `ObjectIdentifier` before then.
    /// Events with no entry are dropped.
    private var utteranceIDs: [ObjectIdentifier: (utterance: AVSpeechUtterance, id: UUID)] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, rate: SpeechRate, utteranceID: UUID) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = Self.utteranceRate(for: rate)
        utteranceIDs[ObjectIdentifier(utterance)] = (utterance, utteranceID)
        synthesizer.speak(utterance)
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .immediate)
    }

    func resume() {
        synthesizer.continueSpeaking()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Multiplier to `AVSpeechUtterance.rate`: 1.0x is `AVSpeechUtteranceDefaultSpeechRate`;
    /// below 1.0x the rate scales proportionally (0.5x is half the default); above 1.0x it rises
    /// linearly to `AVSpeechUtteranceMaximumSpeechRate` at `SpeechRate.maximum`. The result is
    /// clamped to `AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate`.
    /// Nothing here makes the perceived speed-up equal the multiplier.
    static func utteranceRate(for rate: SpeechRate) -> Float {
        let multiplier = Float(rate.multiplier)
        let defaultRate = AVSpeechUtteranceDefaultSpeechRate
        let mapped: Float
        if multiplier <= 1 {
            mapped = defaultRate * multiplier
        } else {
            let fraction = (multiplier - 1) / (Float(SpeechRate.maximum) - 1)
            mapped = defaultRate + (AVSpeechUtteranceMaximumSpeechRate - defaultRate) * fraction
        }
        return min(max(mapped, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }

    private func emit(_ kind: SpeechEngineEvent.Kind, forUtteranceWith key: ObjectIdentifier) {
        guard let entry = utteranceIDs[key] else { return }
        if kind == .finished || kind == .cancelled {
            utteranceIDs[key] = nil
        }
        onEvent?(SpeechEngineEvent(utteranceID: entry.id, kind: kind))
    }
}

extension AVSpeechEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        deliver(.started, for: utterance)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        deliver(.progress(characterOffset: characterRange.location), for: utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        deliver(.finished, for: utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        deliver(.cancelled, for: utterance)
    }

    /// The delegate's calling thread is not assumed, so every event hops to the main queue.
    /// The main queue is serial, so events reach `onEvent` in the order this method enqueued them.
    private nonisolated func deliver(_ kind: SpeechEngineEvent.Kind, for utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.emit(kind, forUtteranceWith: key)
            }
        }
    }
}
