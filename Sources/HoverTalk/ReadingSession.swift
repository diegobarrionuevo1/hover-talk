import HoverTalkCore

/// Keeps one `Player` and one `ControllerPanel` in sync, and is the single way to start
/// reading text aloud.
///
/// Takes over the player's `onChange` and the controller's `onAction`: every player state
/// change is rendered as a `ControllerPresentation`, and every button runs its player operation.
@MainActor
final class ReadingSession {
    private let player: Player
    private let controller: ControllerPanel

    init(player: Player, controller: ControllerPanel) {
        self.player = player
        self.controller = controller
        controller.onAction = { [weak player] action in
            player?.perform(action)
        }
        player.onChange = { [weak controller] state in
            controller?.render(ControllerPresentation(state: state))
        }
        controller.render(ControllerPresentation(state: player.state))
    }

    /// Replaces whatever is being read with `text` and reads it from its first sentence.
    /// The controller appears once playback starts; text without sentences plays nothing
    /// (`PlaybackQueue.play()` needs at least one) and leaves the controller hidden.
    func read(_ text: String) {
        player.load(text)
        player.play()
    }
}
