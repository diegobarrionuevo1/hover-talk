import CoreGraphics
import Testing
@testable import HoverTalkCore

@Suite("PickerState")
struct PickerStateTests {
    private let paragraph = HoverTarget(rect: CGRect(x: 10, y: 20, width: 300, height: 40), text: "A **bold** `word` here.")
    private let other = HoverTarget(rect: CGRect(x: 10, y: 80, width: 300, height: 20), text: "Another paragraph.")

    /// A state that is picking, with `hover` under the pointer.
    private func picking(hover: HoverTarget? = nil) -> PickerState {
        var state = PickerState()
        _ = state.handle(.hotkey)
        if let hover { _ = state.handle(.hoverChanged(hover)) }
        return state
    }

    // MARK: Starting

    @Test("A new picker is idle")
    func startsIdle() {
        #expect(PickerState().phase == .idle)
    }

    @Test("The hotkey starts picking with nothing under the pointer: capture starts, then the overlay shows")
    func hotkeyStartsPicking() {
        var state = PickerState()

        #expect(state.handle(.hotkey) == [.startCapture, .showOverlay])
        #expect(state.phase == .picking(hover: nil))
    }

    @Test("While idle, clicks, Esc, hover changes, selections and cancels do nothing", arguments: [
        PickerEvent.click, .escape, .cancel, .hoverChanged(HoverTarget(rect: .zero, text: "Text.")),
        .selectionChanged(HoverTarget(rect: .zero, text: "Text.")), .selectionEnded(HoverTarget(rect: .zero, text: "Text.")),
    ])
    func idleIgnoresEverythingButTheHotkey(event: PickerEvent) {
        var state = PickerState()

        #expect(state.handle(event) == [])
        #expect(state.phase == .idle)
    }

    // MARK: Hovering

    @Test("Moving over a block highlights its rect")
    func hoverHighlights() {
        var state = picking()

        #expect(state.handle(.hoverChanged(paragraph)) == [.highlight([paragraph.rect])])
        #expect(state.phase == .picking(hover: paragraph))
    }

    @Test("Moving to another block moves the highlight; moving off every block clears it")
    func hoverMovesAndClears() {
        var state = picking(hover: paragraph)

        #expect(state.handle(.hoverChanged(other)) == [.highlight([other.rect])])
        #expect(state.handle(.hoverChanged(nil)) == [.highlight([])])
        #expect(state.phase == .picking(hover: nil))
    }

    @Test("Staying over the same block, or over no block, updates nothing")
    func sameHoverIsQuiet() {
        var state = picking(hover: paragraph)
        #expect(state.handle(.hoverChanged(paragraph)) == [])

        var empty = picking()
        #expect(empty.handle(.hoverChanged(nil)) == [])
    }

    @Test("A block with nothing left to speak after cleaning counts as no block")
    func unspeakableBlockIsNoTarget() {
        var state = picking(hover: paragraph)
        let border = HoverTarget(rect: CGRect(x: 0, y: 0, width: 50, height: 10), text: "\u{2500}\u{2500}\u{2500} \u{2580}\u{2580}")

        #expect(state.handle(.hoverChanged(border)) == [.highlight([])])
        #expect(state.phase == .picking(hover: nil))
    }

    // MARK: Ending

    @Test("A click over a block ends picking and reads the block's cleaned text")
    func clickReadsCleanedText() {
        var state = picking(hover: paragraph)

        #expect(state.handle(.click) == [.stopCapture, .hideOverlay, .read("A bold word here.")])
        #expect(state.phase == .idle)
    }

    @Test("Reading uses the picker's cleaner settings")
    func clickUsesCleaner() {
        var state = PickerState(cleaner: TextCleaner(codeBlocks: .keep))
        _ = state.handle(.hotkey)
        _ = state.handle(.hoverChanged(HoverTarget(rect: .zero, text: "Run:\n```\nmake test\n```")))

        #expect(state.handle(.click).last == .read("Run:\nmake test"))
    }

    @Test("A click over no block keeps picking and reads nothing")
    func clickWithoutTargetKeepsPicking() {
        var state = picking()

        #expect(state.handle(.click) == [])
        #expect(state.phase == .picking(hover: nil))
    }

    @Test("Esc, the hotkey again, or a cancel end picking without reading", arguments: [
        PickerEvent.escape, .hotkey, .cancel,
    ])
    func endWithoutReading(event: PickerEvent) {
        var state = picking(hover: paragraph)

        #expect(state.handle(event) == [.stopCapture, .hideOverlay])
        #expect(state.phase == .idle)
    }

    @Test("Picking again starts without the previous block")
    func newSessionForgetsHover() {
        var state = picking(hover: paragraph)
        _ = state.handle(.escape)
        _ = state.handle(.hotkey)

        #expect(state.phase == .picking(hover: nil))
        #expect(state.handle(.click) == [])
    }

