import CoreGraphics
import Testing
@testable import HoverTalkCore

/// Marks rows starting with `==` as chrome; every other row is content.
private struct FooterTestProfile: TUIProfile {
    func matches(paneLines: [String]) -> Bool { true }

    func role(of row: String) -> LineRole {
        row.hasPrefix("==") ? .chrome : .content(row.withoutTrailingWhitespace)
    }
}

@Suite("Continuous reading")
struct ContinuousReadingTests {
    /// Text that continuous reading must never reach in the vsplit's left pane: the tool block,
    /// key hint, `▣` footer, input box and status line below the last message, the sidebar, and
    /// the right pane's message on the same rows.
    private let leftPaneOutside = [
        "Harbor-On-Garden", "Bash island", "ctrl+", "\u{25A3}", "Harbor-Snowfallreed", "esc interrupt",
        "Context", "tokens", "Seashello", "Claude Wind",
        "reed pearl", "Mountaindo", "O1a",
    ]

    /// A screen of 10 × 20 points per cell at the origin, read with `profile`.
    private func parsed(_ lines: [String], profile: any TUIProfile = PlainTerminalProfile()) -> ParsedScreen {
        let grid = TerminalGrid(lines: lines)
        let frame = CGRect(x: 0, y: 0, width: CGFloat(max(grid.columns, 1)) * 10, height: CGFloat(lines.count) * 20)
        return ParsedScreen(lines: lines, frame: frame, profile: profile)
    }

    private func point(row: Int, column: Int) -> CGPoint {
        CGPoint(x: (CGFloat(column) + 0.5) * 10, y: (CGFloat(row) + 0.5) * 20)
    }

    // MARK: Fixtures

    @Test("vsplit, left pane: reads the pointed paragraph and every paragraph below it, down to the last message row")
    func vsplitLeftPane() throws {
        let screen = try FixtureScreen(VSplitPanes.name)
        let parsed = ParsedScreen(lines: screen.lines, frame: screen.frame)
        let result = try #require(parsed.block(at: screen.center(row: 12, column: 30), mode: .continuous))

        // Paragraphs on rows 11-13, 17-24, 26-27, 30 and 32; row 33 down to 50 is blank or chrome.
        let paragraphs = try [12, 20, 26, 30, 32].map { row in
            try #require(parsed.block(at: screen.center(row: row, column: 10)))
        }
        #expect(paragraphs.map(\.rows) == [11...13, 17...24, 26...27, 30...30, 32...32])
        #expect(result.text == paragraphs.map(\.text).joined(separator: "\n"))
        #expect(result.rows == 11...32)
        #expect(result.rects == paragraphs.map(\.rect))
        for fragment in leftPaneOutside {
            #expect(!result.text.contains(fragment), "contains \(fragment)")
        }
        let anchor = try #require(result.anchor)
        #expect(anchor.rows == 11...32)
        #expect(anchor.paneColumns == VSplitPanes.left)
    }

    @Test("vsplit, left pane: the paragraphs above the pointed one are not read; the last paragraph reads alone")
    func vsplitDownOnly() throws {
        let screen = try FixtureScreen(VSplitPanes.name)
        let parsed = ParsedScreen(lines: screen.lines, frame: screen.frame)

        let fromP6 = try #require(parsed.block(at: screen.center(row: 26, column: 10), mode: .continuous))
        #expect(fromP6.rows == 26...32)
        #expect(!fromP6.text.contains("Sparrow fig 8 sky oak"))

        let last = try #require(parsed.block(at: screen.center(row: 32, column: 6), mode: .continuous))
        #expect(last == parsed.block(at: screen.center(row: 32, column: 6)))
    }

    @Test("vsplit, right pane: continuous reading stays inside the right pane and stops above its running tool")
    func vsplitRightPane() throws {
        let screen = try FixtureScreen(VSplitPanes.name)
        let parsed = ParsedScreen(lines: screen.lines, frame: screen.frame)
        let result = try #require(parsed.block(at: screen.center(row: 13, column: 180), mode: .continuous))

        #expect(result == parsed.block(at: screen.center(row: 13, column: 180)))
        #expect(result.rows == 1...31)
    }

    @Test("Claude Code: skips the tool block between two answers and stops before the thinking row and the input box")
    func claudeSkipsToolBlock() throws {
        let screen = try FixtureScreen("synthetic-claude-code")
        let parsed = ParsedScreen(lines: screen.lines, frame: screen.frame)
        let result = try #require(parsed.block(at: screen.center(row: 8, column: 10), mode: .continuous))

        #expect(result.text == """
            The garden has three beds along the north wall. Each bed holds herbs, and the paths between them are gravel.
            The south side is open lawn with a single oak tree. A bench sits under the tree, facing the beds.
            The notes now list the **three beds**. The lawn section is unchanged.
            """)
        #expect(result.rows == 8...23)
        #expect(result.rects.count == 3)
        #expect(!result.text.contains("Thinking"))
        #expect(!result.text.contains("ask about the pond"))
    }

    @Test("Claude Code: the document's spans cover the paragraphs' rows only, and each paragraph ends a sentence")
    func claudeDocument() throws {
        let screen = try FixtureScreen("synthetic-claude-code")
        let parsed = ParsedScreen(lines: screen.lines, frame: screen.frame)
        let block = try #require(parsed.block(at: screen.center(row: 11, column: 10), mode: .continuous))
        let document = ReadingDocument(TextCleaner().clean(block.mappedText))

        #expect(document.sentences == [
            "The south side is open lawn with a single oak tree.",
            "A bench sits under the tree, facing the beds.",
            "The notes now list the three beds.",
            "The lawn section is unchanged.",
        ])
        #expect(document.spans.map(\.row) == [11, 12, 22, 23])
        #expect(document.sentenceSpans.map { $0.map(\.row) } == [[11], [11, 12], [22], [22, 23]])
    }

    // MARK: Stop rule

    @Test("A chrome row between paragraphs is skipped, not a stop; reading goes on to the pane's last content row")
    func chromeRowIsSkipped() {
        let screen = parsed(["one", "two", "== footer ==", "three", "", "", "four", "== status =="], profile: FooterTestProfile())

        let result = screen.block(at: point(row: 0, column: 1), mode: .continuous)
        #expect(result?.text == "one two\nthree\nfour")
        #expect(result?.rows == 0...6)
        #expect(screen.block(at: point(row: 3, column: 1), mode: .continuous)?.text == "three\nfour")
        #expect(screen.block(at: point(row: 2, column: 1), mode: .continuous) == nil)
    }

    @Test("A paragraph without closing punctuation still ends its sentence before the next paragraph")
    func paragraphBreakIsSentenceBoundary() throws {
        let block = try #require(parsed(["First part without a stop", "", "Second part."]).block(at: point(row: 0, column: 0), mode: .continuous))
        let document = ReadingDocument(TextCleaner().clean(block.mappedText))

        #expect(document.sentences == ["First part without a stop", "Second part."])
    }

    @Test("Paragraph mode, the default, reads only the pointed paragraph")
    func paragraphMode() {
        let screen = parsed(["one", "two", "", "three"])

        #expect(screen.block(at: point(row: 0, column: 0), mode: .paragraph)?.text == "one two")
        #expect(screen.block(at: point(row: 0, column: 0)) == screen.block(at: point(row: 0, column: 0), mode: .paragraph))
        #expect(screen.block(at: point(row: 0, column: 0))?.rects == [CGRect(x: 0, y: 0, width: 30, height: 40)])
    }
}
