import Foundation
import Testing
@testable import HoverTalkCore

private let dora = RemoteVoiceCatalog.descriptor(forVoiceID: "ef_dora")
private let paulina = VoiceDescriptor(id: "com.apple.voice.compact.es-MX.Paulina", name: "Paulina", language: "es-MX", quality: .default)
private let text = "Primera frase. Segunda frase. Tercera frase."

/// A remote-like primary (live rate) and a system-like fallback, composed by the engine under
/// test. The fallback voice resolver gives Paulina for Spanish voices and nil otherwise.
@MainActor
private final class Rig {
    let primary = FakeSpeechEngine()
    let fallback = FakeSpeechEngine()
    let engine: FallbackSpeechEngine
    private(set) var forwarded: [SpeechEngineEvent] = []
    private(set) var activations: [String] = []

    init() {
        primary.supportsLiveRate = true
        engine = FallbackSpeechEngine(primary: primary, fallback: fallback) { voice in
            voice?.language.hasPrefix("es") == true ? paulina : nil
        }
        engine.onEvent = { [unowned self] in forwarded.append($0) }
        engine.onFallbackActivated = { [unowned self] in activations.append($0) }
    }

    /// Begins a reading on the primary and forgets the setup calls (the switch from the initial
    /// fallback route stops the fallback; `switchingStopsOldEngine` covers that).
    func beginPrimaryReading() {
        engine.beginReading(usePrimary: true)
        primary.clearCalls()
        fallback.clearCalls()
    }
}

@MainActor
@Suite("FallbackSpeechEngine routing")
struct FallbackSpeechEngineRoutingTests {
    private let rig = Rig()

    @Test("Before any reading begins, speech goes to the fallback, so nothing reaches the voice server by accident")
    func defaultsToFallback() {
        let id = UUID()
        rig.engine.speak("Hola.", rate: .default, voice: paulina, utteranceID: id)

        #expect(rig.primary.calls.isEmpty)
        #expect(rig.fallback.calls == [.speak(text: "Hola.", rate: .default, voice: paulina, utteranceID: id)])
        #expect(rig.engine.isUsingPrimary == false)
    }

    @Test("A reading on the primary sends every command and hint to it, with the voice unchanged")
    func primaryReading() {
        rig.beginPrimaryReading()
        let id = UUID()

        rig.engine.speak("Hola.", rate: .default, voice: dora, utteranceID: id)
        rig.engine.prepare(upcoming: ["Chau."], voice: dora, rate: .default)
        rig.engine.pause()
        rig.engine.setRate(SpeechRate(1.5))
        rig.engine.resume()
        rig.engine.stop()

        #expect(rig.primary.calls == [
            .speak(text: "Hola.", rate: .default, voice: dora, utteranceID: id),
            .pause, .setRate(SpeechRate(1.5)), .resume, .stop,
        ])
        #expect(rig.primary.preparations == [FakeSpeechEngine.Preparation(upcoming: ["Chau."], voice: dora, rate: .default)])
        #expect(rig.fallback.calls.isEmpty)
        #expect(rig.engine.isUsingPrimary)
        #expect(rig.engine.supportsLiveRate)
    }

    @Test("On the fallback a remote voice is replaced by the resolved system voice; a system voice passes through")
    func fallbackReadingMapsRemoteVoices() {
        rig.engine.beginReading(usePrimary: false)
        let remoteID = UUID()
        let systemID = UUID()

        rig.engine.speak("Hola.", rate: .default, voice: dora, utteranceID: remoteID)
        rig.engine.speak("Hola.", rate: .default, voice: paulina, utteranceID: systemID)
        let unresolvedID = UUID()
        rig.engine.speak("Hello.", rate: .default, voice: RemoteVoiceCatalog.descriptor(forVoiceID: "af_heart"), utteranceID: unresolvedID)
        rig.engine.prepare(upcoming: ["Chau."], voice: dora, rate: .default)

        #expect(rig.fallback.calls == [
            .speak(text: "Hola.", rate: .default, voice: paulina, utteranceID: remoteID),
            .speak(text: "Hola.", rate: .default, voice: paulina, utteranceID: systemID),
            .speak(text: "Hello.", rate: .default, voice: nil, utteranceID: unresolvedID),
        ])
        #expect(rig.fallback.preparations == [FakeSpeechEngine.Preparation(upcoming: ["Chau."], voice: paulina, rate: .default)])
        #expect(rig.engine.supportsLiveRate == false)
    }

    @Test("Events of the active engine are forwarded unchanged; those of the other engine are dropped")
    func forwardsActiveEvents() {
        rig.beginPrimaryReading()
        let id = UUID()
        rig.engine.speak("Hola.", rate: .default, voice: dora, utteranceID: id)

        rig.primary.emit(.started, for: id)
        rig.fallback.emit(.finished, for: id)
        rig.primary.emit(.progress(characterOffset: 2), for: id)

        #expect(rig.forwarded == [
            SpeechEngineEvent(utteranceID: id, kind: .started),
            SpeechEngineEvent(utteranceID: id, kind: .progress(characterOffset: 2)),
        ])
    }

    @Test("Beginning a reading on the other engine stops the one that was active")
    func switchingStopsOldEngine() {
        rig.engine.beginReading(usePrimary: true)
        rig.engine.beginReading(usePrimary: true)
        #expect(rig.fallback.calls == [.stop])
        #expect(rig.primary.calls.isEmpty)

        rig.engine.beginReading(usePrimary: false)
        #expect(rig.primary.calls == [.stop])
    }
}

