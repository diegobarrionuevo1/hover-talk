import Foundation
import HoverTalkCore

/// Keeps one `Player`, one `ControllerPanel` and one `ReadingHighlighter` in sync, and is the
/// single way to start reading text aloud.
///
/// Takes over the player's `onChange` and the controller's `onAction` and
/// `onToggleReadingMode`: every player state change is rendered as a `ControllerPresentation`
/// (with the reading mode from `preferences`) and passed to the highlighter, and every button
/// runs its player operation.
///
/// It also owns the voice and rate settings: each reading detects its text's language, picks the
/// engine (`RemoteRouting.shouldUseRemote`: the voice server when it is available and has a
/// voice for the reading, else the system voice) and gives the player that engine's voice; every
/// rate the player takes is stored as `preferences.speechRate`.
@MainActor
final class ReadingSession {
    /// Called after the rate or the reading mode changed from the controller or the menu, so
    /// the Settings window can show the new values.
    var onSettingsChange: (() -> Void)?
    /// The language `LanguageDetector` found in the latest text read; nil before the first
    /// reading or when the detector could not tell.
    private(set) var lastReadingLanguage: String?
    /// Whether the current reading uses the system voice because the voice server is not
    /// available (decided at its start, or after a failure mid-reading).
    private(set) var isUsingFallbackVoice = false

    private let player: Player
    private let engine: FallbackSpeechEngine
    private let remoteEngine: RemoteSpeechEngine
    private let remoteVoice: RemoteVoiceMonitor
    private let controller: ControllerPanel
    private let preferences: Preferences
    private let voices: SystemVoiceProvider
    private let highlighter = ReadingHighlighter()
    private let languageDetector = LanguageDetector()
    /// Identifies the latest `read` call, so a reading that waited for the voice server does not
    /// start after a newer one.
    private var readingToken = UUID()

    init(
        systemEngine: any SpeechEngine,
        remoteEngine: RemoteSpeechEngine,
        remoteVoice: RemoteVoiceMonitor,
        controller: ControllerPanel,
        preferences: Preferences,
        voices: SystemVoiceProvider
    ) {
        // The engine needs the session's system voice for a failover, before `self` exists.
        weak var owner: ReadingSession?
        let engine = FallbackSpeechEngine(primary: remoteEngine, fallback: systemEngine) { _ in
            owner?.resolvedSystemVoice()
        }
        self.engine = engine
        self.player = Player(engine: engine, rate: preferences.speechRate)
        self.remoteEngine = remoteEngine
        self.remoteVoice = remoteVoice
        self.controller = controller
        self.preferences = preferences
        self.voices = voices
        owner = self

        engine.onFallbackActivated = { [weak self] _ in
            self?.fallbackActivated()
        }
        controller.onAction = { [weak player] action in
            player?.perform(action)
        }
        controller.onToggleReadingMode = { [weak self] in
            self?.toggleReadingMode()
        }
        player.onChange = { [weak self] state in
            self?.renderController(state)
            self?.highlighter.update(state)
            self?.storeRate(state.rate)
        }
        renderController(player.state)
    }

    /// Switches between continuous and paragraph reading. Only later picks read with the new
    /// mode: a document being read was already read from the screen and goes on unchanged.
    func toggleReadingMode() {
        setReadingMode(preferences.readingMode.toggled)
    }

    func setReadingMode(_ mode: ReadingMode) {
        guard mode != preferences.readingMode else { return }
        preferences.readingMode = mode
        renderController(player.state)
        onSettingsChange?()
    }

    /// Stores the system voice selection. While the system voice reads, the player takes the
    /// voice it resolves to for the text being read, and the current sentence starts again with
    /// it (`PlaybackQueue.setVoice(_:)`); while the voice server reads, it is used after a failover.
    func setVoiceSelection(_ selection: VoiceSelection) {
        preferences.voiceSelection = selection
        if !engine.isUsingPrimary {
            player.setVoice(resolvedSystemVoice())
        }
    }

    /// The system voice `selection` resolves to for the latest reading's language, with the
    /// current voice list; what the Settings window previews.
    func voice(for selection: VoiceSelection) -> VoiceDescriptor? {
        voices.catalog().resolve(selection, textLanguage: lastReadingLanguage)
    }

