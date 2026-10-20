import AVFoundation
import HoverTalkCore

/// `SpeechEngine` that reads with the user's voice server: `RemoteVoiceClient` synthesizes each
/// sentence at normal speed, and `AVAudioEngine` plays it through an `AVAudioUnitTimePitch`, so
/// rate changes apply while playing (`supportsLiveRate`).
///
/// - `speak` reuses a synthesis that `prepare(upcoming:voice:rate:)` started; `prepare` keeps
///   only the current sentence and the next `SynthesisPrefetch.upcomingLimit` ones.
/// - Every failure, including a missing client or a voice that is not `.remote`, becomes
///   `.failed(reason:)`; nothing is retried here (`FallbackSpeechEngine` switches voices).
/// - It sends no `.progress` events: the server reports no word positions.
/// - Events are posted to the main queue in the order they are raised, never from inside a call.
@MainActor
final class RemoteSpeechEngine: SpeechEngine {
    var onEvent: ((SpeechEngineEvent) -> Void)?
    var supportsLiveRate: Bool { true }

    /// The server that reads; nil makes every `speak` fail. A different server drops every
    /// synthesis except the current sentence's, which finishes with the previous server: its text
    /// was already sent, and cancelling it would fail over and blame the new server.
    var client: RemoteVoiceClient? {
        didSet {
            if oldValue?.address != client?.address {
                dropSyntheses(except: current?.key)
            }
        }
    }

    private struct Utterance {
        let id: UUID
        let key: SynthesisKey
    }

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    /// The format of the player → time-pitch → mixer connections; nil until first connected.
    private var connectedFormat: AVAudioFormat?
    private var syntheses: [SynthesisKey: Task<DecodedAudio, any Error>] = [:]
    /// The utterance `speak` was last asked for, until it finishes, fails or is cancelled.
    private var current: Utterance?
    /// `current`'s audio once scheduled, kept to schedule it again after an audio device change.
    private var currentBuffer: AVAudioPCMBuffer?
    private var isPaused = false
    /// Increases whenever scheduled audio is flushed, so a completion handler of earlier audio
    /// (which `AVAudioPlayerNode.stop()` also calls) is ignored.
    private var scheduleGeneration = 0
    /// Increases with every `scheduleIdleCheck()`, so only the latest check acts.
    private var idleCheckGeneration = 0
    /// Kept for the app's lifetime; the block holds the engine weakly.
    private var configurationObserver: (any NSObjectProtocol)?

