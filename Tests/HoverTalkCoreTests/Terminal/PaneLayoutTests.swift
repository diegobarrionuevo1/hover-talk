import Testing
@testable import HoverTalkCore

@Suite("PaneLayout")
struct PaneLayoutTests {
    private func panes(_ lines: [String]) -> [Pane] {
        PaneLayout.detect(TerminalGrid(lines: lines))
    }

    @Test("The Ghostty tmux vsplit: the status row on top, then two panes around the divider column")
    func vsplitFixture() throws {
        let grid = TerminalGrid(lines: try ScreenFixture.load("ghostty-tmux-vsplit-opencode").lines)
        let divider = try #require((0..<grid.columns).first { column in
            (1..<grid.rowCount).allSatisfy { grid.character(row: $0, column: column) == "\u{2502}" }
        })

        #expect(divider == 143)
        #expect(PaneLayout.detect(grid) == [
            Pane(rows: 0...0, columns: 0...272),
            Pane(rows: 1...50, columns: 0...142),
            Pane(rows: 1...50, columns: 144...272),
        ])
    }

    @Test("A plain fish screen without dividers is one pane")
    func fishFixture() throws {
        let grid = TerminalGrid(lines: try ScreenFixture.load("plain-shell-fish").lines)

        #expect(PaneLayout.detect(grid) == [Pane(rows: 0...43, columns: 0...103)])
    }

    @Test("A full-width row of ─ splits the screen into top and bottom panes")
    func horizontalSplit() {
        #expect(panes(["aaaa", "aaaa", "────", "bbbb"]) == [
            Pane(rows: 0...1, columns: 0...3),
            Pane(rows: 3...3, columns: 0...3),
        ])
    }

    @Test("A vertical divider with a ├ junction, then a horizontal divider in the right half, gives three panes")
    func threePanes() {
        let lines = [
            "aaa│bbb",
            "aaa│bbb",
            "aaa├───",
            "aaa│ccc",
        ]

        #expect(panes(lines) == [
            Pane(rows: 0...3, columns: 0...2),
            Pane(rows: 0...1, columns: 4...6),
            Pane(rows: 3...3, columns: 4...6),
        ])
    }

    @Test("A full-width divider with a ┴ junction splits first; the top half then splits vertically")
    func junctionInHorizontalDivider() {
        let lines = [
            "aa│bb",
            "aa│bb",
            "──┴──",
            "ccccc",
        ]

        #expect(panes(lines) == [
            Pane(rows: 0...1, columns: 0...1),
            Pane(rows: 0...1, columns: 3...4),
            Pane(rows: 3...3, columns: 0...4),
        ])
    }

    @Test("A status row at the bottom is peeled off as its own pane")
    func statusRowAtBottom() {
        let lines = [
            "aa│bb",
            "aa│bb",
            "[0] status",
        ]

        #expect(panes(lines) == [
            Pane(rows: 0...1, columns: 0...1),
            Pane(rows: 0...1, columns: 3...9),
            Pane(rows: 2...2, columns: 0...9),
        ])
    }

    @Test("A status row is not peeled off when the rest has no divider")
    func noPeelWithoutSplit() {
        #expect(panes(["[0] status", "text", "more"]) == [Pane(rows: 0...2, columns: 0...9)])
    }

    @Test("OpenCode's ┃ message gutter is not a divider")
    func heavyGutterIsNotADivider() {
        #expect(panes(["  ┃ one", "  ┃ two", "  ┃ six"]) == [Pane(rows: 0...2, columns: 0...6)])
    }

    @Test("Rounded box corners are not dividers, so a box border column does not split")
    func roundedCornersAreNotDividers() {
        let lines = [
            "╭──╮",
            "│ab│",
            "│cd│",
            "╰──╯",
        ]

        #expect(panes(lines) == [Pane(rows: 0...3, columns: 0...3)])
    }

    @Test("A single row with a │ is not split: one row is no evidence of a divider")
    func singleRowIsNotSplit() {
        #expect(panes(["ab│cd"]) == [Pane(rows: 0...0, columns: 0...4)])
    }

    @Test("An empty screen has no panes")
    func emptyScreen() {
        #expect(panes([]) == [])
        #expect(panes([""]) == [])
    }
}
