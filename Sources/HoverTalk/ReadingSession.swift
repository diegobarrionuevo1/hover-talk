import HoverTalkCore

/// Keeps one `Player`, one `ControllerPanel` and one `ReadingHighlighter` in sync, and is the
/// single way to start reading text aloud.
///
/// Takes over the player's `onChange` and the controller's `onAction`: every player state
/// change is rendered as a `ControllerPresentation` and passed to the highlighter, and every
/// button runs its player operation.
@MainActor
final class ReadingSession {
    private let player: Player
    private let controller: ControllerPanel
    private let highlighter = ReadingHighlighter()

    init(player: Player, controller: ControllerPanel) {
        self.player = player
        self.controller = controller
        controller.onAction = { [weak player] action in
            player?.perform(action)
        }
        player.onChange = { [weak controller, weak highlighter] state in
            controller?.render(ControllerPresentation(state: state))
            highlighter?.update(state)
        }
        controller.render(ControllerPresentation(state: player.state))
    }

    /// Replaces whatever is being read with `text`, without any on-screen highlight, and reads
    /// it from its first sentence. The controller appears once playback starts; text without
    /// sentences plays nothing (`PlaybackQueue.play()` needs at least one) and leaves the
    /// controller hidden.
    func read(_ text: String) {
        highlighter.end()
        player.load(text)
        player.play()
    }

    /// As `read(_:)` with `document.text`, while the highlighter marks the document on the
    /// screen `screenSource` reads. The player splits `document.text` into `document.sentences`
    /// (both use `SentenceSplitter`), so its sentence index is the document's.
    func read(document: ReadingDocument, screenSource: ReadingScreenSource) {
        player.load(document.text)
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
}
