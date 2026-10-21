import Testing
@testable import HoverTalkCore

@Suite("OpenCodeProfile")
struct OpenCodeProfileTests {
    private let profile = OpenCodeProfile()

    /// A vsplit pane's rows; index 0 is screen row 1.
    private func vsplitPane(_ columns: ClosedRange<Int>) throws -> [String] {
        try FixtureScreen(VSplitPanes.name).paneLines(rows: VSplitPanes.rows, columns: columns)
    }

    /// `left` padded with spaces to `column`, then `right`.
    private func row(_ left: String, _ right: String = "", at column: Int = 40) -> String {
        left + String(repeating: " ", count: column - left.count) + right
    }

    private func collapsed(_ role: LineRole) -> String? {
        guard case let .content(text, _) = role else { return nil }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: Detection

    @Test("Both OpenCode panes of the vsplit match")
    func matchesVsplitPanes() throws {
        #expect(profile.matches(paneLines: try vsplitPane(VSplitPanes.left)))
        #expect(profile.matches(paneLines: try vsplitPane(VSplitPanes.right)))
    }

    @Test("The fish screen, the synthetic Claude Code screen and the tmux status row do not match")
    func otherScreensDoNotMatch() throws {
        let screen = try FixtureScreen(VSplitPanes.name)

        #expect(!profile.matches(paneLines: try ScreenFixture.load("plain-shell-fish").lines))
        #expect(!profile.matches(paneLines: try ScreenFixture.load("synthetic-claude-code").lines))
        #expect(!profile.matches(paneLines: screen.paneLines(rows: 0...0, columns: 0...272)))
    }

    @Test("One kind of marker is not enough; two independent kinds are")
    func markerKinds() {
        let box = "  \u{2579}\u{2580}\u{2580}\u{2580}\u{2580}"
        let footer = "     \u{25A3}  build \u{00B7} model"
        let hints = "   esc interrupt     ctrl+p commands"
        let version = "   \u{2022} OpenCode 1.2.3"

        #expect(!profile.matches(paneLines: [box]))
        #expect(!profile.matches(paneLines: [footer, "text"]))
        #expect(!profile.matches(paneLines: [hints]))
        #expect(!profile.matches(paneLines: [version]))
        #expect(profile.matches(paneLines: [box, hints]))
        #expect(profile.matches(paneLines: [footer, version]))
        // Near misses: a key named in prose, a lone ╹, a word after "OpenCode".
        #expect(!profile.matches(paneLines: ["   ctrl+p to paste", "  \u{2579} plain", "OpenCode rocks", "\u{25A3}"]))
    }

    // MARK: Sidebar

    @Test("The sidebar starts at cell 103 of the left pane and cell 89 of the right pane (233 on screen)")
    func sidebarInVsplit() throws {
        #expect(OpenCodeProfile.sidebarColumn(in: TerminalGrid(lines: try vsplitPane(VSplitPanes.left))) == 103)
        #expect(OpenCodeProfile.sidebarColumn(in: TerminalGrid(lines: try vsplitPane(VSplitPanes.right))) == 89)
    }

    private var sidebarRows: [String] {
        [
            row("  \u{2503}  first message row", "Session title"),
            row("  \u{2503}  second row", "Context"),
            row("", "1,234 tokens"),
            row("     assistant text", "12% used"),
            row("     more text", "$0.42 spent"),
            row("", "\u{25BC} MCP"),
        ]
    }

    @Test("A right-hand column with sidebar markers after a blank gap is the sidebar")
    func syntheticSidebar() {
        #expect(OpenCodeProfile.sidebarColumn(in: TerminalGrid(lines: sidebarRows)) == 40)
    }

    @Test("An aligned column of plain words is not a sidebar: it needs two kinds of markers")
    func columnWithoutMarkers() {
        let lines = ["alpha", "beta", "gamma", "delta", "omega"].map { row("     text on the left", $0) }
        let oneKind = ["Context", "beta", "Context", "delta"].map { row("     text on the left", $0) }

        #expect(OpenCodeProfile.sidebarColumn(in: TerminalGrid(lines: lines)) == nil)
        #expect(OpenCodeProfile.sidebarColumn(in: TerminalGrid(lines: oneKind)) == nil)
    }

    @Test("Markers do not make a sidebar when text runs through the gap before them on many rows")
    func gapCrossedOnManyRows() {
        let long = String(repeating: "word ", count: 7) + "end"  // ends at cell 37, inside the gap 37...39
        let lines = Array(sidebarRows.prefix(4)) + Array(repeating: row(long, "x"), count: 6)

        #expect(OpenCodeProfile.sidebarColumn(in: TerminalGrid(lines: lines)) == nil)
    }

    @Test("One row in ten may cross the gap without hiding the sidebar")
    func gapCrossedOnce() {
        let long = String(repeating: "word ", count: 7) + "end"
        let lines = sidebarRows + [row(long)] + sidebarRows

        #expect(OpenCodeProfile.sidebarColumn(in: TerminalGrid(lines: lines)) == 40)
    }

    @Test("An aligned column inside the message area is not the sidebar; the rightmost column with markers is")
    func alignedColumnInMessageArea() {
        let lines = sidebarRows.map { line in
            var cells = Array(line)
            cells.replaceSubrange(30..<35, with: "value")  // left text ends by cell 21, sidebar from 40
            return String(cells)
        }

        #expect(OpenCodeProfile.sidebarColumn(in: TerminalGrid(lines: lines)) == 40)
    }

    @Test("No sidebar on the fish screen, on a screen of short rows, or on fewer than three rows")
    func noSidebar() throws {
        #expect(OpenCodeProfile.sidebarColumn(in: TerminalGrid(lines: try ScreenFixture.load("plain-shell-fish").lines)) == nil)
        #expect(OpenCodeProfile.sidebarColumn(in: TerminalGrid(lines: ["  \u{2503}  one", "     two", "", "     three"])) == nil)
        #expect(OpenCodeProfile.sidebarColumn(in: TerminalGrid(lines: Array(sidebarRows.prefix(2)))) == nil)
        #expect(OpenCodeProfile.sidebarColumn(in: TerminalGrid(lines: [])) == nil)
    }

    // MARK: Roles on the vsplit

    @Test("Left pane: the running tool, key hints, input box, its border and the status line are chrome; the footer ends the message")
    func leftPaneChrome() throws {
        let roles = profile.roles(ofPane: try vsplitPane(VSplitPanes.left))

        #expect(roles.count == 50)
        for screenRow in [34, 35, 36, 37, 38, 40, 44, 45, 46, 47, 48, 49, 50] {
            #expect(roles[screenRow - 1] == .chrome, "row \(screenRow)")
        }
        #expect(roles[42 - 1] == .end)
        for screenRow in [1, 11, 12, 13, 17, 30, 32] {
            #expect(roles[screenRow - 1] != .chrome, "row \(screenRow)")
        }
    }

    @Test("Left pane: a message row loses its ┃ gutter and the sidebar text on the same row")
    func leftPaneContent() throws {
        let roles = profile.roles(ofPane: try vsplitPane(VSplitPanes.left))

        #expect(collapsed(roles[11]) == "lantern cedar go hillside. \u{00BF}Fig sparrow sky oak?")
        #expect(roles[11] == .content(try #require(textOf(roles[11])), columns: 3...102))
        // Sidebar-only rows inside a message become blank.
        #expect(collapsed(roles[1]) == "")
        #expect(collapsed(roles[13]) == "")
        // A row without a gutter keeps its indentation cells.
        #expect(roles[29] == .content(try #require(textOf(roles[29])), columns: 0...102))
    }

    @Test("Right pane: ⏳ and spinner tool rows, key hints and input box are chrome, the footer ends the message; the sidebar is cut at 89")
    func rightPane() throws {
        let roles = profile.roles(ofPane: try vsplitPane(VSplitPanes.right))

        for screenRow in [34, 36, 37, 38, 40, 44, 45, 46, 47, 48, 49] {
            #expect(roles[screenRow - 1] == .chrome, "row \(screenRow)")
        }
        #expect(roles[42 - 1] == .end)
        #expect(collapsed(roles[12]) == "lavenderby moonbeam, harbor fig), cedar \u{2192} (fig, falcon) \u{2192} wind,")
        #expect(roles[12] == .content(try #require(textOf(roles[12])), columns: 3...88))
    }

    private func textOf(_ role: LineRole) -> String? {
        guard case let .content(text, _) = role else { return nil }
        return text
    }

    // MARK: Roles on synthetic rows

    @Test("The ┃ rows right above ╹▀▀▀ are the input box; a ┃ message separated from it by a blank row stays content")
    func inputBox() {
        let lines = [
            "  \u{2503}  a message",
            "",
            "  \u{2503}",
            "  \u{2503}  draft text",
            "  \u{2503}  build \u{00B7} model",
            "  \u{2579}\u{2580}\u{2580}\u{2580}\u{2580}\u{2580}\u{2580}\u{2580}\u{2580}",
            "   ~/work  12.3K (4%)  ctrl+p commands",
            "     anything below",
        ]
        let roles = profile.roles(ofPane: lines)

        #expect(collapsed(roles[0]) == "a message")
        #expect(roles[1] != .chrome)
        #expect(roles[2...].allSatisfy { $0 == .chrome })
    }

    @Test("A row starting with a braille spinner or ⏳ and the deeper rows under it are chrome, up to a blank or shallower row")
    func toolBlocks() {
        let lines = [
            "     \u{2834} Tool title",
            "       \u{21B3} Bash first part of a long",
            "       command that wraps",
            "     text at the same indent",
            "",
            "     \u{23F3} Pending tool",
            "",
            "       after a blank row",
        ]
        let roles = profile.roles(ofPane: lines)

        #expect(roles[0...2].allSatisfy { $0 == .chrome })
        #expect(collapsed(roles[3]) == "text at the same indent")
        #expect(roles[5] == .chrome)
        #expect(collapsed(roles[7]) == "after a blank row")
    }

    @Test("The ▣ footer ends a message; key-hint rows and rows of only progress glyphs are chrome; prose naming a key is not")
    func rowLocalChrome() {
        #expect(profile.role(of: "     \u{25A3}  build \u{00B7} model \u{00B7} 2.1s") == .end)
        #expect(profile.role(of: "     ctrl+x expand") == .chrome)
        #expect(profile.role(of: "   esc interrupt") == .chrome)
        #expect(profile.role(of: "   \u{2B1D}\u{2B1D}\u{2B1D}\u{2B1D}") == .chrome)
        #expect(profile.role(of: "  \u{280B}") == .chrome)
        #expect(profile.role(of: "     press ctrl+c to stop") == .content("     press ctrl+c to stop", columns: 0...24))
    }

    @Test("A leading ┃ and its indentation are left out of a row's content and cells")
    func gutter() {
        // 16 cells: two spaces, ┃ at 2, then "  Hello there" in 3...15.
        #expect(profile.role(of: "  \u{2503}  Hello there") == .content("  Hello there", columns: 3...15))
        #expect(profile.role(of: "     no gutter") == .content("     no gutter", columns: 0...13))
    }
}
