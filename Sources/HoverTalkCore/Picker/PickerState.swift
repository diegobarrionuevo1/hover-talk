import CoreGraphics

/// Text the picker may read: the block under the pointer, or the text a drag selected; where
/// to outline it and what to read. Two targets are the same when both their rect and their
/// text are equal.
public struct HoverTarget: Equatable, Sendable {
    /// In AX coordinates (top-left origin of the primary screen), around all of the target.
    public let rect: CGRect
    /// What the picker outlines, in the same coordinates: the block's `rects` (one per
    /// paragraph, or per row of a selection), or `[rect]` for a target given as a rect and text.
    public let rects: [CGRect]
    /// As read from the screen, before `TextCleaner`.
    public let text: String
    /// The terminal block the target was found as, so a click can read it with an on-screen
    /// highlight; `nil` for a target given as a rect and text.
    public let block: TerminalTextBlock?

    public init(rect: CGRect, text: String) {
        self.rect = rect
        rects = [rect]
        self.text = text
        block = nil
    }

    public init(_ block: TerminalTextBlock) {
        rect = block.rect
        rects = block.rects
        text = block.text
        self.block = block
    }

    /// Compares rect and text only, so a target found again on an unchanged block is the same
    /// target whether or not it carries its block.
    public static func == (lhs: HoverTarget, rhs: HoverTarget) -> Bool {
        lhs.rect == rhs.rect && lhs.text == rhs.text
    }
}

public enum PickerEvent: Equatable, Sendable {
    /// The picker hotkey was pressed.
    case hotkey
    /// The block under the pointer, or `nil` over anything that is not a readable block.
    case hoverChanged(HoverTarget?)
    case click
    /// While a drag goes on (`PickerDrag.moved`): the text selected so far, or `nil` when it
    /// holds nothing readable.
    case selectionChanged(HoverTarget?)
    /// The drag was released (`PickerDrag.released`) with this selection, or `nil` when it
    /// holds nothing readable.
    case selectionEnded(HoverTarget?)
    case escape
    /// Picking cannot go on, such as when input capture failed or Accessibility was revoked.
    case cancel
}

/// What the app must do after a `PickerState` transition, in the order given.
public enum PickerEffect: Equatable, Sendable {
    /// Start consuming clicks, drags and Esc, and tracking the pointer.
    case startCapture
    case stopCapture
    case showOverlay
    case hideOverlay
    /// Outline these rects in AX coordinates, replacing any earlier outline; `[]` clears it.
    case highlight([CGRect])
    /// Read text aloud; already cleaned and never empty.
    case read(String)
    /// Read a terminal block aloud and highlight it while reading: the document holds its
    /// cleaned text (never empty) and the cells of each sentence; the anchor finds the block
    /// again on later screens.
    case readBlock(ReadingDocument, anchor: ReadingAnchor)
}

/// The picker as a pure state machine: `idle`, then `picking` from the hotkey until a click on
/// a block, a drag over readable text, Esc, the hotkey again, or a cancel; `selecting` while a
/// drag goes on. Every transition returns the effects to perform.
public struct PickerState: Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case picking(hover: HoverTarget?)
        /// A drag goes on; `selection` is the readable text selected so far.
        case selecting(selection: HoverTarget?)
    }

    public private(set) var phase: Phase = .idle
    public let cleaner: TextCleaner

    public init(cleaner: TextCleaner = TextCleaner()) {
        self.cleaner = cleaner
    }

    /// While idle only the hotkey does anything. While picking:
    /// - A hover change outlines the new block, or clears the outline. A block whose text
    ///   cleans to nothing counts as no block; so does a selection.
    /// - A click over a block ends picking and reads its cleaned text: as a `ReadingDocument`
    ///   with the block's anchor when the target carries a block read from a screen, otherwise
    ///   as plain text. A click over no block does nothing: the app has consumed it anyway, and
    ///   a missed click (such as on the blank row between two paragraphs) is then retried
    ///   without pressing the hotkey again.
    /// - A selection change starts selecting: the selection's outline replaces the block's.
    /// - Esc, the hotkey and a cancel end picking without reading.
    ///
    /// While selecting, hover changes and clicks do nothing, a selection change moves the
    /// outline, and Esc, the hotkey and a cancel end picking. In both phases a selection end
    /// reads the selection as a click reads a block, or, with nothing readable selected, clears
    /// the outline and goes back to picking.
    public mutating func handle(_ event: PickerEvent) -> [PickerEffect] {
        switch (phase, event) {
        case (.idle, .hotkey):
            phase = .picking(hover: nil)
            return [.startCapture, .showOverlay]
        case (.idle, _):
            return []
        case let (.picking(hover), .hoverChanged(target)):
            let readable = readable(target)
            guard readable != hover else { return [] }
            phase = .picking(hover: readable)
            return [.highlight(readable?.rects ?? [])]
        case let (.picking(hover), .click):
            guard let hover, let read = read(hover) else { return [] }
            return end() + [read]
        case (.selecting, .hoverChanged), (.selecting, .click):
            return []
        case let (.picking, .selectionChanged(target)):
            let readable = readable(target)
            phase = .selecting(selection: readable)
            return [.highlight(readable?.rects ?? [])]
        case let (.selecting(selection), .selectionChanged(target)):
            let readable = readable(target)
            guard readable != selection else { return [] }
            phase = .selecting(selection: readable)
            return [.highlight(readable?.rects ?? [])]
        case let (_, .selectionEnded(target)):
            if let target, let read = read(target) {
                return end() + [read]
            }
            phase = .picking(hover: nil)
            return [.highlight([])]
        case (_, .escape), (_, .hotkey), (_, .cancel):
            return end()
        }
    }

    private mutating func end() -> [PickerEffect] {
        phase = .idle
        return [.stopCapture, .hideOverlay]
    }

    /// `target` when its text cleans to something to speak.
    private func readable(_ target: HoverTarget?) -> HoverTarget? {
        target.flatMap { spokenText(of: $0) == nil ? nil : $0 }
    }

    /// How to read `target`, or `nil` when nothing is left to speak.
    private func read(_ target: HoverTarget) -> PickerEffect? {
        guard let text = spokenText(of: target) else { return nil }
        if let block = target.block, let anchor = block.anchor {
            return .readBlock(ReadingDocument(cleaner.clean(block.mappedText)), anchor: anchor)
        }
        return .read(text)
    }

    /// The target's cleaned text, or `nil` when nothing is left to speak.
    private func spokenText(of target: HoverTarget) -> String? {
        let text = cleaner.clean(target.text)
        return text.isEmpty ? nil : text
    }
}
