import Foundation
import Testing
@testable import HoverTalkCore

private let sampleText = "Primera oración del texto. The report is ready for review. ¿Tercera pregunta? Fourth and last."
private let s0 = "Primera oración del texto."
private let s1 = "The report is ready for review."
private let s2 = "¿Tercera pregunta?"
private let s3 = "Fourth and last."

/// UTF-16 offset of the first occurrence of `word` in `text`, the unit engines report.
private func utf16Offset(of word: String, in text: String) -> Int {
    text.range(of: word)!.lowerBound.utf16Offset(in: text)
}

private func event(_ id: UUID?, _ kind: SpeechEngineEvent.Kind) -> SpeechEngineEvent {
    SpeechEngineEvent(utteranceID: id ?? UUID(), kind: kind)
}

/// A queue loaded with `sampleText` and playing sentence `index`.
private func playingQueue(at index: Int = 0, rate: SpeechRate = .default) -> PlaybackQueue {
    var queue = PlaybackQueue(rate: rate)
    _ = queue.load(sampleText)
    _ = queue.play()
    for _ in 0..<index {
        _ = queue.handle(event(queue.currentUtteranceID, .finished))
    }
    return queue
}

@Suite("PlaybackQueue loading and playing")
struct PlaybackQueueLoadingTests {
    @Test("load splits the text into sentences and stays idle")
    func loadSplits() {
        var queue = PlaybackQueue()
        let commands = queue.load(sampleText)

        #expect(commands == [.stop])
        #expect(queue.sentences == [s0, s1, s2, s3])
        #expect(queue.currentIndex == 0)
        #expect(queue.status == .idle)
        #expect(queue.currentUtteranceID == nil)
    }

    @Test("play from idle speaks the first sentence at the current rate with a fresh ID")
    func playFromIdle() throws {
        var queue = PlaybackQueue(rate: SpeechRate(1.5))
        _ = queue.load(sampleText)

        let commands = queue.play()
        let id = try #require(queue.currentUtteranceID)

        #expect(commands == [.speak(text: s0, rate: SpeechRate(1.5), utteranceID: id)])
        #expect(queue.status == .playing)
    }

    @Test("play with no sentences does nothing")
    func playEmpty() {
        var queue = PlaybackQueue()
        _ = queue.load("   \n  ")

        #expect(queue.play() == [])
        #expect(queue.status == .idle)
    }

    @Test("play while playing does nothing")
    func playWhilePlaying() {
        var queue = playingQueue()
        let before = queue

        #expect(queue.play() == [])
        #expect(queue == before)
    }

    @Test("A finished current utterance advances to the next sentence")
    func finishedAdvances() throws {
        var queue = playingQueue()
        let first = queue.currentUtteranceID

        let commands = queue.handle(event(first, .finished))
        let second = try #require(queue.currentUtteranceID)

        #expect(commands == [.speak(text: s1, rate: .default, utteranceID: second)])
        #expect(second != first)
        #expect(queue.currentIndex == 1)
        #expect(queue.status == .playing)
    }

    @Test("Finishing the last sentence ends playback without commands")
    func finishedLast() {
        var queue = playingQueue(at: 3)

        #expect(queue.handle(event(queue.currentUtteranceID, .finished)) == [])
        #expect(queue.status == .finished)
        #expect(queue.currentUtteranceID == nil)
        #expect(queue.currentIndex == 3)
    }

    @Test("play after finishing restarts from the first sentence")
    func playAfterFinished() throws {
        var queue = playingQueue(at: 3)
        _ = queue.handle(event(queue.currentUtteranceID, .finished))

        let commands = queue.play()
        let id = try #require(queue.currentUtteranceID)

        #expect(commands == [.speak(text: s0, rate: .default, utteranceID: id)])
        #expect(queue.currentIndex == 0)
        #expect(queue.status == .playing)
    }

    @Test("load while playing stops the engine and resets to idle")
    func loadWhilePlaying() {
        var queue = playingQueue(at: 2)
        let old = queue.currentUtteranceID

        #expect(queue.load("Un texto nuevo. A new text.") == [.stop])
        #expect(queue.sentences == ["Un texto nuevo.", "A new text."])
        #expect(queue.currentIndex == 0)
        #expect(queue.status == .idle)
        #expect(queue.handle(event(old, .finished)) == [])
        #expect(queue.currentIndex == 0)
    }
}

