import Foundation

public enum PlaybackStatus: Equatable, Sendable {
    case idle
    case playing
    case paused
    case finished
}

/// An instruction for the speech engine, produced by `PlaybackQueue`.
public enum SpeechCommand: Equatable, Sendable {
    /// `voice` nil means the engine's default voice.
    case speak(text: String, rate: SpeechRate, voice: VoiceDescriptor? = nil, utteranceID: UUID)
    case pause
    case resume
    case stop
    /// Change the current utterance's rate in place; emitted only with `supportsLiveRate`.
    case setRate(SpeechRate)
}

/// Sentence-by-sentence playback as a pure state machine.
///
/// Every operation updates the state and returns the commands the engine must run, in order.
/// The queue never talks to an engine itself, so its behavior is testable without audio.
///
/// Each `speak` command carries a fresh utterance ID, and `handle(_:)` ignores events whose
/// ID is not the current one. A late `.finished`, `.cancelled` or `.failed` from an utterance
/// that was stopped by a skip, a rate change (without live rate) or a voice change therefore
/// cannot move the cursor a second time or pause the utterance that replaced it.
public struct PlaybackQueue: Equatable, Sendable {
    public private(set) var sentences: [String] = []
    public private(set) var currentIndex = 0
    public private(set) var status = PlaybackStatus.idle
    public private(set) var rate: SpeechRate
    /// The voice every `speak` command carries; nil for the engine's default voice.
    public private(set) var voice: VoiceDescriptor?
    /// The utterance the engine holds for the current sentence, or nil when it holds none
    /// (for example when idle, finished, or paused after a skip, a voice change, or a rate change
    /// without live rate).
    public private(set) var currentUtteranceID: UUID?
    /// UTF-16 offset, within the current sentence, of the last word the engine reported.
    public private(set) var characterOffset = 0
    /// The UTF-16 offset, in the current sentence, of the word the engine reported last, for
    /// highlighting it; `nil` before the first progress of an utterance and for engines that
    /// report no progress (such as the voice server engine).
    public private(set) var wordOffset: Int?

    /// UTF-16 offset in the current sentence where the current utterance's text starts.
    /// Nonzero after a rate change re-speaks the rest of a sentence.
    private var utteranceStart = 0
    /// UTF-16 length of the current utterance's text; progress offsets must be below it.
    private var utteranceLength = 0

    /// Whether the engine changes the rate of an utterance in place (`SpeechEngine.supportsLiveRate`).
    /// When true, a rate change emits `.setRate` and keeps the utterance; when false it stops the
    /// utterance and speaks the rest of the sentence again.
    public var supportsLiveRate: Bool

    public init(rate: SpeechRate = .default, voice: VoiceDescriptor? = nil, supportsLiveRate: Bool = false) {
        self.rate = rate
        self.voice = voice
        self.supportsLiveRate = supportsLiveRate
    }

    /// The last sentence playback reads before it finishes: the last one, or an earlier limit
    /// (`setLastIndex(_:)`), such as the end of the paragraph in paragraph reading mode.
    public var lastIndex: Int {
        let last = sentences.count - 1
        guard let limit else { return last }
        return min(max(limit, currentIndex, 0), last)
    }
    private var limit: Int?

    /// Finishes playback after sentence `index` instead of the last one, or, with `nil`, reads
    /// to the end. Takes effect at once, also while playing; a limit before the current
    /// sentence counts as the current sentence. `load(_:)` clears it.
    public mutating func setLastIndex(_ index: Int?) {
        limit = index
    }

    public var currentSentence: String? {
        sentences.indices.contains(currentIndex) ? sentences[currentIndex] : nil
    }

    /// Replaces the sentences with those of `text` and returns to idle. The rate and the voice
    /// are kept.
    public mutating func load(_ text: String) -> [SpeechCommand] {
        let commands = stop()
        sentences = SentenceSplitter().split(text)
        limit = nil
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
    /// no longer holds one: from its beginning after a skip or a voice change, from the last
    /// reported word after a rate change.
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
        guard currentIndex < lastIndex else {
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

    /// Stores the rate. With live rate, the held utterance, playing or paused, takes the new rate
    /// in place. Without it: while playing, the rest of the current sentence is spoken again at
    /// the new rate right away; while paused, the held utterance is dropped so resume does that.
    public mutating func setRate(_ newRate: SpeechRate) -> [SpeechCommand] {
        guard newRate != rate else { return [] }
        rate = newRate
        guard currentUtteranceID != nil else { return [] }
        if supportsLiveRate {
            return [.setRate(newRate)]
        }
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

    /// Stores the voice. While playing, the current sentence is spoken again from its beginning
    /// with the new voice right away; while paused, the held utterance is dropped and resume
    /// does that. Unlike a rate change, which goes on from the last word, a new voice restarts
    /// the sentence, so no sentence is heard in two voices.
    public mutating func setVoice(_ newVoice: VoiceDescriptor?) -> [SpeechCommand] {
        guard newVoice != voice else { return [] }
        voice = newVoice
        guard status == .playing || status == .paused else { return [] }
        var commands = releaseUtterance()
        moveTo(currentIndex)
        if status == .playing {
            commands.append(speakCurrentSentence(fromUTF16Offset: 0))
        }
        return commands
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
                wordOffset = characterOffset
            }
            return []
        case .finished:
            currentUtteranceID = nil
            guard currentIndex < lastIndex else {
                status = .finished
                return []
            }
            moveTo(currentIndex + 1)
            // A finish that raced with pause() moves the cursor; resume() speaks the sentence.
            return status == .playing ? [speakCurrentSentence(fromUTF16Offset: 0)] : []
        case .cancelled, .failed:
            // For `.cancelled` this is defensive: every `.stop` this queue emits clears
            // `currentUtteranceID` first (`releaseUtterance()`, `stop()`), so a cancel that still
            // matches came from outside the queue. A `.failed` is the engine giving up on the
            // utterance. Either way pause, so resume() can speak the rest of the sentence.
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
        wordOffset = nil
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
        wordOffset = nil
        return .speak(text: text, rate: rate, voice: voice, utteranceID: id)
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
