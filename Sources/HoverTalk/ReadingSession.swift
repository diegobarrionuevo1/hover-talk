import HoverTalkCore

/// Keeps one `Player`, one `ControllerPanel` and one `ReadingHighlighter` in sync, and is the
/// single way to start reading text aloud.
///
/// Takes over the player's `onChange` and the controller's `onAction` and
/// `onToggleReadingMode`: every player state change is rendered as a `ControllerPresentation`
/// (with the reading mode from `preferences`) and passed to the highlighter, and every button
/// runs its player operation.
///
/// It also owns the voice and rate settings: each reading detects its text's language and
/// gives the player the voice `preferences.voiceSelection` resolves to, and every rate the
/// player takes is stored as `preferences.speechRate`.
@MainActor
final class ReadingSession {
    /// Called after the rate or the reading mode changed from the controller or the menu, so
    /// the Settings window can show the new values.
    var onSettingsChange: (() -> Void)?
    /// The language `LanguageDetector` found in the latest text read; nil before the first
    /// reading or when the detector could not tell.
    private(set) var lastReadingLanguage: String?

    private let player: Player
    private let controller: ControllerPanel
    private let preferences: Preferences
    private let voices: SystemVoiceProvider
    private let highlighter = ReadingHighlighter()
    private let languageDetector = LanguageDetector()

    init(player: Player, controller: ControllerPanel, preferences: Preferences, voices: SystemVoiceProvider) {
        self.player = player
        self.controller = controller
        self.preferences = preferences
        self.voices = voices
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

    /// Stores the selection and gives the player the voice it resolves to for the text being
    /// read; while playing, the current sentence starts again with that voice
    /// (`PlaybackQueue.setVoice(_:)`).
    func setVoiceSelection(_ selection: VoiceSelection) {
        preferences.voiceSelection = selection
        player.setVoice(resolvedVoice())
    }

    /// The voice `selection` resolves to for the latest reading's language, with the current
    /// voice list; what the Settings window previews.
    func voice(for selection: VoiceSelection) -> VoiceDescriptor? {
        voices.catalog().resolve(selection, textLanguage: lastReadingLanguage)
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
        player.load(text)
        prepareVoice(for: text)
        player.play()
    }

    /// As `read(_:)` with `document.text`, while the highlighter marks the document on the
    /// screen `screenSource` reads. The player splits `document.text` into `document.sentences`
    /// (both use `SentenceSplitter`), so its sentence index is the document's.
    func read(document: ReadingDocument, screenSource: ReadingScreenSource) {
        player.load(document.text)
        prepareVoice(for: document.text)
        highlighter.begin(document, source: screenSource)
        player.play()
        // Without sentences play() changes nothing, so no state would end these marks.
        if player.state.status != .playing {
            highlighter.end()
        }
    }

    /// While the picker shows its own highlight, the reading marks hide; they come back after.
    func setPicking(_ picking: Bool) {
        highlighter.setSuspended(picking)
    }

    /// Detects the language once per reading and sets the voice before playback starts; the
    /// player was just loaded, so it is idle and `setVoice` only stores the voice.
    private func prepareVoice(for text: String) {
        lastReadingLanguage = languageDetector.language(of: text)
        player.setVoice(resolvedVoice())
    }

    private func resolvedVoice() -> VoiceDescriptor? {
        voice(for: preferences.voiceSelection)
    }

    private func storeRate(_ rate: SpeechRate) {
        guard rate != preferences.speechRate else { return }
        preferences.speechRate = rate
        onSettingsChange?()
    }

    private func renderController(_ state: Player.State) {
        controller.render(ControllerPresentation(state: state, readingMode: preferences.readingMode))
    }
}
