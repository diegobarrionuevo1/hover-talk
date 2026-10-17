import Testing
@testable import HoverTalkCore

/// Against `synthetic-claude-code.json`, which is hand-written, not captured (see `Fixtures/README.md`).
@Suite("ClaudeCodeProfile")
struct ClaudeCodeProfileTests {
    private let profile = ClaudeCodeProfile()

    @Test("The synthetic Claude Code screen matches; OpenCode panes, fish and a box without Claude marks do not")
    func detection() throws {
        let vsplit = try FixtureScreen(VSplitPanes.name)

        #expect(profile.matches(paneLines: try ScreenFixture.load("synthetic-claude-code").lines))
        #expect(!profile.matches(paneLines: vsplit.paneLines(rows: VSplitPanes.rows, columns: VSplitPanes.left)))
        #expect(!profile.matches(paneLines: vsplit.paneLines(rows: VSplitPanes.rows, columns: VSplitPanes.right)))
        #expect(!profile.matches(paneLines: try ScreenFixture.load("plain-shell-fish").lines))
        #expect(!profile.matches(paneLines: ["\u{256D}\u{2500}\u{256E}", "\u{2502}a\u{2502}", "\u{2570}\u{2500}\u{256F}"]))
        #expect(!profile.matches(paneLines: ["\u{23FA} text", "  ? for shortcuts"]))
        #expect(profile.matches(paneLines: ["\u{256D}\u{2500}\u{256E}", "\u{2570}\u{2500}\u{256F}", "  ? for shortcuts"]))
    }

    @Test("Welcome box, input box, hint row, thinking row, tool calls and their ⎿ results are chrome; messages are not")
    func roles() throws {
        let roles = profile.roles(ofPane: try ScreenFixture.load("synthetic-claude-code").lines)

        #expect(roles.count == 31)
        for row in [0, 1, 2, 3, 4, 14, 15, 17, 18, 19, 20, 25, 27, 28, 29, 30] {
            #expect(roles[row] == .chrome, "row \(row)")
        }
        for row in [6, 8, 9, 11, 12, 22, 23] {
            #expect(roles[row] != .chrome, "row \(row)")
        }
    }

    @Test("The ⏺ marker and the > prompt mark are left out of the content and its cells")
    func markers() {
        #expect(profile.role(of: "\u{23FA} The garden") == .content("The garden", columns: 2...11))
        #expect(profile.role(of: "> Describe it") == .content("Describe it", columns: 2...12))
        #expect(profile.role(of: "  holds herbs") == .content("  holds herbs", columns: 0...12))
    }

    @Test("A tool call is ⏺ and a capitalised name directly followed by (; other ⏺ rows are text")
    func toolCallShape() {
        #expect(profile.role(of: "\u{23FA} Bash(swift test)") == .chrome)
        #expect(profile.role(of: "\u{23FA} WebFetch(url)") == .chrome)
        #expect(profile.role(of: "  \u{23BF}  Read 24 lines") == .chrome)
        #expect(profile.role(of: "\u{23FA} Done (all three)") != .chrome)
        #expect(profile.role(of: "\u{23FA} lowercase(x) is text") != .chrome)
    }

    @Test("Rows under a tool call stay chrome up to a blank row or the next ⏺ or > row")
    func toolBlockEnds() {
        let lines = [
            "\u{23FA} Bash(swift test",
            "      --parallel)",
            "  \u{23BF}  Build complete",
            "     All tests passed",
            "\u{23FA} It passed.",
            "\u{23FA} Read(a.md)",
            "",
            "  after a blank row",
        ]
        let roles = profile.roles(ofPane: lines)

        // Content text has trailing spaces trimmed; its cells run to the pane's last column (20).
        #expect(roles[0...3].allSatisfy { $0 == .chrome })
        #expect(roles[4] == .content("It passed.", columns: 2...20))
        #expect(roles[5] == .chrome)
        #expect(roles[7] == .content("  after a blank row", columns: 0...20))
    }
}