    init() {
        audioEngine.attach(playerNode)
        audioEngine.attach(timePitch)
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: nil
        ) { [weak self] _ in
            // AVFoundation posts this on an internal thread. `queue: nil` plus an asynchronous hop
            // never blocks that thread on the main queue, which avoids the poster/main deadlock
            // seen with `availableVoicesDidChangeNotification` (see SystemVoiceProvider).
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.audioConfigurationChanged()
                }
            }
        }
    }

    func speak(_ text: String, rate: SpeechRate, voice: VoiceDescriptor?, utteranceID: UUID) {
        cancelCurrent()
        isPaused = false
        timePitch.rate = Float(rate.multiplier)
        guard let client else {
            post(.failed(reason: "No voice server is set up."), for: utteranceID)
            return
        }
        guard let voiceID = Self.serverVoiceID(voice) else {
            post(.failed(reason: "No voice server voice was chosen."), for: utteranceID)
            return
        }
        let key = SynthesisKey(text: text, voice: voiceID)
        let synthesis = syntheses[key] ?? startSynthesis(key, client: client)
        syntheses[key] = synthesis
        current = Utterance(id: utteranceID, key: key)
        // Inherits the main actor. Cancelling `synthesis` (a dropped cache entry) ends this wait
        // with a failure; a result for an utterance that is no longer current is ignored.
        Task { [weak self] in
            let result = await synthesis.result
            self?.synthesisFinished(result, for: utteranceID)
        }
    }

    func pause() {
        isPaused = true
        if audioEngine.isRunning {
            playerNode.pause()
        }
    }

    func resume() {
        isPaused = false
        guard currentBuffer != nil else { return }
        do {
            try startEngineIfNeeded()
            playerNode.play()
        } catch {
            failCurrent(reason: "Audio playback could not start.")
        }
    }

    /// Cancels the current utterance (posting `.cancelled` for it) and silences the player.
    /// Every synthesis is cancelled too once `scheduleIdleCheck()` finds nothing speaking, so a
    /// skip (`.stop` then `.speak`) keeps the prefetched sentences.
    func stop() {
        cancelCurrent()
        scheduleIdleCheck()
    }

    func setRate(_ rate: SpeechRate) {
        timePitch.rate = Float(rate.multiplier)
    }

    func prepare(upcoming: [String], voice: VoiceDescriptor?, rate: SpeechRate) {
        guard let client, let voiceID = Self.serverVoiceID(voice) else { return }
        let plan = SynthesisPrefetch.plan(
            cached: Set(syntheses.keys),
            current: current?.key,
            upcoming: upcoming.map { SynthesisKey(text: $0, voice: voiceID) }
        )
        for key in plan.drop {
            syntheses.removeValue(forKey: key)?.cancel()
        }
        for key in plan.start {
            syntheses[key] = startSynthesis(key, client: client)
        }
    }

    // MARK: - Synthesis

    private static func serverVoiceID(_ voice: VoiceDescriptor?) -> String? {
        guard let voice, voice.source == .remote else { return nil }
        return voice.id
    }

    /// The task inherits the main actor, but `synthesize` is nonisolated, so the request and the
    /// WAV decoding run off the main thread.
    private func startSynthesis(_ key: SynthesisKey, client: RemoteVoiceClient) -> Task<DecodedAudio, any Error> {
        Task {
            try await client.synthesize(text: key.text, voice: key.voice)
        }
    }

    private func dropSyntheses(except kept: SynthesisKey? = nil) {
        for (key, synthesis) in syntheses where key != kept {
            synthesis.cancel()
            syntheses[key] = nil
        }
    }

    private func synthesisFinished(_ result: Result<DecodedAudio, any Error>, for id: UUID) {
        guard let current, current.id == id else { return }
        switch result {
        case .success(let audio):
            do {
                try play(audio, for: id)
            } catch {
                failCurrent(reason: "Audio playback could not start.")
            }
        case .failure(let error):
            // A failed synthesis is never reused for a later `speak`.
            syntheses[current.key] = nil
            failCurrent(reason: (error as? RemoteVoiceError)?.reason ?? "The voice server request failed.")
        }
    }

    // MARK: - Playback

    private struct PlaybackError: Error {}

    private func play(_ audio: DecodedAudio, for id: UUID) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(audio.sampleRate), channels: AVAudioChannelCount(audio.channels)),
              let buffer = Self.buffer(for: audio, format: format)
        else { throw PlaybackError() }
        connect(format)
        try schedule(buffer, for: id)
        currentBuffer = buffer
        post(.started, for: id)
    }

    /// Connects player → time-pitch → main mixer in `format`, unless already connected in a
    /// format with the same sample rate and channel count. The mixer converts to the output.
    private func connect(_ format: AVAudioFormat) {
        if let connectedFormat, connectedFormat.sampleRate == format.sampleRate, connectedFormat.channelCount == format.channelCount {
            return
        }
        flushPlayer()
        audioEngine.stop()
        audioEngine.connect(playerNode, to: timePitch, format: format)
        audioEngine.connect(timePitch, to: audioEngine.mainMixerNode, format: format)
        connectedFormat = format
    }

    private func startEngineIfNeeded() throws {
        guard !audioEngine.isRunning else { return }
        audioEngine.prepare()
        try audioEngine.start()
    }

    /// Replaces whatever the player holds with `buffer`, and plays it unless paused. Starts the
    /// engine first, because `AVAudioPlayerNode.play()` needs a running engine.
    private func schedule(_ buffer: AVAudioPCMBuffer, for id: UUID) throws {
        try startEngineIfNeeded()
        flushPlayer()
        let generation = scheduleGeneration
        // `@Sendable`: AVFoundation calls the handler on its own thread, so it must not be
        // inferred as main-actor isolated.
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { @Sendable [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.playedBack(id, generation: generation)
                }
            }
        }
        if !isPaused {
            playerNode.play()
        }
    }

    /// Stops the player, dropping its scheduled audio. The player is only touched once connected
    /// (defensive: before that it never held audio).
    private func flushPlayer() {
        scheduleGeneration += 1
        if connectedFormat != nil {
            playerNode.stop()
        }
    }

    private func playedBack(_ id: UUID, generation: Int) {
        guard generation == scheduleGeneration, current?.id == id else { return }
        current = nil
        currentBuffer = nil
        post(.finished, for: id)
        scheduleIdleCheck()
    }

    /// Ends the reading's audio work when nothing speaks any more: a main-queue block, queued
    /// after any event just posted, cancels every synthesis and pauses the audio engine unless an
    /// utterance is current by then. `Player` answers an event, and runs a skip's `.stop` and
    /// `.speak`, within one main-actor turn, so a following sentence is current by then.
    private func scheduleIdleCheck() {
        idleCheckGeneration += 1
        let generation = idleCheckGeneration
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.idleCheckGeneration == generation, self.current == nil else { return }
                self.dropSyntheses()
                if self.audioEngine.isRunning {
                    self.audioEngine.pause()
                }
            }
        }
    }

    /// Per the `AVAudioEngineConfigurationChange` documentation, the engine stops itself when the
    /// audio hardware's sample rate or channel count changes, and keeps its nodes connected. The
    /// current sentence then starts again from its beginning; with nothing current, the next
    /// `speak` starts the engine. Not yet tried with a real device change.
    private func audioConfigurationChanged() {
        guard let current, let buffer = currentBuffer else { return }
        do {
            try schedule(buffer, for: current.id)
        } catch {
            failCurrent(reason: "Audio playback stopped after the audio device changed.")
        }
    }

    // MARK: - Events

    private func cancelCurrent() {
        flushPlayer()
        currentBuffer = nil
        if let current {
            self.current = nil
            post(.cancelled, for: current.id)
        }
    }

    private func failCurrent(reason: String) {
        guard let current else { return }
        self.current = nil
        currentBuffer = nil
        flushPlayer()
        post(.failed(reason: reason), for: current.id)
    }

    private func post(_ kind: SpeechEngineEvent.Kind, for id: UUID) {
        let event = SpeechEngineEvent(utteranceID: id, kind: kind)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.onEvent?(event)
            }
        }
    }

    /// `audio`'s interleaved samples copied into a deinterleaved float buffer in `format`.
    private static func buffer(for audio: DecodedAudio, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = audio.frameCount
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channelData = buffer.floatChannelData
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        let channels = audio.channels
        audio.samples.withUnsafeBufferPointer { samples in
            for channel in 0..<channels {
                let destination = channelData[channel]
                for frame in 0..<frames {
                    destination[frame] = samples[frame * channels + channel]
                }
            }
        }
        return buffer
    }
}
