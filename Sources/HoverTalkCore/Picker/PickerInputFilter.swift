import CoreGraphics

/// An input event captured while picking. Mouse events carry the pointer's location, all in
/// one coordinate system (the app passes AX coordinates).
public enum PickerInput: Equatable, Sendable {
    case mouseDown(CGPoint)
    case mouseDragged(CGPoint)
    case mouseUp(CGPoint)
    case escapeDown
    case escapeUp
}

/// A press that moved more than `PickerInputFilter.dragThreshold` from where it started.
public enum PickerDrag: Equatable, Sendable {
    /// The button is still down; `to` is the pointer's latest location.
    case moved(from: CGPoint, to: CGPoint)
    /// The button was released at `to`.
    case released(from: CGPoint, to: CGPoint)
}

/// Decides which captured input the picker consumes, so it never reaches the app under the
/// pointer, which input becomes a `PickerEvent`, and whether a press is a click or a drag.
///
/// A click and Esc act on their release, not their press: the app stops capturing as soon as
/// picking ends, so acting on the press would let the matching release through to the app
/// under the pointer without its press. Every press is consumed (Esc key repeats included), and
/// so is a release or drag whose press was consumed. A release whose press happened before
/// capture started belongs to the app that saw the press and passes through.
///
/// A press becomes a drag once the pointer is more than `dragThreshold` away from where it was
/// pressed, by a drag event or at the release, and stays one until the release, even if the
/// pointer comes back. A drag reports `PickerDrag.moved` on every drag event and
/// `.released` instead of a click.
public struct PickerInputFilter: Sendable {
    public struct Decision: Equatable, Sendable {
        /// Whether to drop the input instead of passing it on.
        public let consume: Bool
        public let event: PickerEvent?
        /// The drag the input moved or ended; `nil` for a press that is not a drag (yet).
        public let drag: PickerDrag?

        public init(consume: Bool, event: PickerEvent?, drag: PickerDrag? = nil) {
            self.consume = consume
            self.event = event
            self.drag = drag
        }
    }

    /// How far, in points, a press may move and still be a click.
    public static let dragThreshold: CGFloat = 4

    /// Whether a key press with these modifiers is a system shortcut that must end input
    /// capture: any Command-Shift chord, which covers the screenshot shortcuts (⌘⇧3, ⌘⇧4, ⌘⇧5).
    /// Their crosshair click would otherwise be consumed and read as a pick.
    public static func isSystemShortcut(command: Bool, shift: Bool) -> Bool {
        command && shift
    }

    /// Where the consumed mouse press started; `nil` while the button is up.
    private var pressLocation: CGPoint?
    private var isDragging = false
    private var escapePressed = false

    public init() {}

    public mutating func handle(_ input: PickerInput) -> Decision {
        switch input {
        case let .mouseDown(location):
            pressLocation = location
            isDragging = false
            return Decision(consume: true, event: nil)
        case let .mouseDragged(location):
            guard let start = pressLocation else { return Decision(consume: false, event: nil) }
            isDragging = isDragging || Self.isDrag(from: start, to: location)
            return Decision(consume: true, event: nil, drag: isDragging ? .moved(from: start, to: location) : nil)
        case let .mouseUp(location):
            guard let start = pressLocation else { return Decision(consume: false, event: nil) }
            defer {
                pressLocation = nil
                isDragging = false
            }
            guard isDragging || Self.isDrag(from: start, to: location) else { return Decision(consume: true, event: .click) }
            return Decision(consume: true, event: nil, drag: .released(from: start, to: location))
        case .escapeDown:
            escapePressed = true
            return Decision(consume: true, event: nil)
        case .escapeUp:
            defer { escapePressed = false }
            return escapePressed ? Decision(consume: true, event: .escape) : Decision(consume: false, event: nil)
        }
    }

    /// Whether the straight-line distance is more than `dragThreshold`.
    private static func isDrag(from start: CGPoint, to end: CGPoint) -> Bool {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return (dx * dx + dy * dy).squareRoot() > dragThreshold
    }
}
