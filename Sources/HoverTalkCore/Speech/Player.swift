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
    }

    /// Called after an operation or an engine event changes `state`, with the new state.
    public var onChange: ((State) -> Void)?
    public private(set) var state: State

    private var queue: PlaybackQueue
    private let engine: any SpeechEngine

    /// Takes over the engine's `onEvent`.
    public init(engine: any SpeechEngine, rate: SpeechRate = .default) {
        self.engine = engine
        let queue = PlaybackQueue(rate: rate)
        self.queue = queue
        state = Self.state(of: queue)
        engine.onEvent = { [weak self] event in
            self?.apply { $0.handle(event) }
        }
    }

    public func load(_ text: String) { apply { $0.load(text) } }
    public func play() { apply { $0.play() } }
    public func pause() { apply { $0.pause() } }
    public func resume() { apply { $0.resume() } }
    public func togglePause() { apply { $0.togglePause() } }
    public func next() { apply { $0.next() } }
    public func previous() { apply { $0.previous() } }
    public func setRate(_ rate: SpeechRate) { apply { $0.setRate(rate) } }
    public func faster() { apply { $0.faster() } }
    public func slower() { apply { $0.slower() } }
    public func stop() { apply { $0.stop() } }

    private func apply(_ operation: (inout PlaybackQueue) -> [SpeechCommand]) {
        let commands = operation(&queue)
        for command in commands {
            switch command {
            case .speak(let text, let rate, let utteranceID):
                engine.speak(text, rate: rate, utteranceID: utteranceID)
            case .pause:
                engine.pause()
            case .resume:
                engine.resume()
            case .stop:
                engine.stop()
            }
        }
        let newState = Self.state(of: queue)
        if newState != state {
            state = newState
            onChange?(newState)
        }
    }

    private static func state(of queue: PlaybackQueue) -> State {
        State(currentIndex: queue.currentIndex, count: queue.sentences.count, status: queue.status, rate: queue.rate)
    }
}
