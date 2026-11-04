import Foundation
import Testing
@testable import HoverTalkCore

/// A pasteboard in memory. `onCopy` is what the focused app does when it gets Cmd+C.
private final class FakePasteboard: PasteboardAccess {
    var contents: String?
    private(set) var changeCount = 0
    private(set) var restored: [String?] = []

    init(_ contents: String?) { self.contents = contents }

    func save() -> String? { contents }
    func restore(_ saved: String?) {
        contents = saved
        changeCount += 1
        restored.append(saved)
    }
    func text() -> String? { contents }

    func copy(_ text: String) {
        contents = text
        changeCount += 1
    }
}

@Suite("SelectionCopy")
struct SelectionCopyTests {
    private func copied(
        _ pasteboard: FakePasteboard,
        after delay: Int?,
        text: String = "selected words",
        slept: Counter = Counter()
    ) async -> String? {
        await SelectionCopy.copiedText(
            from: pasteboard,
            sendCopy: { if delay == 0 { pasteboard.copy(text) } },
            sleep: { _ in
                slept.count += 1
                if let delay, slept.count == delay { pasteboard.copy(text) }
            }
        )
    }

    final class Counter: @unchecked Sendable { var count = 0 }

    @Test("The copied text is returned and the previous clipboard contents come back")
    func restoresPrevious() async {
        let board = FakePasteboard("my clipboard")

        let text = await copied(board, after: 0)

        #expect(text == "selected words")
        #expect(board.contents == "my clipboard")
        #expect(board.restored == ["my clipboard"])
    }

    @Test("An app that answers Cmd+C a few polls later is waited for")
    func waitsForSlowApp() async {
        let board = FakePasteboard("old")

        let text = await copied(board, after: 3)

        #expect(text == "selected words")
        #expect(board.contents == "old")
    }

    @Test("No selection: the clipboard never changes, nothing is returned, and nothing is restored")
    func nothingSelected() async {
        let board = FakePasteboard("mine")
        let slept = Counter()

        let text = await copied(board, after: nil, slept: slept)

        #expect(text == nil)
        #expect(board.contents == "mine")
        #expect(board.restored.isEmpty)
        #expect(slept.count > 0)
    }

    @Test("A copy of only whitespace gives nothing, and the clipboard still comes back")
    func blankCopy() async {
        let board = FakePasteboard("keep")

        let text = await copied(board, after: 0, text: "  \n ")

        #expect(text == nil)
        #expect(board.contents == "keep")
    }

    @Test("An empty clipboard is restored as empty")
    func emptyClipboardRestored() async {
        let board = FakePasteboard(nil)

        _ = await copied(board, after: 0)

        #expect(board.contents == nil)
    }
}

@Suite("SelectionReader")
struct SelectionReaderTests {
    @Test("A selection from Accessibility is used and the copy fallback is not run")
    func accessibilityFirst() async {
        let ran = SelectionCopyTests.Counter()
        let text = await SelectionReader.read(axSelection: { "from ax" }, copy: { ran.count += 1; return "from copy" })

        #expect(text == "from ax")
        #expect(ran.count == 0)
    }

    @Test("An empty or blank Accessibility selection falls back to the copy")
    func fallsBack() async {
        #expect(await SelectionReader.read(axSelection: { nil }, copy: { "from copy" }) == "from copy")
        #expect(await SelectionReader.read(axSelection: { "" }, copy: { "from copy" }) == "from copy")
        #expect(await SelectionReader.read(axSelection: { " \n" }, copy: { "from copy" }) == "from copy")
        #expect(await SelectionReader.read(axSelection: { nil }, copy: { nil }) == nil)
    }
}