@Suite("PlaybackQueue navigation")
struct PlaybackQueueNavigationTests {
    @Test("next while playing moves exactly one sentence forward")
    func nextWhilePlaying() throws {
        var queue = playingQueue(at: 1)

        let commands = queue.next()
        let id = try #require(queue.currentUtteranceID)

        #expect(commands == [.stop, .speak(text: s2, rate: .default, utteranceID: id)])
        #expect(queue.currentIndex == 2)
        #expect(queue.status == .playing)
    }

    @Test("next at the last sentence stops and finishes")
    func nextAtLast() {
        var queue = playingQueue(at: 3)

        #expect(queue.next() == [.stop])
        #expect(queue.status == .finished)
        #expect(queue.currentUtteranceID == nil)
    }

    @Test("previous while playing moves exactly one sentence back")
    func previousWhilePlaying() throws {
        var queue = playingQueue(at: 2)

        let commands = queue.previous()
        let id = try #require(queue.currentUtteranceID)

        #expect(commands == [.stop, .speak(text: s1, rate: .default, utteranceID: id)])
        #expect(queue.currentIndex == 1)
    }

    @Test("previous at the first sentence restarts it with a fresh ID")
    func previousAtFirst() throws {
        var queue = playingQueue()
        let old = queue.currentUtteranceID

        let commands = queue.previous()
        let id = try #require(queue.currentUtteranceID)

        #expect(commands == [.stop, .speak(text: s0, rate: .default, utteranceID: id)])
        #expect(id != old)
        #expect(queue.currentIndex == 0)
    }

    @Test("next and previous restart the sentence from its beginning")
    func navigationResetsOffset() {
        var queue = playingQueue()
        _ = queue.handle(event(queue.currentUtteranceID, .progress(characterOffset: 8)))

        _ = queue.next()
        #expect(queue.characterOffset == 0)
    }

    @Test("next and previous do nothing while idle or finished")
    func navigationWhenNotPlaying() {
        var idle = PlaybackQueue()
        _ = idle.load(sampleText)
        #expect(idle.next() == [])
        #expect(idle.previous() == [])
        #expect(idle.currentIndex == 0)

        var finished = playingQueue(at: 3)
        _ = finished.next()
        let before = finished
        #expect(finished.next() == [])
        #expect(finished.previous() == [])
        #expect(finished == before)
    }
}

@Suite("PlaybackQueue stale events")
struct PlaybackQueueStaleEventTests {
    @Test("Late finished and cancelled events from a skipped utterance do not skip an extra sentence")
    func lateEventsAfterNext() throws {
        var queue = playingQueue()
        let skipped = queue.currentUtteranceID
        _ = queue.next()
        let current = try #require(queue.currentUtteranceID)

        #expect(queue.handle(event(skipped, .cancelled)) == [])
        #expect(queue.handle(event(skipped, .finished)) == [])
        #expect(queue.currentIndex == 1)
        #expect(queue.currentUtteranceID == current)
        #expect(queue.status == .playing)

        let commands = queue.handle(event(current, .finished))
        let next = try #require(queue.currentUtteranceID)
        #expect(commands == [.speak(text: s2, rate: .default, utteranceID: next)])
        #expect(queue.currentIndex == 2)
    }

    @Test("Late events from two quick skips are all ignored")
    func lateEventsAfterTwoSkips() {
        var queue = playingQueue()
        let first = queue.currentUtteranceID
        _ = queue.next()
        let second = queue.currentUtteranceID
        _ = queue.next()

        for id in [first, second] {
            _ = queue.handle(event(id, .finished))
            _ = queue.handle(event(id, .cancelled))
        }
        #expect(queue.currentIndex == 2)
        #expect(queue.status == .playing)
    }

    @Test("Late events after previous do not move the cursor")
    func lateEventsAfterPrevious() {
        var queue = playingQueue(at: 2)
        let skipped = queue.currentUtteranceID
        _ = queue.previous()

        _ = queue.handle(event(skipped, .finished))
        #expect(queue.currentIndex == 1)
    }

