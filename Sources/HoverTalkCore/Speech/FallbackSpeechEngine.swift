import Foundation

/// A `SpeechEngine` that reads with a primary engine (the voice server) and switches to a
/// fallback engine (the system voice) when the primary fails, for the rest of that reading.
///
/// - `beginReading(usePrimary:)` picks the engine for a reading; until it is first called the
///   fallback reads, so nothing reaches the voice server unless the owner asked for it.
/// - A `.failed` from the primary for the current utterance switches to the fallback, stops the
///   primary, speaks the current utterance again on the fallback with the same utterance ID (or
///   waits for `resume()` when paused), and then calls `onFallbackActivated` once.
/// - Only the active engine's events are forwarded. Late events from the other engine are
///   dropped, even when they carry the current utterance ID (after a failover the primary's late
///   `.cancelled` can).
/// - On the fallback, a `.remote` voice is replaced by `fallbackVoice(voice)`; other voices pass
///   through.
@MainActor
public final class FallbackSpeechEngine: SpeechEngine {
    public var onEvent: ((SpeechEngineEvent) -> Void)?
    /// Called once per reading, with the primary's failure reason, after the switch.
    public var onFallbackActivated: ((String) -> Void)?

    private enum Route {
        case primary
        case fallback
    }

    /// What `speak` was last asked to say, kept so a failover can say it again.
    private struct Utterance {
        let text: String
        var rate: SpeechRate
        let voice: VoiceDescriptor?
        let id: UUID
    }

    private let primary: any SpeechEngine
    private let fallback: any SpeechEngine
    private let fallbackVoice: (VoiceDescriptor?) -> VoiceDescriptor?
    private var route = Route.fallback
    /// The utterance the active engine holds (after a failover while paused, the one `resume()`
    /// will speak); nil after `stop()` or `beginReading(usePrimary:)`, or once it ended.
    private var current: Utterance?
    private var isPaused = false
    /// Set when the primary failed while paused: `resume()` speaks `current` on the fallback.
    private var restartOnResume = false

    /// `fallbackVoice` receives a `.remote` voice the player asked for and returns the system voice
    /// to use instead (for example the automatic system voice for the reading's language), or nil
    /// for the default voice. It is not called for other voices.
    public init(
        primary: any SpeechEngine,
        fallback: any SpeechEngine,
        fallbackVoice: @escaping (VoiceDescriptor?) -> VoiceDescriptor?
    ) {
        self.primary = primary
        self.fallback = fallback
        self.fallbackVoice = fallbackVoice
        primary.onEvent = { [weak self] in self?.handle($0, from: .primary) }
        fallback.onEvent = { [weak self] in self?.handle($0, from: .fallback) }
    }

    /// Whether the primary engine reads now; false before the first
    /// `beginReading(usePrimary: true)` and after a failover.
    public var isUsingPrimary: Bool { route == .primary }

    public var supportsLiveRate: Bool { active.supportsLiveRate }

    /// Chooses the engine for the reading about to be loaded, stopping the other one if it was
    /// active. Call it before the player loads the reading.
    public func beginReading(usePrimary: Bool) {
        let next: Route = usePrimary ? .primary : .fallback
        if next != route {
            active.stop()
        }
        route = next
        current = nil
        isPaused = false
        restartOnResume = false
    }

    public func speak(_ text: String, rate: SpeechRate, voice: VoiceDescriptor?, utteranceID: UUID) {
        let utterance = Utterance(text: text, rate: rate, voice: voice, id: utteranceID)
        current = utterance
        isPaused = false
        restartOnResume = false
        speak(utterance)
    }

    public func pause() {
        isPaused = true
        active.pause()
    }

    public func resume() {
        isPaused = false
        if restartOnResume, let current {
            restartOnResume = false
            speak(current)
        } else {
            active.resume()
        }
    }

    public func stop() {
        current = nil
        isPaused = false
        restartOnResume = false
        active.stop()
    }

    public func setRate(_ rate: SpeechRate) {
        current?.rate = rate
        active.setRate(rate)
    }

    public func prepare(upcoming: [String], voice: VoiceDescriptor?, rate: SpeechRate) {
        active.prepare(upcoming: upcoming, voice: voiceForActiveEngine(voice), rate: rate)
    }

    // MARK: - Helpers

    private var active: any SpeechEngine {
        route == .primary ? primary : fallback
    }

    private func speak(_ utterance: Utterance) {
        active.speak(utterance.text, rate: utterance.rate, voice: voiceForActiveEngine(utterance.voice), utteranceID: utterance.id)
    }

    private func voiceForActiveEngine(_ voice: VoiceDescriptor?) -> VoiceDescriptor? {
        guard route == .fallback, voice?.source == .remote else { return voice }
        return fallbackVoice(voice)
    }

    private func handle(_ event: SpeechEngineEvent, from source: Route) {
        guard source == route else { return }
        let isCurrent = event.utteranceID == current?.id
        switch event.kind {
        case .failed(let reason) where source == .primary:
            if isCurrent {
                failOver(reason: reason)
            }
            return
        case .finished, .cancelled, .failed:
            if isCurrent {
                current = nil
            }
        case .started, .progress:
            break
        }
        onEvent?(event)
    }

    private func failOver(reason: String) {
        route = .fallback
        primary.stop()
        if isPaused {
            restartOnResume = true
        } else if let current {
            speak(current)
        }
        onFallbackActivated?(reason)
    }
}
