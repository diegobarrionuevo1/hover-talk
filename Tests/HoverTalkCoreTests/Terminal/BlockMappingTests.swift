import CoreGraphics
import Testing
@testable import HoverTalkCore

/// Prefixes every row with text that is not on screen.
private struct InventingTestProfile: TUIProfile {
    func matches(paneLines: [String]) -> Bool { true }

    func role(of row: String) -> LineRole {
        row.allSatisfy(\.isWhitespace) ? .content("") : .content("Note: " + row)
    }
}

@Suite("Terminal block mapped text")
struct BlockMappingTests {
    /// Synthetic screens get a frame of 10 × 20 points per cell at the origin.
    private func block(_ lines: [String], row: Int, column: Int, profile: any TUIProfile = PlainTerminalProfile()) -> TerminalTextBlock? {
        let grid = TerminalGrid(lines: lines)
        let frame = CGRect(x: 0, y: 0, width: CGFloat(grid.columns) * 10, height: CGFloat(grid.rowCount) * 20)
        let point = CGPoint(x: (CGFloat(column) + 0.5) * 10, y: (CGFloat(row) + 0.5) * 20)
        return TerminalGridProvider.block(at: point, frame: frame, lines: lines, profile: profile)
    }

    private func cell(_ row: Int, _ column: Int) -> CellPosition? {
        CellPosition(row: row, column: column)
    }

    @Test("Each Character maps to its cell; a collapsed whitespace run maps to its first cell; joining spaces map to nothing")
    func rowsAndJoins() throws {
        let result = try #require(block(["ab  c", "d"], row: 0, column: 0))

        #expect(result.mappedText.text == "ab c d")
        #expect(result.mappedText.anchors == [cell(0, 0), cell(0, 1), cell(0, 2), cell(0, 4), nil, cell(1, 0)])
    }

    @Test("A list item starts a new line that maps to nothing")
    func listJoin() throws {
        let result = try #require(block(["Intro", "- item"], row: 0, column: 0))

        #expect(result.mappedText.text == "Intro\n- item")
        #expect(result.mappedText.anchors[5] == nil)
        #expect(result.mappedText.anchors[6] == cell(1, 0))
    }

    @Test("A wide Character maps to its first cell, and the next Character to the cell after both")
    func wideCharacter() throws {
        let result = try #require(block(["  \u{23F3} wait", "", "abcdefghij"], row: 0, column: 3))

        #expect(result.mappedText.text == "\u{23F3} wait")
        #expect(result.mappedText.anchors == [cell(0, 2), cell(0, 4), cell(0, 5), cell(0, 6), cell(0, 7), cell(0, 8)])
    }

    @Test("A row whose profile text is not the text of its cells is read without anchors")
    func inventedText() throws {
        let result = try #require(block(["one", "two"], row: 0, column: 0, profile: InventingTestProfile()))

        #expect(result.text == "Note: one Note: two")
        #expect(result.mappedText.anchors.allSatisfy { $0 == nil })
    }

    @Test("A block records the rows, columns and pane it was read from")
    func anchor() throws {
        let screen = try FixtureScreen(VSplitPanes.name)
        let result = try #require(screen.block(row: 13, column: 180))
        let anchor = try #require(result.anchor)

        #expect(anchor.rows == result.rows)
        #expect(anchor.columns == result.columns)
        #expect(anchor.paneColumns == VSplitPanes.right)
    }

    @Test(
        "Fixture blocks: every anchored Character, before and after cleaning, is the Character in its cell",
        arguments: [
            (VSplitPanes.name, 12, 30), (VSplitPanes.name, 13, 180),
            ("synthetic-claude-code", 8, 10), ("synthetic-claude-code", 12, 10), ("synthetic-claude-code", 22, 4),
            ("synthetic-claude-code", 6, 10), ("plain-shell-fish", 11, 5),
        ]
    )
    func anchorsPointAtTheirCells(name: String, row: Int, column: Int) throws {
        let screen = try FixtureScreen(name)
        let result = try #require(screen.block(row: row, column: column))
        let cleaned = TextCleaner().clean(result.mappedText)

        #expect(result.mappedText.text == result.text)
        #expect(result.mappedText.anchors.count == result.text.count)
        #expect(cleaned.text == TextCleaner().clean(result.text))
        for mapped in [result.mappedText, cleaned] {
            let anchored = mapped.elements.filter { !$0.0.isWhitespace }
            #expect(!anchored.isEmpty)
            for (character, anchor) in anchored {
                let position = try #require(anchor)
                #expect(result.rows.contains(position.row))
                #expect(screen.grid.character(row: position.row, column: position.column) == character)
            }
        }
    }
}