    @Test("Late events after a rate change do not advance")
    func lateEventsAfterRateChange() {
        var queue = playingQueue()
        let replaced = queue.currentUtteranceID
        _ = queue.faster()

        _ = queue.handle(event(replaced, .cancelled))
        _ = queue.handle(event(replaced, .finished))
        #expect(queue.currentIndex == 0)
        #expect(queue.status == .playing)
    }

    @Test("Late events after stop are ignored")
    func lateEventsAfterStop() {
        var queue = playingQueue(at: 1)
        let stopped = queue.currentUtteranceID
        _ = queue.stop()
        let before = queue

        #expect(queue.handle(event(stopped, .finished)) == [])
        #expect(queue == before)
    }

    @Test("Progress from a stale utterance is ignored")
    func staleProgress() {
        var queue = playingQueue()
        _ = queue.handle(event(UUID(), .progress(characterOffset: 4)))
        #expect(queue.characterOffset == 0)
    }

    @Test("Progress outside the utterance text is ignored", arguments: [-1, 1_000])
    func outOfRangeProgress(offset: Int) {
        var queue = playingQueue()
        _ = queue.handle(event(queue.currentUtteranceID, .progress(characterOffset: 8)))
        _ = queue.handle(event(queue.currentUtteranceID, .progress(characterOffset: offset)))
        #expect(queue.characterOffset == 8)
    }
}

@Suite("PlaybackQueue pause and resume")
struct PlaybackQueuePauseTests {
    @Test("pause and resume forward to the engine")
    func pauseResume() {
        var queue = playingQueue()
        let id = queue.currentUtteranceID

        #expect(queue.pause() == [.pause])
        #expect(queue.status == .paused)
        #expect(queue.pause() == [])

        #expect(queue.resume() == [.resume])
        #expect(queue.status == .playing)
        #expect(queue.currentUtteranceID == id)
        #expect(queue.resume() == [])
    }

    @Test("togglePause plays from idle, then pauses and resumes")
    func togglePause() throws {
        var queue = PlaybackQueue()
        _ = queue.load(sampleText)

        let commands = queue.togglePause()
        let id = try #require(queue.currentUtteranceID)
        #expect(commands == [.speak(text: s0, rate: .default, utteranceID: id)])

        #expect(queue.togglePause() == [.pause])
        #expect(queue.status == .paused)
        #expect(queue.togglePause() == [.resume])
        #expect(queue.status == .playing)
        #expect(queue.currentUtteranceID == id)
    }

    @Test("togglePause after finishing restarts from the first sentence")
    func togglePauseAfterFinished() throws {
        var queue = playingQueue(at: 3)
        _ = queue.next()

        let commands = queue.togglePause()
        let id = try #require(queue.currentUtteranceID)
        #expect(commands == [.speak(text: s0, rate: .default, utteranceID: id)])
        #expect(queue.status == .playing)
    }

    @Test("next while paused moves the cursor without speaking until resume")
    func nextWhilePaused() throws {
        var queue = playingQueue()
        _ = queue.pause()

        #expect(queue.next() == [.stop])
        #expect(queue.currentIndex == 1)
        #expect(queue.status == .paused)
        #expect(queue.currentUtteranceID == nil)

        #expect(queue.next() == [])
        #expect(queue.currentIndex == 2)

        let commands = queue.resume()
        let id = try #require(queue.currentUtteranceID)
        #expect(commands == [.speak(text: s2, rate: .default, utteranceID: id)])
        #expect(queue.status == .playing)
    }

    @Test("previous while paused moves the cursor without speaking until resume")
    func previousWhilePaused() throws {
        var queue = playingQueue(at: 2)
        _ = queue.pause()

        #expect(queue.previous() == [.stop])
        #expect(queue.currentIndex == 1)
        #expect(queue.status == .paused)

        let commands = queue.resume()
        let id = try #require(queue.currentUtteranceID)
        #expect(commands == [.speak(text: s1, rate: .default, utteranceID: id)])
    }

    @Test("next at the last sentence while paused finishes")
    func nextAtLastWhilePaused() {
        var queue = playingQueue(at: 3)
        _ = queue.pause()

        #expect(queue.next() == [.stop])
        #expect(queue.status == .finished)
    }

