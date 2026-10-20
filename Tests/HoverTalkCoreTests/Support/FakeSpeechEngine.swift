import Foundation
@testable import HoverTalkCore

/// Records every call and lets the test emit engine events.
@MainActor
final class FakeSpeechEngine: SpeechEngine {
    enum Call: Equatable {
        case speak(text: String, rate: SpeechRate, voice: VoiceDescriptor? = nil, utteranceID: UUID)
        case pause
        case resume
        case stop
        case setRate(SpeechRate)
    }

    /// One `prepare(upcoming:voice:rate:)` call.
    struct Preparation: Equatable {
        let upcoming: [String]
        let voice: VoiceDescriptor?
        let rate: SpeechRate
    }

    var onEvent: ((SpeechEngineEvent) -> Void)?
    var supportsLiveRate = false
    private(set) var calls: [Call] = []
    /// Kept apart from `calls`, so tests that compare `calls` do not depend on prefetch hints.
    private(set) var preparations: [Preparation] = []

    var lastSpokenID: UUID? {
        for call in calls.reversed() {
            if case .speak(_, _, _, let id) = call { return id }
        }
        return nil
    }

    var spokenTexts: [String] {
        calls.compactMap { call in
            if case .speak(let text, _, _, _) = call { return text }
            return nil
        }
    }

    func speak(_ text: String, rate: SpeechRate, voice: VoiceDescriptor?, utteranceID: UUID) {
        calls.append(.speak(text: text, rate: rate, voice: voice, utteranceID: utteranceID))
    }

    func pause() { calls.append(.pause) }
    func resume() { calls.append(.resume) }
    func stop() { calls.append(.stop) }
    func setRate(_ rate: SpeechRate) { calls.append(.setRate(rate)) }

    func prepare(upcoming: [String], voice: VoiceDescriptor?, rate: SpeechRate) {
        preparations.append(Preparation(upcoming: upcoming, voice: voice, rate: rate))
    }

    func emit(_ kind: SpeechEngineEvent.Kind, for id: UUID?) {
        onEvent?(SpeechEngineEvent(utteranceID: id ?? UUID(), kind: kind))
    }

    func clearCalls() {
        calls.removeAll()
        preparations.removeAll()
    }
}

/// An engine that implements only the required members, so the protocol's defaults apply.
@MainActor
final class MinimalSpeechEngine: SpeechEngine {
    var onEvent: ((SpeechEngineEvent) -> Void)?
    func speak(_ text: String, rate: SpeechRate, voice: VoiceDescriptor?, utteranceID: UUID) {}
    func pause() {}
    func resume() {}
    func stop() {}
}