@MainActor
@Suite("FallbackSpeechEngine failures")
struct FallbackSpeechEngineFailureTests {
    private let rig = Rig()

    @Test("A primary failure restarts the current utterance on the fallback with the same ID and signals once")
    func failover() {
        rig.beginPrimaryReading()
        let id = UUID()
        rig.engine.speak("Primera frase.", rate: SpeechRate(1.25), voice: dora, utteranceID: id)

        rig.primary.emit(.failed(reason: "connection refused"), for: id)

        #expect(rig.primary.calls.last == .stop)
        #expect(rig.fallback.calls == [.speak(text: "Primera frase.", rate: SpeechRate(1.25), voice: paulina, utteranceID: id)])
        #expect(rig.activations == ["connection refused"])
        #expect(rig.forwarded.isEmpty)
        #expect(rig.engine.isUsingPrimary == false)
        #expect(rig.engine.supportsLiveRate == false)
    }

    @Test("After a failover the rest of the reading stays on the fallback, and later primary failures are ignored")
    func staysOnFallback() {
        rig.beginPrimaryReading()
        let first = UUID()
        rig.engine.speak("Primera frase.", rate: .default, voice: dora, utteranceID: first)
        rig.primary.emit(.failed(reason: "timeout"), for: first)

        let second = UUID()
        rig.engine.speak("Segunda frase.", rate: .default, voice: dora, utteranceID: second)
        rig.primary.emit(.failed(reason: "timeout"), for: second)
        rig.primary.emit(.failed(reason: "timeout"), for: first)

        #expect(rig.fallback.calls.last == .speak(text: "Segunda frase.", rate: .default, voice: paulina, utteranceID: second))
        #expect(rig.primary.calls.filter { if case .speak = $0 { true } else { false } }.count == 1)
        #expect(rig.activations == ["timeout"])
    }

    @Test("Late finished, cancelled and failed events from the primary after a failover never reach the player")
    func staleEventRace() {
        rig.beginPrimaryReading()
        let id = UUID()
        rig.engine.speak("Primera frase.", rate: .default, voice: dora, utteranceID: id)
        rig.primary.emit(.failed(reason: "timeout"), for: id)

        rig.primary.emit(.cancelled, for: id)
        rig.primary.emit(.finished, for: id)
        rig.primary.emit(.failed(reason: "late"), for: id)
        rig.fallback.emit(.started, for: id)

        #expect(rig.forwarded == [SpeechEngineEvent(utteranceID: id, kind: .started)])
        #expect(rig.activations == ["timeout"])
    }

    @Test("A primary failure for an utterance that is no longer current is ignored")
    func staleFailure() {
        rig.beginPrimaryReading()
        let old = UUID()
        rig.engine.speak("Primera frase.", rate: .default, voice: dora, utteranceID: old)
        rig.engine.stop()

        rig.primary.emit(.failed(reason: "timeout"), for: old)
        let finished = UUID()
        rig.engine.speak("Segunda frase.", rate: .default, voice: dora, utteranceID: finished)
        rig.primary.emit(.finished, for: finished)
        rig.primary.emit(.failed(reason: "timeout"), for: finished)

        #expect(rig.activations.isEmpty)
        #expect(rig.fallback.calls.isEmpty)
        #expect(rig.engine.isUsingPrimary)
    }

    @Test("A failure while paused switches engines but waits for resume to restart the utterance")
    func failureWhilePaused() {
        rig.beginPrimaryReading()
        let id = UUID()
        rig.engine.speak("Primera frase.", rate: .default, voice: dora, utteranceID: id)
        rig.engine.pause()

        rig.primary.emit(.failed(reason: "timeout"), for: id)
        #expect(rig.activations == ["timeout"])
        #expect(rig.fallback.calls.isEmpty)

        rig.engine.setRate(SpeechRate(1.5))
        rig.engine.resume()
        #expect(rig.fallback.calls == [.setRate(SpeechRate(1.5)), .speak(text: "Primera frase.", rate: SpeechRate(1.5), voice: paulina, utteranceID: id)])

        rig.engine.resume()
        #expect(rig.fallback.calls.last == .resume)
    }

