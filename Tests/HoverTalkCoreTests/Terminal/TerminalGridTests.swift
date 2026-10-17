import Testing
@testable import HoverTalkCore

@Suite("TerminalGrid")
struct TerminalGridTests {
    @Test(
        "Wide and emoji-presentation Characters take two cells; narrow ones, box drawing and private-use glyphs take one",
        arguments: [
            ("a", 1), ("\u{2502}", 1), ("\u{2503}", 1), ("\u{00B7}", 1), ("\u{2713}", 1), ("\u{2714}", 1),
            ("\u{F06A9}", 1),  // Nerd Font private-use glyph, seen in the vsplit fixture
            ("\u{23F3}", 2),  // ⏳, Emoji_Presentation
            ("\u{1F600}", 2),  // 😀
            ("\u{6F22}", 2),  // 漢
            ("\u{AC00}", 2),  // 가
            ("\u{FF21}", 2),  // Ａ fullwidth
        ] as [(Character, Int)]
    )
    func cellWidth(character: Character, width: Int) {
        #expect(TerminalGrid.cellWidth(of: character) == width)
    }

    @Test("Columns is the widest row in cells, not in Characters")
    func columnsCountCells() {
        let grid = TerminalGrid(lines: ["ab", "\u{23F3}cd", ""])

        #expect(grid.rowCount == 3)
        #expect(grid.columns == 4)
    }

    @Test("A wide Character is reported on both of its cells; short rows are padded with spaces")
    func characterAtCell() {
        let grid = TerminalGrid(lines: ["a\u{23F3}b", "x"])

        #expect(grid.character(row: 0, column: 0) == "a")
        #expect(grid.character(row: 0, column: 1) == "\u{23F3}")
        #expect(grid.character(row: 0, column: 2) == "\u{23F3}")
        #expect(grid.character(row: 0, column: 3) == "b")
        #expect(grid.character(row: 1, column: 3) == " ")
        #expect(grid.character(row: 0, column: 4) == nil)
        #expect(grid.character(row: 2, column: 0) == nil)
        #expect(grid.character(row: -1, column: 0) == nil)
    }

    @Test("Row text is cut by cell columns; a wide Character belongs to the range holding its first cell")
    func textInColumnRange() {
        // Cells: a 0, ⏳ 1-2, b 3, │ 4, c 5, d 6.
        let grid = TerminalGrid(lines: ["a\u{23F3}b\u{2502}cd"])

        #expect(grid.text(row: 0, in: 0...3) == "a\u{23F3}b")
        #expect(grid.text(row: 0, in: 5...6) == "cd")
        #expect(grid.text(row: 0, in: 1...1) == "\u{23F3}")
        #expect(grid.text(row: 0, in: 2...3) == "b")
        #expect(grid.text(row: 0, in: 5...99) == "cd")
        #expect(grid.text(row: 1, in: 0...3) == "")
    }

    @Test("Content columns span from the first to the last non-space cell, including a trailing wide cell")
    func contentColumns() {
        let grid = TerminalGrid(lines: ["  ab  ", "  \u{23F3} ", "      ", "ab cd"])

        #expect(grid.contentColumns(row: 0, in: 0...5) == 2...3)
        #expect(grid.contentColumns(row: 1, in: 0...5) == 2...3)
        #expect(grid.contentColumns(row: 2, in: 0...5) == nil)
        #expect(grid.contentColumns(row: 3, in: 3...4) == 3...4)
        #expect(grid.contentColumns(row: 3, in: 2...2) == nil)
    }

    @Test("Every row of the Ghostty vsplit fixture is 273 cells wide, including the row with ⏳")
    func vsplitFixtureIsRectangular() throws {
        let fixture = try ScreenFixture.load("ghostty-tmux-vsplit-opencode")
        let grid = TerminalGrid(lines: fixture.lines)

        #expect(grid.rowCount == 51)
        #expect(grid.columns == 273)
        #expect(fixture.lines.map { $0.reduce(0) { $0 + TerminalGrid.cellWidth(of: $1) } }.allSatisfy { $0 == 273 })
        #expect(grid.character(row: 34, column: 149) == "\u{23F3}")
        #expect(grid.character(row: 34, column: 143) == "\u{2502}")
    }
}
