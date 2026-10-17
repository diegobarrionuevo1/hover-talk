import CoreGraphics
import Testing
@testable import HoverTalkCore

/// Marks rows starting with `==` as chrome and strips a leading `┃` gutter from the rest.
private struct GutterTestProfile: TUIProfile {
    func matches(paneLines: [String]) -> Bool { true }

    func role(of row: String) -> LineRole {
        let trimmed = row.drop { $0 == " " }
        if trimmed.hasPrefix("==") { return .chrome }
        return .content(String(trimmed.hasPrefix("┃") ? trimmed.dropFirst() : trimmed))
    }
}

@Suite("TerminalGridProvider")
struct TerminalGridProviderTests {
    /// Synthetic screens get a frame of 10 × 20 points per cell at the origin.
    private func block(
        _ lines: [String],
        row: Int,
        column: Int,
        profile: any TUIProfile = PlainTerminalProfile()
    ) -> TerminalTextBlock? {
        let grid = TerminalGrid(lines: lines)
        let frame = CGRect(x: 0, y: 0, width: CGFloat(grid.columns) * 10, height: CGFloat(grid.rowCount) * 20)
        let point = CGPoint(x: (CGFloat(column) + 0.5) * 10, y: (CGFloat(row) + 0.5) * 20)
        return TerminalGridProvider.block(at: point, frame: frame, lines: lines, profile: profile)
    }

    // MARK: Paragraphs and joining

    @Test("A paragraph is the run of non-blank rows around the pointed row; wrapped rows join with one space")
    func paragraphBoundedByBlankRows() {
        let lines = ["first block", "", "  second   block", "wraps    here  ", "", "third"]
        let result = block(lines, row: 3, column: 1)

        #expect(result?.text == "second block wraps here")
        #expect(result?.rows == 2...3)
        #expect(result?.columns == 0...15)
        #expect(result?.rect == CGRect(x: 0, y: 40, width: 160, height: 40))
    }