    @Test("A finish that races with pause advances the cursor but stays paused")
    func finishedWhilePaused() throws {
        var queue = playingQueue()
        let id = queue.currentUtteranceID
        _ = queue.pause()

        #expect(queue.handle(event(id, .finished)) == [])
        #expect(queue.currentIndex == 1)
        #expect(queue.status == .paused)

        let commands = queue.resume()
        let next = try #require(queue.currentUtteranceID)
        #expect(commands == [.speak(text: s1, rate: .default, utteranceID: next)])
    }

    @Test("A cancel the queue did not request pauses so resume can re-speak the rest")
    func unrequestedCancel() throws {
        var queue = playingQueue(at: 1)
        let id = queue.currentUtteranceID
        _ = queue.handle(event(id, .progress(characterOffset: utf16Offset(of: "ready", in: s1))))

        #expect(queue.handle(event(id, .cancelled)) == [])
        #expect(queue.status == .paused)
        #expect(queue.currentUtteranceID == nil)

        let commands = queue.resume()
        let fresh = try #require(queue.currentUtteranceID)
        #expect(commands == [.speak(text: "ready for review.", rate: .default, utteranceID: fresh)])
    }
}

@Suite("PlaybackQueue rate changes")
struct PlaybackQueueRateTests {
    @Test("A rate change while playing re-speaks the rest of the sentence from the last word")
    func rateChangeWhilePlaying() throws {
        var queue = playingQueue(at: 1)
        let old = queue.currentUtteranceID
        _ = queue.handle(event(old, .progress(characterOffset: utf16Offset(of: "ready", in: s1))))

        let commands = queue.setRate(SpeechRate(1.5))
        let id = try #require(queue.currentUtteranceID)

        #expect(commands == [.stop, .speak(text: "ready for review.", rate: SpeechRate(1.5), utteranceID: id)])
        #expect(id != old)
        #expect(queue.rate == SpeechRate(1.5))
        #expect(queue.currentIndex == 1)
        #expect(queue.status == .playing)
    }

    @Test("Offsets from a remainder utterance stay relative to the whole sentence")
    func offsetsAccumulate() throws {
        var queue = playingQueue(at: 1)
        _ = queue.handle(event(queue.currentUtteranceID, .progress(characterOffset: utf16Offset(of: "ready", in: s1))))
        _ = queue.faster()
        let remainder = "ready for review."
        _ = queue.handle(event(queue.currentUtteranceID, .progress(characterOffset: utf16Offset(of: "review", in: remainder))))

        #expect(queue.characterOffset == utf16Offset(of: "review", in: s1))

        let commands = queue.faster()
        let id = try #require(queue.currentUtteranceID)
        #expect(commands == [.stop, .speak(text: "review.", rate: SpeechRate(1.5), utteranceID: id)])
    }

    @Test("A rate change before any progress re-speaks the whole sentence")
    func rateChangeWithoutProgress() throws {
        var queue = playingQueue()

        let commands = queue.slower()
        let id = try #require(queue.currentUtteranceID)
        #expect(commands == [.stop, .speak(text: s0, rate: SpeechRate(0.75), utteranceID: id)])
    }

    @Test("A rate change while paused stops the utterance; resume re-speaks the rest at the new rate")
    func rateChangeWhilePaused() throws {
        var queue = playingQueue(at: 1)
        _ = queue.handle(event(queue.currentUtteranceID, .progress(characterOffset: utf16Offset(of: "ready", in: s1))))
        _ = queue.pause()

        #expect(queue.setRate(SpeechRate(2.0)) == [.stop])
        #expect(queue.status == .paused)
        #expect(queue.rate == SpeechRate(2.0))
        #expect(queue.faster() == [])

        let commands = queue.resume()
        let id = try #require(queue.currentUtteranceID)
        #expect(commands == [.speak(text: "ready for review.", rate: SpeechRate(2.25), utteranceID: id)])
    }

