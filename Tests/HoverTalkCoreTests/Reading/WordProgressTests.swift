import Foundation
import Testing
@testable import HoverTalkCore

@Suite("Word progress")
struct WordProgressTests {
    private func event(_ id: UUID?, _ kind: SpeechEngineEvent.Kind) -> SpeechEngineEvent {
        SpeechEngineEvent(utteranceID: id ?? UUID(), kind: kind)
    }

    @Test("The queue reports the word offset of the latest progress, and none before it")
    func queueWordOffset() {
        var queue = PlaybackQueue()
        _ = queue.load("Hello there. Bye now.")
        _ = queue.play()
        #expect(queue.wordOffset == nil)
        _ = queue.handle(event(queue.currentUtteranceID, .progress(characterOffset: 6)))
        #expect(queue.wordOffset == 6)
    }

    @Test("Moving to another sentence clears the word offset")
    func clearedOnMove() {
        var queue = PlaybackQueue()
        _ = queue.load("Hello there. Bye now.")
        _ = queue.play()
        _ = queue.handle(event(queue.currentUtteranceID, .progress(characterOffset: 6)))
        _ = queue.next()
        #expect(queue.wordOffset == nil)
    }

    @Test("A stale progress event does not move the word")
    func staleProgress() {
        var queue = PlaybackQueue()
        _ = queue.load("Hello there.")
        _ = queue.play()
        _ = queue.handle(event(UUID(), .progress(characterOffset: 6)))
        #expect(queue.wordOffset == nil)
    }

    @Test("The player state carries the word offset")
    @MainActor
    func playerState() {
        let engine = FakeSpeechEngine()
        let player = Player(engine: engine)
        player.load("Hello there.")
        player.play()
        engine.emit(.progress(characterOffset: 6), for: engine.lastSpokenID)
        #expect(player.state.wordOffset == 6)
    }
}

@Suite("SentenceAnchors")
struct SentenceAnchorsTests {
    /// Each Character anchored to its own index, so anchors read as positions in the text.
    private func mapped(_ text: String) -> MappedText<Int> {
        MappedText(elements: text.enumerated().map { ($0.element, $0.offset) })
    }

    @Test("Sentences match the splitter, and each lists its non-whitespace anchors")
    func sentences() {
        let anchors = SentenceAnchors(mapped("Hi you. Go."))
        #expect(anchors.sentences == SentenceSplitter().split("Hi you. Go."))
        #expect(anchors.anchors(ofSentence: 1).map(\.anchor) == [8, 9, 10])
    }

    @Test("The word at a UTF-16 offset runs to the next whitespace")
    func word() {
        let anchors = SentenceAnchors(mapped("Hi there, friend."))
        #expect(anchors.word(inSentence: 0, atUTF16Offset: 3).map(\.anchor) == [3, 4, 5, 6, 7, 8])
        #expect(anchors.word(inSentence: 0, atUTF16Offset: 10).map(\.anchor) == [10, 11, 12, 13, 14, 15, 16])
    }

    @Test("An offset inside a word, or past the sentence, is handled")
    func edges() {
        let anchors = SentenceAnchors(mapped("Hi there."))
        #expect(anchors.word(inSentence: 0, atUTF16Offset: 5).map(\.anchor) == [3, 4, 5, 6, 7, 8])
        #expect(anchors.word(inSentence: 0, atUTF16Offset: 99).isEmpty)
        #expect(anchors.word(inSentence: 7, atUTF16Offset: 0).isEmpty)
    }

    @Test("Offsets count UTF-16 units, so an emoji before the word shifts it by two")
    func utf16() {
        let anchors = SentenceAnchors(mapped("😀 ok"))
        #expect(anchors.word(inSentence: 0, atUTF16Offset: 3).map(\.anchor) == [2, 3])
    }

    @Test("Characters without an anchor are left out")
    func unanchored() {
        var text = MappedText<Int>()
        text.append("a", anchor: 0)
        text.append(" ", anchor: nil)
        text.append("bc", anchor: nil)
        let anchors = SentenceAnchors(text)
        #expect(anchors.word(inSentence: 0, atUTF16Offset: 2).isEmpty)
        #expect(anchors.anchors(ofSentence: 0).map(\.anchor) == [0])
    }
}
