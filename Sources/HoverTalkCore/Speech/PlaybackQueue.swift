import Foundation

public enum PlaybackStatus: Equatable, Sendable {
    case idle
    case playing
    case paused
    case finished
}

/// An instruction for the speech engine, produced by `PlaybackQueue`.
public enum SpeechCommand: Equatable, Sendable {
    case speak(text: String, rate: SpeechRate, utteranceID: UUID)
    case pause
    case resume
    case stop
}

/// Sentence-by-sentence playback as a pure state machine.
///
/// Every operation updates the state and returns the commands the engine must run, in order.
/// The queue never talks to an engine itself, so its behavior is testable without audio.
///
/// Each `speak` command carries a fresh utterance ID, and `handle(_:)` ignores events whose
/// ID is not the current one. A late `.finished` or `.cancelled` from an utterance that was
/// stopped by a skip or a rate change therefore cannot move the cursor a second time.
public struct PlaybackQueue: Equatable, Sendable {
    public private(set) var sentences: [String] = []
    public private(set) var currentIndex = 0
    public private(set) var status = PlaybackStatus.idle
    public private(set) var rate: SpeechRate
    /// The utterance the engine holds for the current sentence, or nil when it holds none
    /// (for example when idle, finished, or paused after a skip or a rate change).
    public private(set) var currentUtteranceID: UUID?
    /// UTF-16 offset, within the current sentence, of the last word the engine reported.
    public private(set) var characterOffset = 0

    /// UTF-16 offset in the current sentence where the current utterance's text starts.
    /// Nonzero after a rate change re-speaks the rest of a sentence.
    private var utteranceStart = 0
    /// UTF-16 length of the current utterance's text; progress offsets must be below it.
    private var utteranceLength = 0

    public init(rate: SpeechRate = .default) {
        self.rate = rate
    }

    public var currentSentence: String? {
        sentences.indices.contains(currentIndex) ? sentences[currentIndex] : nil
    }

    /// Replaces the sentences with those of `text` and returns to idle. The rate is kept.
    public mutating func load(_ text: String) -> [SpeechCommand] {
        let commands = stop()
        sentences = SentenceSplitter().split(text)
        return commands
    }

    /// Starts from the first sentence when idle or finished; resumes when paused.
    public mutating func play() -> [SpeechCommand] {
        switch status {
        case .playing:
            return []
        case .paused:
            return resume()
        case .idle, .finished:
            guard !sentences.isEmpty else { return [] }
            moveTo(0)
            status = .playing
            return [speakCurrentSentence(fromUTF16Offset: 0)]
        }
    }

    public mutating func pause() -> [SpeechCommand] {
        guard status == .playing else { return [] }
        status = .paused
        return [.pause]
    }

    /// Continues the paused utterance, or speaks the current sentence again when the engine
    /// no longer holds one: from its beginning after a skip, from the last reported word after
    /// a rate change.
    public mutating func resume() -> [SpeechCommand] {
        guard status == .paused else { return [] }
        status = .playing
        if currentUtteranceID != nil {
            return [.resume]
        }
        return [speakCurrentSentence(fromUTF16Offset: characterOffset)]
    }

    /// Play/pause for a single button: pauses when playing, otherwise plays or resumes.
    public mutating func togglePause() -> [SpeechCommand] {
        status == .playing ? pause() : play()
    }

    /// Moves exactly one sentence forward; at the last sentence playback finishes.
    /// While paused, only the cursor moves. Does nothing when idle or finished.
    public mutating func next() -> [SpeechCommand] {
        guard status == .playing || status == .paused else { return [] }
        var commands = releaseUtterance()
        guard currentIndex + 1 < sentences.count else {
            status = .finished
            return commands
        }
        moveTo(currentIndex + 1)
        if status == .playing {
            commands.append(speakCurrentSentence(fromUTF16Offset: 0))
        }
        return commands
    }

