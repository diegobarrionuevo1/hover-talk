import CoreGraphics

/// The block under the pointer while picking: where to highlight it and what to read.
/// Two targets are the same block when both their rect and their text are equal.
public struct HoverTarget: Equatable, Sendable {
    /// In AX coordinates (top-left origin of the primary screen).
    public let rect: CGRect
    /// As read from the screen, before `TextCleaner`.
    public let text: String

    public init(rect: CGRect, text: String) {
        self.rect = rect
        self.text = text
    }

    public init(_ block: TerminalTextBlock) {
        self.init(rect: block.rect, text: block.text)
    }
}

public enum PickerEvent: Equatable, Sendable {
    /// The picker hotkey was pressed.
    case hotkey
    /// The block under the pointer, or `nil` over anything that is not a readable block.
    case hoverChanged(HoverTarget?)
    case click
    case escape
    /// Picking cannot go on, such as when input capture failed or Accessibility was revoked.
    case cancel
}

/// What the app must do after a `PickerState` transition, in the order given.
public enum PickerEffect: Equatable, Sendable {
    /// Start consuming clicks and Esc, and tracking the pointer.
    case startCapture
    case stopCapture
    case showOverlay
    case hideOverlay
    /// Draw the highlight around a rect in AX coordinates, or clear it for `nil`.
    case highlight(CGRect?)
    /// Read text aloud; already cleaned and never empty.
    case read(String)
}

/// The picker as a pure state machine: `idle`, then `picking` from the hotkey until a click on
/// a block, Esc, the hotkey again, or a cancel. Every transition returns the effects to perform.
public struct PickerState: Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case picking(hover: HoverTarget?)
    }

    public private(set) var phase: Phase = .idle
    public let cleaner: TextCleaner

    public init(cleaner: TextCleaner = TextCleaner()) {
        self.cleaner = cleaner
    }

    /// While idle only the hotkey does anything. While picking:
    /// - A hover change highlights the new block, or clears the highlight. A block whose text
    ///   cleans to nothing counts as no block.
    /// - A click over a block ends picking and reads its cleaned text. A click over no block
    ///   does nothing: the app has consumed it anyway, and a missed click (such as on the
    ///   blank row between two paragraphs) is then retried without pressing the hotkey again.
    /// - Esc, the hotkey and a cancel end picking without reading.
    public mutating func handle(_ event: PickerEvent) -> [PickerEffect] {
        guard case let .picking(hover) = phase else {
            guard event == .hotkey else { return [] }
            phase = .picking(hover: nil)
            return [.startCapture, .showOverlay]
        }
        switch event {
        case let .hoverChanged(target):
            let readable = target.flatMap { spokenText(of: $0) == nil ? nil : $0 }
            guard readable != hover else { return [] }
            phase = .picking(hover: readable)
            return [.highlight(readable?.rect)]
        case .click:
            guard let text = hover.flatMap(spokenText(of:)) else { return [] }
            return end() + [.read(text)]
        case .escape, .hotkey, .cancel:
            return end()
        }
    }

    private mutating func end() -> [PickerEffect] {
        phase = .idle
        return [.stopCapture, .hideOverlay]
    }

    /// The target's cleaned text, or `nil` when nothing is left to speak.
    private func spokenText(of target: HoverTarget) -> String? {
        let text = cleaner.clean(target.text)
        return text.isEmpty ? nil : text
    }
}