    @Test("A hover target from a terminal block keeps its rect and raw text")
    func targetFromBlock() {
        let block = TerminalTextBlock(text: "Raw **text**.", rows: 2...3, columns: 0...9, rect: CGRect(x: 1, y: 2, width: 3, height: 4))

        #expect(HoverTarget(block) == HoverTarget(rect: block.rect, text: block.text))
    }

    @Test("A click over a block read from a screen reads it as a document with its anchor, so it can be highlighted")
    func clickReadsBlockDocument() throws {
        let block = try #require(try FixtureScreen("synthetic-claude-code").block(row: 22, column: 4))
        let anchor = try #require(block.anchor)
        var state = picking(hover: HoverTarget(block))

        let effects = state.handle(.click)

        let document = ReadingDocument(TextCleaner().clean(block.mappedText)) { block.paragraph(ofRow: $0.row) }
        #expect(effects == [.stopCapture, .hideOverlay, .readBlock(document, anchor: anchor)])
        #expect(document.text == "The notes now list the three beds. The lawn section is unchanged.")
        #expect(document.anchors.paragraphEnds == [1])
        #expect(!document.spans.isEmpty)
        #expect(state.phase == .idle)
    }

    @Test("A block given only as text and rect is read as plain text")
    func clickReadsUnanchoredBlockAsText() {
        let block = TerminalTextBlock(text: "Raw **text**.", rows: 2...3, columns: 0...9, rect: CGRect(x: 1, y: 2, width: 3, height: 4))
        var state = picking(hover: HoverTarget(block))

        #expect(state.handle(.click).last == .read("Raw text."))
    }

    @Test("A block of several paragraphs outlines only the pointed one")
    func hoverOutlinesPointedParagraph() throws {
        let screen = try FixtureScreen("synthetic-claude-code")
        let block = try #require(ParsedScreen(lines: screen.lines, frame: screen.frame)
            .block(at: screen.center(row: 8, column: 10), mode: .continuous))
        var state = picking()

        #expect(block.rects.count == 1)
        #expect(state.handle(.hoverChanged(HoverTarget(block))) == [.highlight(block.rects)])
    }

    // MARK: Drag selection

    /// The vsplit selection from row 9 to row 12 of the left pane.
    private func selection() throws -> TerminalTextBlock {
        let screen = try FixtureScreen(VSplitPanes.name)
        return try #require(ParsedScreen(lines: screen.lines, frame: screen.frame)
            .selection(from: screen.center(row: 9, column: 11), to: screen.center(row: 12, column: 30)))
    }

    @Test("A drag outlines the selection's rows in place of the block under the pointer, and ignores hover changes")
    func dragOutlinesSelection() throws {
        let selection = try HoverTarget(selection())
        var state = picking(hover: paragraph)

        #expect(state.handle(.selectionChanged(selection)) == [.highlight(selection.rects)])
        #expect(state.phase == .selecting(selection: selection))
        #expect(state.handle(.hoverChanged(other)) == [])
        #expect(state.handle(.click) == [])
        #expect(state.handle(.selectionChanged(selection)) == [])
        #expect(state.handle(.selectionChanged(nil)) == [.highlight([])])
        #expect(state.phase == .selecting(selection: nil))
    }

    @Test("Releasing a drag reads exactly the selection, as a document with its anchor")
    func releaseReadsSelection() throws {
        let block = try selection()
        let anchor = try #require(block.anchor)
        var state = picking(hover: paragraph)
        _ = state.handle(.selectionChanged(HoverTarget(block)))

        let effects = state.handle(.selectionEnded(HoverTarget(block)))

        #expect(effects == [.stopCapture, .hideOverlay, .readBlock(ReadingDocument(TextCleaner().clean(block.mappedText)), anchor: anchor)])
        #expect(state.phase == .idle)
    }

    @Test("A drag released before any live selection arrived still reads its selection")
    func releaseWithoutLiveSelection() {
        var state = picking()

        #expect(state.handle(.selectionEnded(paragraph)) == [.stopCapture, .hideOverlay, .read("A bold word here.")])
    }

    @Test("A drag that selects nothing readable keeps picking, with nothing outlined", arguments: [
        nil, HoverTarget(rect: .zero, text: "\u{2500}\u{2500} \u{2503}"),
    ])
    func emptySelectionKeepsPicking(target: HoverTarget?) {
        var state = picking(hover: paragraph)
        _ = state.handle(.selectionChanged(target))

        #expect(state.handle(.selectionEnded(target)) == [.highlight([])])
        #expect(state.phase == .picking(hover: nil))
        #expect(state.handle(.hoverChanged(other)) == [.highlight([other.rect])])
    }

    @Test("Esc, the hotkey or a cancel during a drag end picking without reading", arguments: [
        PickerEvent.escape, .hotkey, .cancel,
    ])
    func endDuringDrag(event: PickerEvent) {
        var state = picking()
        _ = state.handle(.selectionChanged(paragraph))

        #expect(state.handle(event) == [.stopCapture, .hideOverlay])
        #expect(state.phase == .idle)
    }
}
