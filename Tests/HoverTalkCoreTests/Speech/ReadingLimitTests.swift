import Foundation
import Testing
@testable import HoverTalkCore

@Suite("Reading limit")
struct ReadingLimitTests {
    private func finish(_ queue: inout PlaybackQueue) -> [SpeechCommand] {
        queue.handle(SpeechEngineEvent(utteranceID: queue.currentUtteranceID ?? UUID(), kind: .finished))
    }

    @Test("Playback finishes after the limit sentence instead of the last one")
    func stopsAtLimit() {
        var queue = PlaybackQueue()
        _ = queue.load("One. Two. Three.")
        queue.setLastIndex(1)
        _ = queue.play()
        _ = finish(&queue)
        #expect(queue.currentIndex == 1)
        #expect(finish(&queue) == [])
        #expect(queue.status == .finished)
    }

    @Test("Removing the limit while reading lets playback go on to the end")
    func liftLimit() {
        var queue = PlaybackQueue()
        _ = queue.load("One. Two. Three.")
        queue.setLastIndex(0)
        _ = queue.play()
        queue.setLastIndex(nil)
        let commands = finish(&queue)
        #expect(queue.currentIndex == 1)
        #expect(commands.count == 1)
        #expect(queue.status == .playing)
    }

    @Test("Next at the limit finishes, like next at the last sentence")
    func nextAtLimit() {
        var queue = PlaybackQueue()
        _ = queue.load("One. Two. Three.")
        queue.setLastIndex(0)
        _ = queue.play()
        _ = queue.next()
        #expect(queue.status == .finished)
    }

    @Test("A limit past the end, or below the current sentence, is clamped")
    func clamped() {
        var queue = PlaybackQueue()
        _ = queue.load("One. Two.")
        queue.setLastIndex(9)
        #expect(queue.lastIndex == 1)
        _ = queue.play()
        _ = finish(&queue)
        queue.setLastIndex(0)
        #expect(queue.lastIndex == 1)
    }

    @Test("Loading new text clears the limit")
    func loadClears() {
        var queue = PlaybackQueue()
        _ = queue.load("One. Two.")
        queue.setLastIndex(0)
        _ = queue.load("A. B. C.")
        #expect(queue.lastIndex == 2)
    }

    @Test("The player's count is the number of sentences up to the limit")
    @MainActor
    func playerCount() {
        let player = Player(engine: FakeSpeechEngine())
        player.load("One. Two. Three.")
        player.setLastIndex(0)
        #expect(player.state.count == 1)
        player.setLastIndex(nil)
        #expect(player.state.count == 3)
    }
}