    @Test("A rate change while idle or finished only stores the rate")
    func rateChangeWhenNotPlaying() throws {
        var queue = PlaybackQueue()
        _ = queue.load(sampleText)

        #expect(queue.setRate(SpeechRate(2.0)) == [])
        #expect(queue.rate == SpeechRate(2.0))

        let commands = queue.play()
        let id = try #require(queue.currentUtteranceID)
        #expect(commands == [.speak(text: s0, rate: SpeechRate(2.0), utteranceID: id)])

        var finished = playingQueue(at: 3)
        _ = finished.next()
        #expect(finished.slower() == [])
        #expect(finished.rate == SpeechRate(0.75))
        #expect(finished.status == .finished)
    }

    @Test("Setting the same rate, or stepping past a bound, does nothing")
    func noOpRateChanges() {
        var queue = playingQueue(rate: SpeechRate(SpeechRate.maximum))
        let before = queue

        #expect(queue.setRate(SpeechRate(SpeechRate.maximum)) == [])
        #expect(queue.faster() == [])
        #expect(queue == before)

        var slowest = playingQueue(rate: SpeechRate(SpeechRate.minimum))
        #expect(slowest.slower() == [])
    }

    @Test("The remainder starts at a character boundary for UTF-16 offsets")
    func unicodeRemainder() throws {
        var queue = PlaybackQueue()
        _ = queue.load("Pedí un café ☕️ con leche. Say 😀 now.")
        _ = queue.play()
        let first = "Pedí un café ☕️ con leche."
        _ = queue.handle(event(queue.currentUtteranceID, .progress(characterOffset: utf16Offset(of: "con", in: first))))

        let commands = queue.faster()
        let id = try #require(queue.currentUtteranceID)
        #expect(commands == [.stop, .speak(text: "con leche.", rate: SpeechRate(1.25), utteranceID: id)])

        _ = queue.next()
        // "Say 😀 now.": the emoji occupies UTF-16 offsets 4 and 5; offset 5 is inside it.
        _ = queue.handle(event(queue.currentUtteranceID, .progress(characterOffset: 5)))
        let emojiCommands = queue.slower()
        let emojiID = try #require(queue.currentUtteranceID)
        #expect(emojiCommands == [.stop, .speak(text: "😀 now.", rate: .default, utteranceID: emojiID)])
    }
}

/// A queue for a live-rate engine, loaded with `sampleText` and playing sentence 1 with
/// progress at "ready".
private func liveQueue() -> PlaybackQueue {
    var queue = PlaybackQueue(supportsLiveRate: true)
    _ = queue.load(sampleText)
    _ = queue.play()
    _ = queue.handle(event(queue.currentUtteranceID, .finished))
    _ = queue.handle(event(queue.currentUtteranceID, .progress(characterOffset: utf16Offset(of: "ready", in: s1))))
    return queue
}

@Suite("PlaybackQueue live rate")
struct PlaybackQueueLiveRateTests {
    @Test("Without live rate by default; it can be set at creation or later")
    func configuration() {
        #expect(PlaybackQueue().supportsLiveRate == false)
        #expect(PlaybackQueue(supportsLiveRate: true).supportsLiveRate == true)
        var queue = PlaybackQueue()
        queue.supportsLiveRate = true
        #expect(queue.supportsLiveRate)
    }

    @Test("While playing, a rate change is one setRate command; the utterance and its progress stay")
    func whilePlaying() throws {
        var queue = liveQueue()
        let id = queue.currentUtteranceID

        #expect(queue.setRate(SpeechRate(1.5)) == [.setRate(SpeechRate(1.5))])
        #expect(queue.faster() == [.setRate(SpeechRate(1.75))])
        #expect(queue.slower() == [.setRate(SpeechRate(1.5))])
        #expect(queue.currentUtteranceID == id)
        #expect(queue.characterOffset == utf16Offset(of: "ready", in: s1))
        #expect(queue.status == .playing)
        #expect(queue.rate == SpeechRate(1.5))

        _ = queue.handle(event(id, .progress(characterOffset: utf16Offset(of: "review", in: s1))))
        #expect(queue.characterOffset == utf16Offset(of: "review", in: s1))

        let commands = queue.handle(event(id, .finished))
        let next = try #require(queue.currentUtteranceID)
        #expect(commands == [.speak(text: s2, rate: SpeechRate(1.5), utteranceID: next)])
    }

