import CoreGraphics
import Testing
@testable import HoverTalkCore

@Suite("ReadingAnchor")
struct ReadingAnchorTests {
    /// A plain screen of 10 × 20 points per cell at the origin.
    private func parsed(_ lines: [String]) -> ParsedScreen {
        let grid = TerminalGrid(lines: lines)
        return ParsedScreen(
            lines: lines,
            frame: CGRect(x: 0, y: 0, width: CGFloat(max(grid.columns, 1)) * 10, height: CGFloat(lines.count) * 20)
        )
    }

    private let lines = ["alpha one", "", "beta two", "beta more", "", "gamma", "", "delta"]

    /// The anchor of the block on rows 2...3 of `lines`.
    private func betaAnchor() throws -> ReadingAnchor {
        let block = try #require(parsed(lines).block(at: CGPoint(x: 5, y: 50)))
        #expect(block.rows == 2...3)
        return try #require(block.anchor)
    }

    @Test("On the screen it was captured from, the block is where it was")
    func sameScreen() throws {
        #expect(try betaAnchor().rowOffset(in: parsed(lines)) == 0)
    }

    @Test("Text that scrolled up or down is found at its new rows")
    func shifted() throws {
        let anchor = try betaAnchor()
        let up = Array(lines.dropFirst(2)) + ["", ""]
        let down = ["", "", ""] + Array(lines.dropLast(3))

        #expect(anchor.rowOffset(in: parsed(up)) == -2)
        #expect(anchor.rowOffset(in: parsed(down)) == 3)
    }

    @Test("Rows that changed or scrolled out of view lose the anchor")
    func lost() throws {
        let anchor = try betaAnchor()
        var changed = lines
        changed[3] = "beta MORE"

        #expect(anchor.rowOffset(in: parsed(changed)) == nil)
        #expect(anchor.rowOffset(in: parsed(Array(lines.dropFirst(3)))) == nil)
        #expect(anchor.rowOffset(in: parsed([])) == nil)
    }

    @Test("When the rows show up more than once, the nearest place wins, upward first")
    func nearest() throws {
        let anchor = try betaAnchor()
        let twice = ["beta two", "beta more", "", "x", "", "beta two", "beta more", ""]
        let evenly = ["beta two", "beta more", "", "x", "beta two", "beta more", "", ""]

        #expect(anchor.rowOffset(in: parsed(twice)) == -2)
        #expect(anchor.rowOffset(in: parsed(evenly)) == -2)
    }

    // MARK: Fixture

    @Test("vsplit, left pane: the anchor follows a one-row scroll and ignores the sidebar beside the block")
    func vsplitScrollAndSidebar() throws {
        let screen = try FixtureScreen(VSplitPanes.name)
        let block = try #require(screen.block(row: 12, column: 30))
        let anchor = try #require(block.anchor)
        #expect(anchor.paneColumns == VSplitPanes.left)

        // Pane rows 1...50 move up one row; the last row repeats so the divider stays whole.
        let scrolled = [screen.lines[0]] + screen.lines[2...] + [screen.lines[50]]
        #expect(anchor.rowOffset(in: ParsedScreen(lines: scrolled, frame: screen.frame)) == -1)

        // New sidebar text on the block's rows (the sidebar starts at column 103).
        var sidebar = screen.lines
        for row in block.rows {
            sidebar[row] = screen.grid.text(row: row, in: 0...102) + String(repeating: "Z", count: 30)
                + screen.grid.text(row: row, in: 133...272)
        }
        #expect(anchor.rowOffset(in: ParsedScreen(lines: sidebar, frame: screen.frame)) == 0)
    }

    @Test("Claude Code: a continuous block's anchor checks only the rows it read, so a changing tool block between them keeps it")
    func continuousBlockSkipsChrome() throws {
        let screen = try FixtureScreen("synthetic-claude-code")
        let parse = { (lines: [String]) in ParsedScreen(lines: lines, frame: screen.frame) }
        let block = try #require(parse(screen.lines).block(at: screen.center(row: 8, column: 10), mode: .continuous))
        let anchor = try #require(block.anchor)
        #expect(anchor.rows == 8...23)

        var toolChanged = screen.lines
        toolChanged[15] = "  \u{23BF}  Read 31 lines (ctrl+r to expand)"
        #expect(anchor.rowOffset(in: parse(toolChanged)) == 0)

        var answerChanged = screen.lines
        answerChanged[23] = "  changed."
        #expect(anchor.rowOffset(in: parse(answerChanged)) == nil)

        let scrolled = Array(screen.lines.dropFirst(2)) + ["", ""]
        #expect(anchor.rowOffset(in: parse(scrolled)) == -2)
    }

    @Test("A screen without the captured pane loses the anchor")
    func otherLayout() throws {
        let vsplit = try FixtureScreen(VSplitPanes.name)
        let anchor = try #require(vsplit.block(row: 12, column: 30)?.anchor)
        let fish = try FixtureScreen("plain-shell-fish")

        #expect(anchor.rowOffset(in: ParsedScreen(lines: fish.lines, frame: fish.frame)) == nil)
    }
}

@Suite("ReadingAnchor in stacked panes")
struct StackedPaneAnchorTests {
    /// Two tmux panes stacked over the same columns, split by a horizontal divider.
    private let lines = [
        "top shell line one     ",
        "top shell line two     ",
        "───────────────────────",
        "Bottom paragraph here. ",
        "It goes on.            ",
        "                       ",
    ]

    private func screen(_ lines: [String]) -> ParsedScreen {
        ParsedScreen(lines: lines, frame: CGRect(x: 0, y: 0, width: 230, height: CGFloat(lines.count) * 20), profile: PlainTerminalProfile())
    }

    @Test("An anchor read in the lower of two stacked panes is found again in that pane")
    func lowerPane() throws {
        let parsed = screen(lines)
        #expect(parsed.panes.filter { $0.kind == .program }.count == 2)
        let block = try #require(parsed.block(at: CGPoint(x: 15, y: 70)))
        let anchor = try #require(block.anchor)
        #expect(anchor.rowOffset(in: parsed) == 0)
    }

    @Test("It follows the lower pane's text when it scrolls up by a row")
    func lowerPaneScrolls() throws {
        let before = [lines[0], lines[1], lines[2], "                       ",
                      "Bottom paragraph here. ", "It goes on.            ", "                       "]
        let after = [lines[0], lines[1], lines[2], "Bottom paragraph here. ",
                     "It goes on.            ", "                       ", "                       "]
        let anchor = try #require(screen(before).block(at: CGPoint(x: 15, y: 90))?.anchor)
        #expect(anchor.rowOffset(in: screen(before)) == 0)
        #expect(anchor.rowOffset(in: screen(after)) == -1)
    }
}