    /// Moves exactly one sentence back; at the first sentence it restarts that sentence.
    /// While paused, only the cursor moves. Does nothing when idle or finished.
    public mutating func previous() -> [SpeechCommand] {
        guard status == .playing || status == .paused else { return [] }
        var commands = releaseUtterance()
        moveTo(max(currentIndex - 1, 0))
        if status == .playing {
            commands.append(speakCurrentSentence(fromUTF16Offset: 0))
        }
        return commands
    }

    /// Stores the rate. While playing, the rest of the current sentence is spoken again at the
    /// new rate right away; while paused, the held utterance is dropped so resume does that.
    public mutating func setRate(_ newRate: SpeechRate) -> [SpeechCommand] {
        guard newRate != rate else { return [] }
        rate = newRate
        guard currentUtteranceID != nil else { return [] }
        var commands = releaseUtterance()
        if status == .playing {
            commands.append(speakCurrentSentence(fromUTF16Offset: characterOffset))
        }
        return commands
    }

    public mutating func faster() -> [SpeechCommand] {
        setRate(rate.faster())
    }

    public mutating func slower() -> [SpeechCommand] {
        setRate(rate.slower())
    }

    /// Returns to idle at the first sentence. Always emits `.stop`, even when nothing plays.
    public mutating func stop() -> [SpeechCommand] {
        status = .idle
        currentUtteranceID = nil
        moveTo(0)
        return [.stop]
    }

    public mutating func handle(_ event: SpeechEngineEvent) -> [SpeechCommand] {
        guard let currentID = currentUtteranceID, event.utteranceID == currentID else {
            return []
        }
        switch event.kind {
        case .started:
            return []
        case .progress(let offset):
            if (0..<utteranceLength).contains(offset) {
                characterOffset = utteranceStart + offset
            }
            return []
        case .finished:
            currentUtteranceID = nil
            guard currentIndex + 1 < sentences.count else {
                status = .finished
                return []
            }
            moveTo(currentIndex + 1)
            // A finish that raced with pause() moves the cursor; resume() speaks the sentence.
            return status == .playing ? [speakCurrentSentence(fromUTF16Offset: 0)] : []
        case .cancelled:
            // Defensive: every `.stop` this queue emits clears `currentUtteranceID` first
            // (`releaseUtterance()`, `stop()`), so a cancel that still matches came from outside
            // the queue. Pause so resume() can speak the rest of the sentence.
            currentUtteranceID = nil
            if status == .playing {
                status = .paused
            }
            return []
        }
    }

    // MARK: - Helpers

    private mutating func moveTo(_ index: Int) {
        currentIndex = index
        characterOffset = 0
    }

    /// Drops the utterance the engine holds, if any, and returns the command that stops it.
    private mutating func releaseUtterance() -> [SpeechCommand] {
        guard currentUtteranceID != nil else { return [] }
        currentUtteranceID = nil
        return [.stop]
    }

    /// Speaks the current sentence from the character that contains `offset` to its end.
    private mutating func speakCurrentSentence(fromUTF16Offset offset: Int) -> SpeechCommand {
        let sentence = sentences[currentIndex]
        let start = Self.characterStart(containingUTF16Offset: offset, in: sentence)
        let text = String(sentence[start...])
        let id = UUID()
        currentUtteranceID = id
        utteranceStart = start.utf16Offset(in: sentence)
        utteranceLength = text.utf16.count
        characterOffset = utteranceStart
        return .speak(text: text, rate: rate, utteranceID: id)
    }

    /// The start of the character that contains the UTF-16 `offset`, so an offset inside a
    /// surrogate pair or a combined character rounds down to a boundary.
    private static func characterStart(containingUTF16Offset offset: Int, in text: String) -> String.Index {
        var start = text.startIndex
        var position = 0
        for index in text.indices {
            guard position <= offset else { break }
            start = index
            position += text[index].utf16.count
        }
        return start
    }
}
