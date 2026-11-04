import CoreGraphics
import Testing
@testable import HoverTalkCore

/// Against `ghostty-tmux-gentle-shell.json`: three Gentle Shell panes in a tmux split, the two on
/// the right wide enough to show the sidebar. Words in it are sanitized; the layout is real.
@Suite("GentleShellProfile")
struct GentleShellProfileTests {
    private let profile = GentleShellProfile()
    private static let name = "ghostty-tmux-gentle-shell"

    @Test("The three panes of the capture are Gentle Shell; OpenCode panes, Claude Code, fish and plain boxes are not")
    func detection() throws {
        let screen = try FixtureScreen(Self.name)
        let parsed = ParsedScreen(lines: screen.lines, frame: screen.frame)

        #expect(parsed.panes.map(\.kind) == [.tmuxStatus, .program, .program, .program])
        #expect(parsed.panes.compactMap(\.profileName) == Array(repeating: "GentleShellProfile", count: 3))

        let vsplit = try FixtureScreen(VSplitPanes.name)
        #expect(!profile.matches(paneLines: vsplit.paneLines(rows: VSplitPanes.rows, columns: VSplitPanes.left)))
        #expect(!profile.matches(paneLines: try ScreenFixture.load("synthetic-claude-code").lines))
        #expect(!profile.matches(paneLines: try ScreenFixture.load("plain-shell-fish").lines))
        #expect(!profile.matches(paneLines: ["▎ one", "▎ two"]))
        #expect(!profile.matches(paneLines: ["▔▔▔▔▔▔▔▔▔▔"]))
        #expect(profile.matches(paneLines: ["▔▔▔▔▔▔▔▔▔▔", "▎ one", "▎ two"]))
        #expect(profile.matches(paneLines: ["✿ Name  ctx ▰▰▱▱▱▱▱▱ 25%", "▎ one", "▎ two"]))
    }

    @Test("The header, the rule, the todo widget, the editor and the sidebar give no block; messages do")
    func chromeAndMessages() throws {
        let screen = try FixtureScreen(Self.name)

        // Header, rule and a gutter row of the left pane.
        for (row, column) in [(2, 5), (4, 5), (28, 5), (34, 5), (39, 5)] {
            #expect(screen.block(row: row, column: column) == nil, "row \(row)")
        }
        // The right panes' header rows, rule rows and editor rows.
        for (row, column) in [(2, 60), (4, 60), (34, 60), (36, 100), (39, 60)] {
            #expect(screen.block(row: row, column: column) == nil, "row \(row)")
        }
        // The sidebar, on rows that also have message text.
        for (row, column) in [(6, 170), (8, 170), (22, 180), (38, 170)] {
            #expect(screen.block(row: row, column: column) == nil, "row \(row)")
        }

        let message = try #require(screen.block(row: 10, column: 3))
        #expect(message.rows == 9...15)
        #expect(message.columns == 1...43)
    }

    @Test("The text of a wide pane stops before the sidebar column, and the sidebar rows are never read")
    func sidebarCut() throws {
        let screen = try FixtureScreen(Self.name)
        let block = try #require(screen.block(row: 5, column: 60))

        #expect(block.rows == 5...8)
        #expect(block.columns.upperBound < 161)
        // The pointer is inside the message cells, but the same row's sidebar cells are not.
        #expect(screen.block(row: 5, column: 165) == nil)
    }

    @Test("The sidebar column is found in the right half only, from at least three gutter rows after a gap")
    func sidebarColumn() {
        let wide = [
            "text here          ▎",
            "more text          ▎ A",
            "more text          ▎ B",
            "▎ editor",
        ]
        #expect(GentleShellProfile.sidebarColumn(in: TerminalGrid(lines: wide)) == 19)
        #expect(GentleShellProfile.sidebarColumn(in: TerminalGrid(lines: ["▎ a", "▎ b", "▎ c", "▎ d"])) == nil)
        #expect(GentleShellProfile.sidebarColumn(in: TerminalGrid(lines: Array(wide.prefix(2)))) == nil)
        #expect(GentleShellProfile.sidebarColumn(in: TerminalGrid(lines: ["a▎", "b▎", "c▎"])) == nil)
    }

    @Test("Tool blocks, Elapsed rows, key hints and the header and footer marks are chrome")
    func syntheticRoles() {
        let roles = profile.roles(ofPane: [
            " Some answer",
            "",
            " $ swift test --filter",
            " Tools",
            "",
            " Elapsed 0.0s",
            " Took 12s",
            " Elapsed time is a phrase",
            " ctrl+shift+t toggles",
            "✎ 8 files · +225 −15       /changes",
            "✿ Name ⟡ main",
            "  ✿ Name  ctx ▰▰▱▱▱▱▱▱ 25% ⟡ $0.000",
            " Next answer",
            " the path of ## \u{2193} Jump to latest message \u{00B7} Ctrl+End reviewed by the user later",
            " It skips the row of the \"\u{2193} Jump to latest message\" pill.",
            "      \u{2193} Jump to latest message \u{00B7} Ctrl+End      ",
        ])

        guard case let .content(text, _) = roles[0] else { Issue.record("row 0 is not content"); return }
        #expect(text == " Some answer")
        for row in [2, 3, 5, 6, 8, 9, 10, 11] {
            #expect(roles[row] == .chrome, "row \(row)")
        }
        // The pill row reads its longer side only; a row that quotes the pill's words is ordinary.
        guard case let .content(pillText, pillColumns) = roles[13] else { Issue.record("row 13 is not content"); return }
        #expect(pillText.contains("reviewed by the user later"))
        #expect(!pillText.contains("path of"))
        #expect(pillColumns != nil)
        #expect(roles[14] != .chrome)
        #expect(roles[15] == .chrome)
        #expect(roles[7] != .chrome)
        #expect(roles[12] != .chrome)
    }

    @Test("A narrow screen without a sidebar reads its whole width")
    func noSidebar() {
        let lines = ["▔▔▔▔▔▔▔▔▔▔▔▔", " First answer here", "", "▎ typed text", "▎ more"]
        let roles = profile.roles(ofPane: lines)

        guard case let .content(text, columns) = roles[1] else { Issue.record("row 1 is not content"); return }
        #expect(text == " First answer here")
        #expect(columns == 0...(TerminalGrid(lines: lines).columns - 1))
        #expect(roles[0] == .chrome)
        #expect(roles[3] == .chrome)
    }
}
