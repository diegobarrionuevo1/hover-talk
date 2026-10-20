import Foundation

/// Something that speaks one utterance at a time and reports what happens to it.
///
/// Engines report through `onEvent`, on the main actor. Every event carries the ID passed to
/// `speak`, so the player can ignore events from an utterance it already replaced.
@MainActor
public protocol SpeechEngine: AnyObject {
    /// Set by the player. Engines call it for every event of every utterance.
    var onEvent: ((SpeechEngineEvent) -> Void)? { get set }

    /// Speaks `text` with `voice`, or with the engine's default voice when `voice` is nil.
    func speak(_ text: String, rate: SpeechRate, voice: VoiceDescriptor?, utteranceID: UUID)
    func pause()
    func resume()
    /// Cancels the current utterance. Late events for it may still arrive; the playback queue
    /// ignores them because their ID no longer matches the current utterance.
    func stop()

    /// Whether `setRate(_:)` changes the rate of the current utterance in place. The player reads
    /// it before every operation (`Player.apply`); false by default.
    var supportsLiveRate: Bool { get }
    /// Applies `rate` to the current utterance, playing or paused, without restarting it. The
    /// player calls it only while `supportsLiveRate` is true (`Player.apply` copies the flag into
    /// `PlaybackQueue.supportsLiveRate`, which alone emits `.setRate`); the default does nothing.
    func setRate(_ rate: SpeechRate)
    /// A hint with the texts the player will likely speak next, in order, and the voice and rate
    /// it would use, so an engine that synthesizes ahead can start. It never speaks; the default
    /// does nothing.
    func prepare(upcoming: [String], voice: VoiceDescriptor?, rate: SpeechRate)
}

extension SpeechEngine {
    public var supportsLiveRate: Bool { false }
    public func setRate(_ rate: SpeechRate) {}
    public func prepare(upcoming: [String], voice: VoiceDescriptor?, rate: SpeechRate) {}
}

public struct SpeechEngineEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case started
        /// The engine is about to speak the word that starts at `characterOffset`, counted in
        /// UTF-16 code units of the utterance text (the unit of `NSString` and `NSRange`).
        case progress(characterOffset: Int)
        case finished
        case cancelled
        /// The engine gave up on the utterance (for example the voice server did not answer);
        /// `reason` is for logs and status text.
        case failed(reason: String)
    }

    public let utteranceID: UUID
    public let kind: Kind

    public init(utteranceID: UUID, kind: Kind) {
        self.utteranceID = utteranceID
        self.kind = kind
    }
}
