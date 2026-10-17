/// An input event captured while picking.
public enum PickerInput: Equatable, Sendable {
    case mouseDown
    case mouseDragged
    case mouseUp
    case escapeDown
    case escapeUp
}

/// Decides which captured input the picker consumes, so it never reaches the app under the
/// pointer, and which input becomes a `PickerEvent`.
///
/// A click and Esc act on their release, not their press: the app stops capturing as soon as
/// picking ends, so acting on the press would let the matching release through to the app
/// under the pointer without its press. Every press is consumed (Esc key repeats included), and
/// so is a release or drag whose press was consumed. A release whose press happened before
/// capture started belongs to the app that saw the press and passes through.
public struct PickerInputFilter: Sendable {
    public struct Decision: Equatable, Sendable {
        /// Whether to drop the input instead of passing it on.
        public let consume: Bool
        public let event: PickerEvent?

        public init(consume: Bool, event: PickerEvent?) {
            self.consume = consume
            self.event = event
        }
    }

    private var mousePressed = false
    private var escapePressed = false

    public init() {}

    public mutating func handle(_ input: PickerInput) -> Decision {
        switch input {
        case .mouseDown:
            mousePressed = true
            return Decision(consume: true, event: nil)
        case .mouseDragged:
            return Decision(consume: mousePressed, event: nil)
        case .mouseUp:
            defer { mousePressed = false }
            return mousePressed ? Decision(consume: true, event: .click) : Decision(consume: false, event: nil)
        case .escapeDown:
            escapePressed = true
            return Decision(consume: true, event: nil)
        case .escapeUp:
            defer { escapePressed = false }
            return escapePressed ? Decision(consume: true, event: .escape) : Decision(consume: false, event: nil)
        }
    }
}