    @Test("While paused, the held utterance takes the new rate and resume continues it")
    func whilePaused() {
        var queue = liveQueue()
        let id = queue.currentUtteranceID
        _ = queue.pause()

        #expect(queue.setRate(SpeechRate(2.0)) == [.setRate(SpeechRate(2.0))])
        #expect(queue.currentUtteranceID == id)
        #expect(queue.status == .paused)
        #expect(queue.resume() == [.resume])
    }

    @Test("With no utterance held the rate is only stored, as without live rate")
    func nothingHeld() throws {
        var idle = PlaybackQueue(supportsLiveRate: true)
        _ = idle.load(sampleText)
        #expect(idle.setRate(SpeechRate(2.0)) == [])

        var pausedAfterSkip = liveQueue()
        _ = pausedAfterSkip.pause()
        _ = pausedAfterSkip.next()
        #expect(pausedAfterSkip.setRate(SpeechRate(2.0)) == [])
        let commands = pausedAfterSkip.resume()
        let id = try #require(pausedAfterSkip.currentUtteranceID)
        #expect(commands == [.speak(text: s2, rate: SpeechRate(2.0), utteranceID: id)])

        var same = liveQueue()
        #expect(same.setRate(.default) == [])
    }
}

@Suite("PlaybackQueue engine failures")
struct PlaybackQueueFailureTests {
    @Test("A failure of the current utterance pauses, so resume speaks the rest again")
    func failurePauses() throws {
        var queue = playingQueue(at: 1)
        let id = queue.currentUtteranceID
        _ = queue.handle(event(id, .progress(characterOffset: utf16Offset(of: "ready", in: s1))))

        #expect(queue.handle(event(id, .failed(reason: "timeout"))) == [])
        #expect(queue.status == .paused)
        #expect(queue.currentUtteranceID == nil)
        #expect(queue.currentIndex == 1)

        let commands = queue.resume()
        let fresh = try #require(queue.currentUtteranceID)
        #expect(commands == [.speak(text: "ready for review.", rate: .default, utteranceID: fresh)])
    }

    @Test("A failure of a replaced utterance is ignored")
    func staleFailure() {
        var queue = playingQueue(at: 1)
        let old = queue.currentUtteranceID
        _ = queue.next()
        let before = queue

        #expect(queue.handle(event(old, .failed(reason: "timeout"))) == [])
        #expect(queue == before)
    }
}

private let marisol = VoiceDescriptor(id: "com.apple.voice.premium.es-ES.Marisol", name: "Marisol (Premium)", language: "es-ES", quality: .premium)
private let samantha = VoiceDescriptor(id: "com.apple.voice.compact.en-US.Samantha", name: "Samantha", language: "en-US", quality: .default)

@Suite("PlaybackQueue voice changes")
struct PlaybackQueueVoiceTests {
    @Test("Every speak command carries the queue's voice, and load keeps the voice")
    func commandsCarryVoice() throws {
        var queue = PlaybackQueue(voice: marisol)
        _ = queue.load(sampleText)

        let first = queue.play()
        let firstID = try #require(queue.currentUtteranceID)
        #expect(first == [.speak(text: s0, rate: .default, voice: marisol, utteranceID: firstID)])

        let next = queue.handle(event(firstID, .finished))
        let nextID = try #require(queue.currentUtteranceID)
        #expect(next == [.speak(text: s1, rate: .default, voice: marisol, utteranceID: nextID)])

        _ = queue.load(sampleText)
        #expect(queue.voice == marisol)
    }

    @Test("A voice change while playing restarts the current sentence from its beginning with the new voice")
    func voiceChangeWhilePlaying() throws {
        var queue = playingQueue(at: 1)
        let old = queue.currentUtteranceID
        _ = queue.handle(event(old, .progress(characterOffset: utf16Offset(of: "ready", in: s1))))

        let commands = queue.setVoice(marisol)
        let id = try #require(queue.currentUtteranceID)

        #expect(commands == [.stop, .speak(text: s1, rate: .default, voice: marisol, utteranceID: id)])
        #expect(id != old)
        #expect(queue.voice == marisol)
        #expect(queue.currentIndex == 1)
        #expect(queue.characterOffset == 0)
        #expect(queue.status == .playing)
    }

