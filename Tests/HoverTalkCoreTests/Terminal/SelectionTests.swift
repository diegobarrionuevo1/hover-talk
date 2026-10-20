import CoreGraphics
import Testing
@testable import HoverTalkCore

@Suite("Drag selection")
struct SelectionTests {
    /// Sidebar text and right-pane text on rows 7...13 of the vsplit, beside the left pane's message.
    private let besideLeftMessage = [
        "Snowfalle", "Meadow lake", "harvest", "10:90", "Claude Wind", "Context",  // left pane's sidebar
        "\u{2503}", "\u{2502}", "Sunlight: fig fern", "Moonbeam: fern", "lavenderby",  // gutters, divider, right pane
    ]

    private func vsplit() throws -> (FixtureScreen, ParsedScreen) {
        let screen = try FixtureScreen(VSplitPanes.name)
        return (screen, ParsedScreen(lines: screen.lines, frame: screen.frame))
    }

    @Test("vsplit: a drag across two paragraphs of the left pane reads both, from the start cell to the end cell, without the sidebar or the right pane")
    func acrossTwoParagraphs() throws {
        let (screen, parsed) = try vsplit()
        // From "otter" on row 9 to the "." of "hillside." on row 12; row 10 is a blank gutter row.
        let result = try #require(parsed.selection(from: screen.center(row: 9, column: 11), to: screen.center(row: 12, column: 30)))

        #expect(result.text == "otter by rain `reed/sunlightdo/fig/sun/orchard/compass.rain.so`.\n"
            + "Go sun fern e cloud fig canyon fig fig woodlandleaf go sparrow e in fig harbor, elm fig rain lantern cedar go hillside.")
        #expect(result.rows == 9...12)
        #expect(result.rects.count == 3)
        #expect(result.rects.first?.minX == screen.x(column: 11))
        for fragment in besideLeftMessage {
            #expect(!result.text.contains(fragment), "contains \(fragment)")
        }
        let document = ReadingDocument(TextCleaner().clean(result.mappedText))
        #expect(document.spans == [
            RowSpan(row: 9, columns: 11...74), RowSpan(row: 11, columns: 5...96), RowSpan(row: 12, columns: 5...30),
        ])
        #expect(result.anchor?.rowOffset(in: parsed) == 0)
    }

    @Test("vsplit: dragging backwards selects the same text as dragging forwards")
    func backwards() throws {
        let (screen, parsed) = try vsplit()
        let start = screen.center(row: 9, column: 11)
        let end = screen.center(row: 12, column: 30)

        #expect(parsed.selection(from: end, to: start) == parsed.selection(from: start, to: end))
    }

    @Test("vsplit: within one row, only the cells from the start to the end are read")
    func partialRow() throws {
        let (screen, parsed) = try vsplit()
        let result = parsed.selection(from: screen.center(row: 11, column: 12), to: screen.center(row: 11, column: 23))

        #expect(result?.text == "fern e cloud")
        #expect(result?.rows == 11...11)
    }

    @Test("vsplit: a drag from the left pane into the right pane is clamped to the left pane")
    func clampedToStartPane() throws {
        let (screen, parsed) = try vsplit()
        let result = try #require(parsed.selection(from: screen.center(row: 7, column: 5), to: screen.center(row: 9, column: 200)))
        let paragraph = try #require(parsed.block(at: screen.center(row: 8, column: 30)))

        #expect(paragraph.rows == 7...9)
        #expect(result.text == paragraph.text)
        #expect(result.anchor?.paneColumns == VSplitPanes.left)
        for fragment in besideLeftMessage {
            #expect(!result.text.contains(fragment), "contains \(fragment)")
        }
        #expect(result.rect.maxX <= screen.x(column: 103))
    }

    @Test("vsplit: a drag that leaves the pane at the top ends on the pane's first row, at the column it left from")
    func clampedAboveThePane() throws {
        let (screen, parsed) = try vsplit()
        // Above the frame, over column 60: clamped to row 1, column 60, right of "Maple at falcon".
        let above = CGPoint(x: screen.center(row: 1, column: 60).x, y: screen.frame.minY - 50)
        let result = parsed.selection(from: screen.center(row: 5, column: 10), to: above)

        #expect(result?.text == "# Moon")
        #expect(result?.rows == 5...5)
    }

    @Test("vsplit: a drag that leaves the pane at the bottom reads down to the pane's last row, chrome excluded")
    func clampedBelowThePane() throws {
        let (screen, parsed) = try vsplit()
        let below = CGPoint(x: screen.center(row: 1, column: 60).x, y: screen.frame.maxY + 50)
        let result = try #require(parsed.selection(from: screen.center(row: 30, column: 5), to: below))

        #expect(result.text == "+ Thistle: 6.2o\n+ Thistle: 8in")
        #expect(result.rows == 30...32)
    }

    @Test(
        "vsplit: a drag that selects nothing readable, or starts off every program pane, gives no selection",
        arguments: [
            ((10, 30), (10, 90)),  // a blank gutter row
            ((34, 10), (38, 40)),  // a running tool block
            ((44, 10), (50, 60)),  // the input box and status line
            ((13, 110), (16, 130)),  // the sidebar, then blank gutter rows
            ((0, 10), (12, 30)),  // the tmux status row
            ((12, 143), (12, 30)),  // the divider
        ]
    )
    func nothingReadable(start: (Int, Int), end: (Int, Int)) throws {
        let (screen, parsed) = try vsplit()

        #expect(parsed.selection(from: screen.center(row: start.0, column: start.1), to: screen.center(row: end.0, column: end.1)) == nil)
    }

    @Test("Claude Code: chrome rows inside the selection are left out; the rows after them start a new line")
    func claudeSkipsChrome() throws {
        let screen = try FixtureScreen("synthetic-claude-code")
        let parsed = ParsedScreen(lines: screen.lines, frame: screen.frame)
        let result = parsed.selection(from: screen.center(row: 11, column: 2), to: screen.center(row: 22, column: 14))

        #expect(result?.text == "The south side is open lawn with a single oak tree. A bench sits under the tree, facing the beds.\nThe notes now")
        #expect(result?.rects.count == 3)
    }
}