    /// Stores the voice server settings and applies them: the monitor probes a new address, and
    /// a reading on the voice server takes them from its next sentence. The remote engine gets
    /// the new client (none when the server was turned off, so that sentence fails over to the
    /// system voice), and the player the server voice the new settings resolve to, if any, which
    /// restarts the current sentence when the voice changed.
    func setRemoteVoiceServer(_ config: RemoteVoiceServerConfig) {
        preferences.remoteVoiceServer = config
        remoteVoice.update(config: config)
        remoteEngine.client = remoteVoice.activeClient
        if engine.isUsingPrimary, let voice = resolvedRemoteVoice() {
            player.setVoice(voice)
        }
    }

    /// The player's rate; storing it happens in the player's `onChange`.
    var rate: SpeechRate { player.state.rate }

    func setRate(_ rate: SpeechRate) {
        player.setRate(rate)
    }

    func pause() {
        player.pause()
    }

    /// Replaces whatever is being read with `text`, without any on-screen highlight, and reads
    /// it from its first sentence. The controller appears once playback starts; text without
    /// sentences plays nothing (`PlaybackQueue.play()` needs at least one) and leaves the
    /// controller hidden.
    func read(_ text: String) {
        highlighter.end()
        begin(text: text, highlight: nil)
    }

    /// As `read(_:)` with `document.text`, while the highlighter marks the document on the
    /// screen `screenSource` reads. The player splits `document.text` into `document.sentences`
    /// (both use `SentenceSplitter`), so its sentence index is the document's.
    func read(document: ReadingDocument, screenSource: ReadingScreenSource) {
        begin(text: document.text, highlight: (document, screenSource))
    }

    /// While the picker shows its own highlight, the reading marks hide; they come back after.
    func setPicking(_ picking: Bool) {
        highlighter.setSuspended(picking)
    }

    // MARK: - Starting a reading

    /// Starts at once, unless the voice server is set up and its state is not known yet: then
    /// the current reading stops and this one waits for the server's answer, at most
    /// `RemoteVoiceMonitor.readingCheckTimeout`, before it starts with whichever voice applies.
    private func begin(text: String, highlight: (ReadingDocument, ReadingScreenSource)?) {
        let token = UUID()
        readingToken = token
        guard remoteVoice.needsCheckBeforeReading else {
            start(text: text, highlight: highlight)
            return
        }
        player.stop()
        highlighter.end()
        Task { [weak self] in
            await self?.remoteVoice.checkBeforeReading()
            guard let self, self.readingToken == token else { return }
            self.start(text: text, highlight: highlight)
        }
    }

    /// Picks the engine before loading, so the engine that read the previous text is stopped by
    /// `beginReading(usePrimary:)`. The voice is set after `load`, while the player is idle, so
    /// `setVoice` only stores it and speaks nothing.
    private func start(text: String, highlight: (ReadingDocument, ReadingScreenSource)?) {
        lastReadingLanguage = languageDetector.language(of: text)
        let config = remoteVoice.config
        let remoteVoiceForReading = resolvedRemoteVoice()
        let useRemote = RemoteRouting.shouldUseRemote(
            config: config,
            availability: remoteVoice.state,
            resolvedRemoteVoice: remoteVoiceForReading
        )
        isUsingFallbackVoice = !useRemote && RemoteRouting.isFallback(config: config, availability: remoteVoice.state)
        remoteEngine.client = remoteVoice.activeClient
        engine.beginReading(usePrimary: useRemote)

        player.load(text)
        player.setVoice(useRemote ? remoteVoiceForReading : resolvedSystemVoice())
        if let highlight {
            highlighter.begin(highlight.0, source: highlight.1)
        }
        player.play()
        // Without sentences play() changes nothing, so no state would end these marks.
        if highlight != nil, player.state.status != .playing {
            highlighter.end()
        }
        renderController(player.state)
    }

    /// The voice server failed mid-reading. The notice shows only while the server is still set
    /// up: a failure caused by turning it off is no outage.
    private func fallbackActivated() {
        remoteVoice.reportPlaybackFailed()
        isUsingFallbackVoice = remoteVoice.activeClient != nil
        renderController(player.state)
    }

    private func resolvedSystemVoice() -> VoiceDescriptor? {
        voice(for: preferences.voiceSelection)
    }

    private func resolvedRemoteVoice() -> VoiceDescriptor? {
        remoteVoice.catalog().resolve(remoteVoice.config.voice, textLanguage: lastReadingLanguage)
    }

    private func storeRate(_ rate: SpeechRate) {
        guard rate != preferences.speechRate else { return }
        preferences.speechRate = rate
        onSettingsChange?()
    }

    private func renderController(_ state: Player.State) {
        controller.render(ControllerPresentation(
            state: state,
            readingMode: preferences.readingMode,
            usingFallbackVoice: isUsingFallbackVoice
        ))
    }
}
