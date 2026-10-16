/// A button of the floating controller.
public enum ControllerAction: CaseIterable, Equatable, Sendable {
    case previous
    case playPause
    case next
    case slower
    case faster
    case stop
}

extension Player {
    /// Runs the player operation behind a controller button.
    public func perform(_ action: ControllerAction) {
        switch action {
        case .previous: previous()
        case .playPause: togglePause()
        case .next: next()
        case .slower: slower()
        case .faster: faster()
        case .stop: stop()
        }
    }
}