    @Test("A stop after a failure while paused drops the pending restart")
    func stopDropsPendingRestart() {
        rig.beginPrimaryReading()
        let id = UUID()
        rig.engine.speak("Primera frase.", rate: .default, voice: dora, utteranceID: id)
        rig.engine.pause()
        rig.primary.emit(.failed(reason: "timeout"), for: id)

        rig.engine.stop()
        rig.engine.resume()

        #expect(rig.fallback.calls == [.stop, .resume])
    }

    @Test("A live rate change on the primary is kept for the restart on the fallback")
    func liveRateCarriedOver() {
        rig.beginPrimaryReading()
        let id = UUID()
        rig.engine.speak("Primera frase.", rate: .default, voice: dora, utteranceID: id)
        rig.engine.setRate(SpeechRate(1.75))

        rig.primary.emit(.failed(reason: "timeout"), for: id)

        #expect(rig.fallback.calls == [.speak(text: "Primera frase.", rate: SpeechRate(1.75), voice: paulina, utteranceID: id)])
    }

    @Test("The next reading goes back to the primary and can fail over again")
    func nextReadingUsesPrimary() {
        rig.beginPrimaryReading()
        let first = UUID()
        rig.engine.speak("Primera frase.", rate: .default, voice: dora, utteranceID: first)
        rig.primary.emit(.failed(reason: "timeout"), for: first)

        rig.engine.beginReading(usePrimary: true)
        #expect(rig.fallback.calls.last == .stop)
        let second = UUID()
        rig.engine.speak("Otra lectura.", rate: .default, voice: dora, utteranceID: second)
        #expect(rig.primary.calls.last == .speak(text: "Otra lectura.", rate: .default, voice: dora, utteranceID: second))

        rig.primary.emit(.failed(reason: "refused"), for: second)
        #expect(rig.activations == ["timeout", "refused"])
    }

    @Test("A failure on the fallback engine itself is forwarded to the player")
    func fallbackFailureForwarded() {
        rig.engine.beginReading(usePrimary: false)
        let id = UUID()
        rig.engine.speak("Hola.", rate: .default, voice: paulina, utteranceID: id)

        rig.fallback.emit(.failed(reason: "no voice"), for: id)

        #expect(rig.forwarded == [SpeechEngineEvent(utteranceID: id, kind: .failed(reason: "no voice"))])
        #expect(rig.activations.isEmpty)
    }
}

@MainActor
@Suite("FallbackSpeechEngine with Player")
struct FallbackSpeechEnginePlayerTests {
    private let rig = Rig()

    @Test("A failover mid-reading keeps the player on the same sentence; the primary's late cancel does not pause it")
    func playerSurvivesFailover() throws {
        let player = Player(engine: rig.engine, voice: dora)
        rig.beginPrimaryReading()
        player.load(text)
        player.play()
        let id = try #require(rig.primary.lastSpokenID)

        rig.primary.emit(.failed(reason: "timeout"), for: id)
        rig.primary.emit(.cancelled, for: id)

        #expect(player.state.status == .playing)
        #expect(player.state.currentIndex == 0)
        #expect(rig.fallback.lastSpokenID == id)

        rig.fallback.emit(.finished, for: id)
        #expect(player.state.currentIndex == 1)
        #expect(rig.fallback.spokenTexts == ["Primera frase.", "Segunda frase."])
        #expect(rig.fallback.calls.last == .speak(text: "Segunda frase.", rate: .default, voice: paulina, utteranceID: try #require(rig.fallback.lastSpokenID)))
    }

    @Test("After a failover a rate change re-speaks on the fallback instead of a live setRate")
    func rateAfterFailover() throws {
        let player = Player(engine: rig.engine, voice: dora)
        rig.beginPrimaryReading()
        player.load(text)
        player.play()
        player.faster()
        #expect(rig.primary.calls.last == .setRate(SpeechRate(1.25)))

        rig.primary.emit(.failed(reason: "timeout"), for: rig.primary.lastSpokenID)
        rig.fallback.clearCalls()
        player.faster()

        let id = try #require(rig.fallback.lastSpokenID)
        #expect(rig.fallback.calls == [.stop, .speak(text: "Primera frase.", rate: SpeechRate(1.5), voice: paulina, utteranceID: id)])
    }
}
