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

    @Test("While idle, clicks, Esc, hover changes and cancels do nothing", arguments: [
        PickerEvent.click, .escape, .cancel, .hoverChanged(HoverTarget(rect: .zero, text: "Text.")),
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

        #expect(state.handle(.hoverChanged(paragraph)) == [.highlight(paragraph.rect)])
        #expect(state.phase == .picking(hover: paragraph))
    }

    @Test("Moving to another block moves the highlight; moving off every block clears it")
    func hoverMovesAndClears() {
        var state = picking(hover: paragraph)

        #expect(state.handle(.hoverChanged(other)) == [.highlight(other.rect)])
        #expect(state.handle(.hoverChanged(nil)) == [.highlight(nil)])
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

        #expect(state.handle(.hoverChanged(border)) == [.highlight(nil)])
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
}
