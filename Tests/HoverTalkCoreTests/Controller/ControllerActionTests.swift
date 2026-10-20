import Foundation
import Testing
@testable import HoverTalkCore

/// Accepts every command and never emits events, so only the queue's own state changes.
@MainActor
private final class SilentSpeechEngine: SpeechEngine {
    var onEvent: ((SpeechEngineEvent) -> Void)?
    func speak(_ text: String, rate: SpeechRate, voice: VoiceDescriptor?, utteranceID: UUID) {}
    func pause() {}
    func resume() {}
    func stop() {}
}

private let text = "Hola, este es el primer paso. Then the second step runs. Done."

@MainActor
@Suite("ControllerAction")
struct ControllerActionTests {
    @Test("Each controller action runs the matching player operation")
    func actionsDrivePlayer() {
        let player = Player(engine: SilentSpeechEngine())
        player.load(text)

        player.perform(.playPause)
        #expect(player.state.status == .playing)
        #expect(player.state.currentIndex == 0)

        player.perform(.next)
        #expect(player.state.currentIndex == 1)

        player.perform(.previous)
        #expect(player.state.currentIndex == 0)

        player.perform(.faster)
        #expect(player.state.rate == SpeechRate(1.25))

        player.perform(.slower)
        #expect(player.state.rate == .default)

        player.perform(.playPause)
        #expect(player.state.status == .paused)

        player.perform(.playPause)
        #expect(player.state.status == .playing)

        player.perform(.stop)
        #expect(player.state.status == .idle)
    }
}