    @Test("Rows starting with a list marker join with a newline; other rows join with a space")
    func listMarkersStartNewLines() {
        let lines = [
            "Intro text that",
            "wraps here.",
            "- first item",
            "  continues",
            "* second",
            "1. third",
            "  12) fourth",
            "a) fifth",
            "\u{2022} sixth",
        ]

        #expect(block(lines, row: 0, column: 0)?.text
            == "Intro text that wraps here.\n- first item continues\n* second\n1. third\n12) fourth\na) fifth\n\u{2022} sixth")
    }

    @Test("Flags, decimals, bold text and words with a parenthesis are not list markers")
    func notListMarkers() {
        let lines = ["run it with", "-v for details", "rose by", "1.5 percent", "**bold** too", "ab) not one", "1234. nor this"]

        #expect(block(lines, row: 0, column: 0)?.text
            == "run it with -v for details rose by 1.5 percent **bold** too ab) not one 1234. nor this")
    }

    @Test("Pointing at a blank row, or outside the frame, gives no block")
    func blankRowOrOutside() {
        let lines = ["text", "", "more"]
        let frame = CGRect(x: 0, y: 0, width: 40, height: 60)

        #expect(block(lines, row: 1, column: 0) == nil)
        #expect(block(lines, row: 0, column: 3)?.rows == 0...0)
        #expect(TerminalGridProvider.block(at: CGPoint(x: 41, y: 5), frame: frame, lines: lines) == nil)
    }

    @Test("A wide glyph takes two cells in the block's columns and rect")
    func wideGlyphColumns() {
        // Cells: two spaces, ⏳ 2-3, space 4, "wait" 5-8; the grid is 10 columns wide.
        let lines = ["  \u{23F3} wait", "", "abcdefghij"]
        let onContinuationCell = block(lines, row: 0, column: 3)

        #expect(onContinuationCell?.text == "\u{23F3} wait")
        #expect(onContinuationCell?.columns == 2...8)
        #expect(onContinuationCell?.rect == CGRect(x: 20, y: 0, width: 70, height: 20))
        #expect(block(lines, row: 0, column: 8)?.columns == 2...8)
    }

    @Test("Pointing at the empty cells after a row's text still selects that row's paragraph")
    func trailingCellsBelongToTheRow() {
        let lines = ["short", "longer row"]

        #expect(block(lines, row: 0, column: 8)?.rows == 0...1)
    }

    // MARK: Profile hook

    @Test("The plain profile keeps every row as content, trimming trailing whitespace only, and matches any pane")
    func plainProfile() {
        let profile = PlainTerminalProfile()

        #expect(profile.role(of: "  text  \t") == .content("  text"))
        #expect(profile.role(of: "   ") == .content(""))
        #expect(profile.role(of: "\u{2503} \u{2500}\u{2500}") == .content("\u{2503} \u{2500}\u{2500}"))
        #expect(profile.matches(paneLines: []))
        #expect(profile.matches(paneLines: ["anything"]))
    }

    @Test("A profile's chrome rows end a paragraph and give no block; its cleaned content is what is joined")
    func profileChromeAndContent() {
        let lines = ["  ┃ one", "  ┃ two", "== footer ==", "  ┃ three"]
        let profile = GutterTestProfile()

        #expect(block(lines, row: 0, column: 4, profile: profile)?.text == "one two")
        #expect(block(lines, row: 0, column: 4, profile: profile)?.rows == 0...1)
        #expect(block(lines, row: 2, column: 4, profile: profile) == nil)
        #expect(block(lines, row: 3, column: 4, profile: profile)?.text == "three")
    }

    // MARK: Fixtures

    private struct VSplit {
        let fixture: ScreenFixture
        let frame: CGRect
        let cellWidth: CGFloat
        let cellHeight: CGFloat

        init() throws {
            fixture = try ScreenFixture.load("ghostty-tmux-vsplit-opencode")
            frame = try #require(fixture.frame)
            cellWidth = frame.width / 273
            cellHeight = frame.height / 51
        }

        func block(row: Int, column: Int) -> TerminalTextBlock? {
            let point = CGPoint(
                x: frame.minX + (CGFloat(column) + 0.5) * cellWidth,
                y: frame.minY + (CGFloat(row) + 0.5) * cellHeight
            )
            return TerminalGridProvider.block(at: point, frame: frame, lines: fixture.lines)
        }
    }

    @Test("vsplit, left pane: a tool block stays inside the left pane")
    func vsplitLeftPane() throws {
        let screen = try VSplit()
        let result = try #require(screen.block(row: 36, column: 20))

        #expect(result.rows == 34...38)
        #expect(result.columns == 5...96)
        #expect(result.text.hasPrefix("\u{2834} Harbor-On-Garden-Wind-Glacier Wind \u{2014} Meadow IN 2 E90 a8 \u{21B3} Bash island"))
        #expect(result.text.hasSuffix("in2-rain.elm | rain"))
        #expect(!result.text.contains("\u{2502}"))
        // Right-pane words on the same rows (34 and 37).
        #expect(!result.text.contains("Mountaindo"))
        #expect(!result.text.contains("MoonbeaMlavendErmap"))
        #expect(result.rect.minX >= screen.frame.minX)
        #expect(result.rect.maxX <= screen.frame.minX + 143 * screen.cellWidth)
    }

    @Test("vsplit, right pane: a tool block stays inside the right pane")
    func vsplitRightPane() throws {
        let screen = try VSplit()
        let result = try #require(screen.block(row: 37, column: 200))

        #expect(result.rows == 36...38)
        #expect(result.columns == 149...228)
        #expect(result.text.hasPrefix("\u{2838} Harbor-On-Garden-Wind-Glacier Wind \u{2014} O1e thistle moss oak"))
        #expect(!result.text.contains("\u{2502}"))
        // Left-pane words on the same rows (35 and 37).
        #expect(!result.text.contains("BIRD="))
        #expect(!result.text.contains("Cedar|Maple"))
        #expect(result.rect.minX >= screen.frame.minX + 144 * screen.cellWidth)
        #expect(result.rect.maxX <= screen.frame.maxX)
    }

    @Test("vsplit, right pane: the row with ⏳ maps its second cell to the same one-row block")
    func vsplitWideGlyphRow() throws {
        let result = try #require(try VSplit().block(row: 34, column: 150))

        #expect(result.rows == 34...34)
        #expect(result.columns == 149...214)
        #expect(result.text.hasPrefix("\u{23F3} Mountaindo O1e"))
    }

    @Test("vsplit: the divider column, a blank row and the far edge give no block")
    func vsplitNoBlock() throws {
        let screen = try VSplit()

        #expect(screen.block(row: 20, column: 143) == nil)
        #expect(screen.block(row: 39, column: 20) == nil)
        #expect(screen.block(row: 20, column: 273) == nil)
    }

    @Test("vsplit: the tmux status row is its own pane and never joins the pane below")
    func vsplitStatusRow() throws {
        let screen = try VSplit()

        #expect(screen.block(row: 0, column: 10)?.rows == 0...0)
        #expect(screen.block(row: 1, column: 10)?.rows.lowerBound == 1)
    }

    @Test("Plain fish screen with a synthetic frame: pointing at command output reads that block")
    func fishOutputBlock() throws {
        let fixture = try ScreenFixture.load("plain-shell-fish")
        let frame = CGRect(x: 0, y: 0, width: 1040, height: 880)  // 104 columns × 44 rows of 10 × 20
        let result = try #require(TerminalGridProvider.block(at: CGPoint(x: 55, y: 230), frame: frame, lines: fixture.lines))

        #expect(result.rows == 11...12)
        #expect(result.columns == 2...53)
        #expect(result.text == "Blossom Mountaino harbor Hillside opencode -u fig_otter98u2cloUd2Lavender2dO")
        #expect(result.rect == CGRect(x: 20, y: 220, width: 520, height: 40))
    }
}
