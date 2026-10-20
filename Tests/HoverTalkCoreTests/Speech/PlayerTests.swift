import Foundation
import Testing
@testable import HoverTalkCore

private let text = "Hola, este es el primer paso. Then the second step runs. Done."

@MainActor
@Suite("Player")
struct PlayerTests {
    private let engine = FakeSpeechEngine()

    @Test("load and play speak the first sentence through the engine")
    func loadAndPlay() throws {
        let player = Player(engine: engine, rate: SpeechRate(1.25))
        player.load(text)
        player.play()

        let id = try #require(engine.lastSpokenID)
        #expect(engine.calls == [.stop, .speak(text: "Hola, este es el primer paso.", rate: SpeechRate(1.25), utteranceID: id)])
        #expect(player.state.status == .playing)
        #expect(player.state.count == 3)
        #expect(player.state.currentIndex == 0)
    }

    @Test("Engine events reach the queue: a finished utterance speaks the next sentence")
    func forwardsEvents() {
        let player = Player(engine: engine)
        player.load(text)
        player.play()

        engine.emit(.finished, for: engine.lastSpokenID)

        #expect(engine.spokenTexts == ["Hola, este es el primer paso.", "Then the second step runs."])
        #expect(player.state.currentIndex == 1)
    }

    @Test("A late event from a skipped utterance does not skip an extra sentence")
    func staleEventThroughPlayer() {
        let player = Player(engine: engine)
        player.load(text)
        player.play()
        let skipped = engine.lastSpokenID
        player.next()

        engine.emit(.cancelled, for: skipped)
        engine.emit(.finished, for: skipped)

        #expect(player.state.currentIndex == 1)
        #expect(engine.spokenTexts == ["Hola, este es el primer paso.", "Then the second step runs."])
    }

    @Test("Each control runs the matching engine commands")
    func controls() throws {
        let player = Player(engine: engine)
        player.load(text)
        player.play()
        engine.clearCalls()

        player.pause()
        player.resume()
        player.togglePause()
        player.togglePause()
        #expect(engine.calls == [.pause, .resume, .pause, .resume])

        engine.clearCalls()
        player.next()
        let nextID = try #require(engine.lastSpokenID)
        player.previous()
        let previousID = try #require(engine.lastSpokenID)
        #expect(engine.calls == [
            .stop, .speak(text: "Then the second step runs.", rate: .default, utteranceID: nextID),
            .stop, .speak(text: "Hola, este es el primer paso.", rate: .default, utteranceID: previousID),
        ])

        engine.clearCalls()
        player.faster()
        let fasterID = try #require(engine.lastSpokenID)
        player.setRate(SpeechRate(2.0))
        let rateID = try #require(engine.lastSpokenID)
        player.slower()
        let slowerID = try #require(engine.lastSpokenID)
        #expect(engine.calls == [
            .stop, .speak(text: "Hola, este es el primer paso.", rate: SpeechRate(1.25), utteranceID: fasterID),
            .stop, .speak(text: "Hola, este es el primer paso.", rate: SpeechRate(2.0), utteranceID: rateID),
            .stop, .speak(text: "Hola, este es el primer paso.", rate: SpeechRate(1.75), utteranceID: slowerID),
        ])

        engine.clearCalls()
        player.stop()
        #expect(engine.calls == [.stop])
        #expect(player.state.status == .idle)
    }

    @Test("onChange reports every state change")
    func reportsChanges() {
        let player = Player(engine: engine)
        var reported: [Player.State] = []
        player.onChange = { reported.append($0) }

        player.load(text)
        player.play()
        player.next()
        player.faster()
        player.pause()
        engine.emit(.finished, for: UUID())

        #expect(reported == [
            Player.State(currentIndex: 0, count: 3, status: .idle, rate: .default),
            Player.State(currentIndex: 0, count: 3, status: .playing, rate: .default),
            Player.State(currentIndex: 1, count: 3, status: .playing, rate: .default),
            Player.State(currentIndex: 1, count: 3, status: .playing, rate: SpeechRate(1.25)),
            Player.State(currentIndex: 1, count: 3, status: .paused, rate: SpeechRate(1.25)),
        ])
        #expect(player.state == reported.last)
    }

    @Test("onChange is not called when an operation changes nothing")
    func noChangeNoReport() {
        let player = Player(engine: engine)
        player.load(text)
        var reportCount = 0
        player.onChange = { _ in reportCount += 1 }

        player.pause()
        player.next()
        player.load(text)
        engine.emit(.finished, for: UUID())

        #expect(reportCount == 0)
    }

    @Test("setVoice restarts the current sentence with the new voice, and later sentences keep it")
    func voiceChange() throws {
        let paulina = VoiceDescriptor(id: "com.apple.voice.compact.es-MX.Paulina", name: "Paulina", language: "es-MX", quality: .default)
        let player = Player(engine: engine)
        player.load(text)
        player.play()
        engine.emit(.progress(characterOffset: 6), for: engine.lastSpokenID)
        engine.clearCalls()

        player.setVoice(paulina)
        let restartID = try #require(engine.lastSpokenID)
        #expect(engine.calls == [.stop, .speak(text: "Hola, este es el primer paso.", rate: .default, voice: paulina, utteranceID: restartID)])
        #expect(player.voice == paulina)

        engine.emit(.finished, for: restartID)
        let nextID = try #require(engine.lastSpokenID)
        #expect(engine.calls.last == .speak(text: "Then the second step runs.", rate: .default, voice: paulina, utteranceID: nextID))
    }

    @Test("A player created with a voice speaks with it")
    func initialVoice() throws {
        let samantha = VoiceDescriptor(id: "com.apple.voice.compact.en-US.Samantha", name: "Samantha", language: "en-US", quality: .default)
        let player = Player(engine: engine, voice: samantha)
        player.load(text)
        player.play()

        let id = try #require(engine.lastSpokenID)
        #expect(engine.calls.last == .speak(text: "Hola, este es el primer paso.", rate: .default, voice: samantha, utteranceID: id))
    }

    @Test("Playback finishes after the last sentence and reports it")
    func finishes() {
        let player = Player(engine: engine)
        player.load(text)
        player.play()
        for _ in 0..<3 {
            engine.emit(.finished, for: engine.lastSpokenID)
        }

        #expect(player.state.status == .finished)
        #expect(engine.spokenTexts.count == 3)
    }
}