    @Test("Late events from the utterance a voice change replaced do not advance")
    func lateEventsAfterVoiceChange() {
        var queue = playingQueue()
        let replaced = queue.currentUtteranceID
        _ = queue.setVoice(marisol)

        #expect(queue.handle(event(replaced, .cancelled)) == [])
        #expect(queue.handle(event(replaced, .finished)) == [])
        #expect(queue.currentIndex == 0)
        #expect(queue.status == .playing)
    }

    @Test("A voice change while paused stops the utterance; resume restarts the sentence with the new voice")
    func voiceChangeWhilePaused() throws {
        var queue = playingQueue(at: 1)
        _ = queue.handle(event(queue.currentUtteranceID, .progress(characterOffset: utf16Offset(of: "ready", in: s1))))
        _ = queue.pause()

        #expect(queue.setVoice(marisol) == [.stop])
        #expect(queue.status == .paused)
        #expect(queue.currentUtteranceID == nil)

        let commands = queue.resume()
        let id = try #require(queue.currentUtteranceID)
        #expect(commands == [.speak(text: s1, rate: .default, voice: marisol, utteranceID: id)])
    }

    @Test("After a rate change while paused, a voice change still restarts from the sentence start")
    func voiceChangeAfterPausedRateChange() throws {
        var queue = playingQueue(at: 1)
        _ = queue.handle(event(queue.currentUtteranceID, .progress(characterOffset: utf16Offset(of: "ready", in: s1))))
        _ = queue.pause()
        _ = queue.faster()

        #expect(queue.setVoice(marisol) == [])

        let commands = queue.resume()
        let id = try #require(queue.currentUtteranceID)
        #expect(commands == [.speak(text: s1, rate: SpeechRate(1.25), voice: marisol, utteranceID: id)])
    }

    @Test("A voice change while idle or finished only stores the voice")
    func voiceChangeWhenNotPlaying() throws {
        var queue = PlaybackQueue()
        _ = queue.load(sampleText)

        #expect(queue.setVoice(samantha) == [])
        #expect(queue.voice == samantha)

        let commands = queue.play()
        let id = try #require(queue.currentUtteranceID)
        #expect(commands == [.speak(text: s0, rate: .default, voice: samantha, utteranceID: id)])

        var finished = playingQueue(at: 3)
        _ = finished.next()
        #expect(finished.setVoice(marisol) == [])
        #expect(finished.voice == marisol)
        #expect(finished.status == .finished)
    }

    @Test("Setting the same voice does nothing; nil returns to the engine's default voice")
    func sameVoiceAndNil() throws {
        var queue = playingQueue()
        _ = queue.setVoice(marisol)
        let before = queue

        #expect(queue.setVoice(marisol) == [])
        #expect(queue == before)

        let commands = queue.setVoice(nil)
        let id = try #require(queue.currentUtteranceID)
        #expect(commands == [.stop, .speak(text: s0, rate: .default, voice: nil, utteranceID: id)])
    }
}

@Suite("PlaybackQueue stop")
struct PlaybackQueueStopTests {
    @Test("stop returns to idle at the first sentence and emits stop", arguments: [0, 2])
    func stopWhilePlaying(index: Int) {
        var queue = playingQueue(at: index)

        #expect(queue.stop() == [.stop])
        #expect(queue.status == .idle)
        #expect(queue.currentIndex == 0)
        #expect(queue.currentUtteranceID == nil)
        #expect(queue.sentences.count == 4)
    }

    @Test("stop while paused or idle also emits stop")
    func stopWhenNotPlaying() {
        var paused = playingQueue(at: 1)
        _ = paused.pause()
        #expect(paused.stop() == [.stop])
        #expect(paused.status == .idle)

        var idle = PlaybackQueue()
        #expect(idle.stop() == [.stop])
        #expect(idle.status == .idle)
    }

    @Test("play after stop starts again from the first sentence")
    func playAfterStop() throws {
        var queue = playingQueue(at: 2)
        _ = queue.stop()

        let commands = queue.play()
        let id = try #require(queue.currentUtteranceID)
        #expect(commands == [.speak(text: s0, rate: .default, utteranceID: id)])
    }
}
