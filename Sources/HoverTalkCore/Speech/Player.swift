import Foundation

/// Drives a `SpeechEngine` from a `PlaybackQueue`: runs the commands each operation returns
/// and feeds the engine's events back into the queue.
@MainActor
public final class Player {
    /// What a controller shows.
    public struct State: Equatable, Sendable {
        public let currentIndex: Int
        public let count: Int
        public let status: PlaybackStatus
        public let rate: SpeechRate
        /// See `PlaybackQueue.wordOffset`.
        public var wordOffset: Int? = nil
    }

    /// How many sentences after the one being spoken each `prepare` hint names.
    static let prefetchCount = 2

    /// Called after an operation or an engine event changes `state`, with the new state.
    public var onChange: ((State) -> Void)?
    public private(set) var state: State

    private var queue: PlaybackQueue
    private let engine: any SpeechEngine

    /// The voice the player speaks with; nil for the engine's default voice.
    public var voice: VoiceDescriptor? { queue.voice }

    /// Takes over the engine's `onEvent`.
    public init(engine: any SpeechEngine, rate: SpeechRate = .default, voice: VoiceDescriptor? = nil) {
        self.engine = engine
        let queue = PlaybackQueue(rate: rate, voice: voice)
        self.queue = queue
        state = Self.state(of: queue)
        engine.onEvent = { [weak self] event in
            self?.apply { $0.handle(event) }
        }
    }

    public func load(_ text: String) { apply { $0.load(text) } }
    /// See `PlaybackQueue.setLastIndex(_:)`.
    public func setLastIndex(_ index: Int?) { apply { $0.setLastIndex(index); return [] } }
    public func play() { apply { $0.play() } }
    public func pause() { apply { $0.pause() } }
    public func resume() { apply { $0.resume() } }
    public func togglePause() { apply { $0.togglePause() } }
    public func next() { apply { $0.next() } }
    public func previous() { apply { $0.previous() } }
    public func setRate(_ rate: SpeechRate) { apply { $0.setRate(rate) } }
    public func faster() { apply { $0.faster() } }
    public func slower() { apply { $0.slower() } }
    public func setVoice(_ voice: VoiceDescriptor?) { apply { $0.setVoice(voice) } }
    public func stop() { apply { $0.stop() } }

    /// Runs `operation` on the queue and its commands on the engine. The queue's live-rate flag
    /// is read from the engine first, because an engine such as `FallbackSpeechEngine` can
    /// change it between readings or in the middle of one. Every `speak` is followed by a
    /// `prepare` hint with the next `prefetchCount` sentences (empty at the last sentence).
    private func apply(_ operation: (inout PlaybackQueue) -> [SpeechCommand]) {
        queue.supportsLiveRate = engine.supportsLiveRate
        let commands = operation(&queue)
        for command in commands {
            switch command {
            case .speak(let text, let rate, let voice, let utteranceID):
                engine.speak(text, rate: rate, voice: voice, utteranceID: utteranceID)
                let upcoming = queue.sentences.dropFirst(queue.currentIndex + 1).prefix(Self.prefetchCount)
                engine.prepare(upcoming: Array(upcoming), voice: voice, rate: rate)
            case .pause:
                engine.pause()
            case .resume:
                engine.resume()
            case .stop:
                engine.stop()
            case .setRate(let rate):
                engine.setRate(rate)
            }
        }
        let newState = Self.state(of: queue)
        if newState != state {
            state = newState
            onChange?(newState)
        }
    }

    private static func state(of queue: PlaybackQueue) -> State {
        State(
            currentIndex: queue.currentIndex, count: queue.sentences.isEmpty ? 0 : queue.lastIndex + 1, status: queue.status,
            rate: queue.rate, wordOffset: queue.wordOffset
        )
    }
}