@MainActor
@Suite("Player live rate and prefetch")
struct PlayerLiveRateTests {
    private let engine = FakeSpeechEngine()

    @Test("With a live-rate engine a rate change is one setRate call; the utterance goes on")
    func liveRate() throws {
        engine.supportsLiveRate = true
        let player = Player(engine: engine)
        player.load(text)
        player.play()
        let id = try #require(engine.lastSpokenID)
        engine.clearCalls()

        player.setRate(SpeechRate(2.0))
        player.faster()
        player.pause()
        player.slower()

        #expect(engine.calls == [.setRate(SpeechRate(2.0)), .setRate(SpeechRate(2.25)), .pause, .setRate(SpeechRate(2.0))])
        #expect(player.state.rate == SpeechRate(2.0))

        player.resume()
        engine.emit(.finished, for: id)
        let nextID = try #require(engine.lastSpokenID)
        #expect(engine.calls.suffix(2) == [.resume, .speak(text: "Then the second step runs.", rate: SpeechRate(2.0), utteranceID: nextID)])
    }

    @Test("The player asks the engine before every operation, so live rate follows the active engine")
    func liveRateFollowsEngine() throws {
        engine.supportsLiveRate = true
        let player = Player(engine: engine)
        player.load(text)
        player.play()
        player.faster()
        #expect(engine.calls.last == .setRate(SpeechRate(1.25)))

        engine.supportsLiveRate = false
        engine.clearCalls()
        player.faster()
        let id = try #require(engine.lastSpokenID)
        #expect(engine.calls == [.stop, .speak(text: "Hola, este es el primer paso.", rate: SpeechRate(1.5), utteranceID: id)])
    }

    @Test("Each spoken sentence comes with a prefetch hint for the next two sentences, with its voice and rate")
    func prefetch() {
        let samantha = VoiceDescriptor(id: "com.apple.voice.compact.en-US.Samantha", name: "Samantha", language: "en-US", quality: .default)
        let player = Player(engine: engine, rate: SpeechRate(1.5), voice: samantha)
        player.load(text)
        player.play()
        engine.emit(.finished, for: engine.lastSpokenID)
        engine.emit(.finished, for: engine.lastSpokenID)

        #expect(engine.preparations == [
            FakeSpeechEngine.Preparation(upcoming: ["Then the second step runs.", "Done."], voice: samantha, rate: SpeechRate(1.5)),
            FakeSpeechEngine.Preparation(upcoming: ["Done."], voice: samantha, rate: SpeechRate(1.5)),
            FakeSpeechEngine.Preparation(upcoming: [], voice: samantha, rate: SpeechRate(1.5)),
        ])
    }

    @Test("Operations that speak nothing send no prefetch hint")
    func noPrefetchWithoutSpeaking() {
        let player = Player(engine: engine)
        player.load(text)
        player.play()
        engine.clearCalls()

        player.pause()
        player.next()
        player.stop()

        #expect(engine.preparations.isEmpty)
    }

    @Test("An engine without the optional members gets the defaults: no live rate, no-op setRate and prepare")
    func protocolDefaults() {
        let minimal = MinimalSpeechEngine()
        #expect(minimal.supportsLiveRate == false)
        minimal.setRate(SpeechRate(2.0))
        minimal.prepare(upcoming: ["Next."], voice: nil, rate: .default)

        let player = Player(engine: minimal)
        player.load(text)
        player.play()
        player.faster()
        #expect(player.state.rate == SpeechRate(1.25))
    }
}
