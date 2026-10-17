import CoreGraphics
import Testing
@testable import HoverTalkCore

/// End to end: `TerminalGridProvider` with the standard registry, on whole fixture screens.
@Suite("Reading through TUI profiles")
struct ProfiledReadingTests {
    /// Text that must never be read from the vsplit: tmux status, sidebar, borders, footer,
    /// key hints, input box and status line.
    private let vsplitChrome = [
        "8CuP", "99%",  // tmux status row
        "Context", "tokens", "Seashello", "Snowfalle", "Claude Wind", "10:90", "10:16", "$",  // sidebars
        "\u{2503}", "\u{2502}", "\u{2579}", "\u{2580}", "\u{25A3}", "\u{21B3}", "\u{2B1D}",  // ┃ │ ╹ ▀ ▣ ↳ ⬝
        "esc interrupt", "ctrl+", "OpenCode 6.34.5", "Harbor-Snowfallreed",  // hints, status, input box
    ]

    private func expectNoVsplitChrome(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) {
        for fragment in vsplitChrome {
            #expect(!text.contains(fragment), "contains \(fragment)", sourceLocation: sourceLocation)
        }
    }

    // MARK: OpenCode in a tmux vertical split

    @Test("vsplit, left pane: pointing at a message paragraph reads only that paragraph, without the sidebar beside it")
    func leftParagraph() throws {
        let screen = try FixtureScreen(VSplitPanes.name)
        let result = try #require(screen.block(row: 12, column: 30))

        #expect(result.rows == 11...13)
        #expect(result.columns == 5...96)
        #expect(result.text == "Go sun fern e cloud fig canyon fig fig woodlandleaf go sparrow e in fig harbor, elm fig rain"
            + " lantern cedar go hillside. \u{00BF}Fig sparrow sky oak? Sparrow fig 8 sky oak")
        expectNoVsplitChrome(result.text)
        #expect(result.rect.minX == screen.x(column: 5))
        #expect(abs(result.rect.maxX - screen.x(column: 97)) < 0.001)
        #expect(result.rect.maxX < screen.x(column: 103))
    }

    @Test("vsplit, right pane: pointing at a message reads its rows inside the right pane, cut before the sidebar at 233")
    func rightParagraph() throws {
        let screen = try FixtureScreen(VSplitPanes.name)
        let result = try #require(screen.block(row: 13, column: 180))

        #expect(result.rows == 1...31)
        #expect(result.columns == 151...228)
        #expect(result.text.hasPrefix("reed pearl (5337-61-68, orchard wind-sky-hillsidea sunlight bird e moss river): 48 + - [ ] **O1e**"))
        #expect(result.text.contains("lavenderby moonbeam, harbor fig), cedar \u{2192} (fig, falcon) \u{2192} wind, snowfalle"))
        #expect(result.text.hasSuffix("(brook / orchard / in) so fig WILLOW."))
        expectNoVsplitChrome(result.text)
        #expect(result.rect.minX >= screen.x(column: 144))
        #expect(abs(result.rect.maxX - screen.x(column: 229)) < 0.001)
        #expect(result.rect.maxX < screen.x(column: 233))
    }

    @Test(
        "vsplit: tmux status, sidebar, gutter, running tools, key hints, footer, input box and status line give no block",
        arguments: [
            (0, 10), (0, 250),  // tmux status row
            (12, 110), (17, 105), (14, 105), (16, 105), (13, 235), (14, 235),  // sidebars, also beside message text
            (12, 2),  // the ┃ gutter cell itself
            (36, 20), (34, 150), (37, 160),  // running tool blocks
            (40, 10), (40, 150),  // key-hint rows
            (42, 10), (42, 150),  // ▣ footers
            (45, 10), (47, 10), (47, 110), (46, 150),  // input boxes, with the sidebar's cwd beside them
            (48, 10), (48, 150),  // ╹▀▀▀ borders
            (49, 10), (49, 110), (49, 150), (50, 10),  // status lines and below
        ]
    )
    func vsplitNoBlock(row: Int, column: Int) throws {
        #expect(try FixtureScreen(VSplitPanes.name).block(row: row, column: column) == nil)
    }

    @Test("vsplit: TextCleaner turns a read block into speakable text without markdown marks")
    func cleanedRightParagraph() throws {
        let text = try #require(try FixtureScreen(VSplitPanes.name).block(row: 13, column: 180)).text
        let spoken = TextCleaner().clean(text)

        #expect(!spoken.contains("**"))
        #expect(!spoken.contains("`"))
        #expect(spoken.contains("48 + - [ ] O1e Fig thistle moss"))
    }

    // MARK: Claude Code (synthetic screen)

    @Test("Claude Code: pointing at an assistant paragraph reads it without the ⏺ marker; the highlight starts after it")
    func claudeParagraphs() throws {
        let screen = try FixtureScreen("synthetic-claude-code")
        let first = try #require(screen.block(row: 8, column: 10))
        let second = try #require(screen.block(row: 12, column: 10))

        #expect(first.text == "The garden has three beds along the north wall. Each bed holds herbs, and the paths between them are gravel.")
        #expect(first.rows == 8...9)
        #expect(first.columns == 2...57)
        #expect(first.rect == CGRect(x: 20, y: 160, width: 560, height: 40))
        #expect(second.text == "The south side is open lawn with a single oak tree. A bench sits under the tree, facing the beds.")
        #expect(second.columns == 2...60)
        #expect(screen.block(row: 22, column: 4)?.text == "The notes now list the **three beds**. The lawn section is unchanged.")
    }

    @Test("Claude Code: an echoed user prompt reads without its > mark")
    func claudeUserPrompt() throws {
        let result = try #require(try FixtureScreen("synthetic-claude-code").block(row: 6, column: 10))

        #expect(result.text == "Describe the garden layout in two short paragraphs.")
        #expect(result.columns == 2...52)
    }

    @Test(
        "Claude Code: boxes, tool calls, ⎿ results, the thinking row, the hint row and the ⏺ marker give no block",
        arguments: [
            (1, 5), (3, 10),  // welcome box
            (14, 5), (15, 8), (17, 5), (18, 8), (19, 8), (20, 12),  // tool calls and results
            (25, 5),  // thinking row
            (27, 5), (28, 5), (28, 63), (29, 5),  // input box
            (30, 4),  // hint row
            (8, 0),  // the ⏺ marker cell
        ]
    )
    func claudeNoBlock(row: Int, column: Int) throws {
        #expect(try FixtureScreen("synthetic-claude-code").block(row: row, column: column) == nil)
    }
}
