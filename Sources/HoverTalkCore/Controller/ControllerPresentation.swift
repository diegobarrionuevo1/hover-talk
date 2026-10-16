import Foundation

/// What the floating controller shows for a `Player.State`.
public struct ControllerPresentation: Equatable, Sendable {
    /// What the play/pause button does when pressed.
    public enum PlayPauseMode: Equatable, Sendable {
        case play
        case pause
        case resume
    }

    public struct Control: Equatable, Sendable {
        public let action: ControllerAction
        /// SF Symbol name for the button image.
        public let symbolName: String
        public let accessibilityLabel: String
        public let isEnabled: Bool
    }

    public static let panelTitle = "\(AppInfo.name) Controls"

    /// Visible while playing or paused. Idle (including after stop) and finished hide it.
    public let isVisible: Bool
    public let playPauseMode: PlayPauseMode
    public let previous: Control
    public let playPause: Control
    public let next: Control
    public let slower: Control
    public let faster: Control
    public let stop: Control
    /// The 1-based current sentence and the sentence count, for example "3 / 12".
    public let progressText: String
    public let progressAccessibilityLabel: String
    /// The rate multiplier, for example "1.25×".
    public let rateText: String
    public let rateAccessibilityLabel: String

    public init(state: Player.State) {
        let isActive = state.status == .playing || state.status == .paused
        let isLoaded = state.count > 0
        isVisible = isActive

        let mode: PlayPauseMode = switch state.status {
        case .playing: .pause
        case .paused: .resume
        case .idle, .finished: .play
        }
        playPauseMode = mode
        let playPauseLabel = switch mode {
        case .play: "Play"
        case .pause: "Pause"
        case .resume: "Resume"
        }
        playPause = Control(
            action: .playPause,
            symbolName: mode == .pause ? "pause.fill" : "play.fill",
            accessibilityLabel: playPauseLabel,
            isEnabled: isLoaded
        )

        // `PlaybackQueue.next()` and `previous()` do nothing unless playing or paused.
        previous = Control(
            action: .previous,
            symbolName: "backward.end.fill",
            accessibilityLabel: "Previous sentence",
            isEnabled: isActive && state.currentIndex > 0
        )
        next = Control(
            action: .next,
            symbolName: "forward.end.fill",
            accessibilityLabel: "Next sentence",
            isEnabled: isActive && state.currentIndex + 1 < state.count
        )

        slower = Control(
            action: .slower,
            symbolName: "minus",
            accessibilityLabel: "Slower",
            isEnabled: state.rate.multiplier > SpeechRate.minimum
        )
        faster = Control(
            action: .faster,
            symbolName: "plus",
            accessibilityLabel: "Faster",
            isEnabled: state.rate.multiplier < SpeechRate.maximum
        )
        stop = Control(action: .stop, symbolName: "stop.fill", accessibilityLabel: "Stop", isEnabled: isActive)

        if isLoaded {
            let number = state.currentIndex + 1
            progressText = "\(number) / \(state.count)"
            progressAccessibilityLabel = "Sentence \(number) of \(state.count)"
        } else {
            progressText = "0 / 0"
            progressAccessibilityLabel = "No text loaded"
        }

        let multiplier = Self.format(state.rate.multiplier)
        rateText = "\(multiplier)×"
        rateAccessibilityLabel = state.rate == .default ? "Normal speed" : "\(multiplier) times normal speed"
    }

    /// Up to two fraction digits, no trailing zeros, and always "." as the decimal separator.
    private static func format(_ multiplier: Double) -> String {
        multiplier.formatted(
            .number
                .precision(.fractionLength(0...2))
                .grouping(.never)
                .locale(Locale(identifier: "en_US_POSIX"))
        )
    }
}
