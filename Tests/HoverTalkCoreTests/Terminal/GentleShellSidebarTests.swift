import CoreGraphics
import Testing
@testable import HoverTalkCore

/// Against `synthetic-gentle-shell-sidebar.json`: hand-written, modeled on a full-width Gentle
/// Shell with its right sidebar (sections behind `▾`), no `▎` gutters and no `▔▔▔` rule, under a
/// tmux status row. Neutral text; the layout follows what Gentle Shell draws.
@Suite("GentleShellProfile, sidebar layout")
struct GentleShellSidebarTests {
    private static let name = "synthetic-gentle-shell-sidebar"
    private let profile = GentleShellProfile()

    private func parsed() throws -> (ParsedScreen, FixtureScreen) {
        let screen = try FixtureScreen(Self.name)
        return (ParsedScreen(lines: screen.lines, frame: screen.frame, statusBar: .top), screen)
    }

    @Test("With the tmux bar known, the screen is the status row and one Gentle Shell pane")
    func detection() throws {
        let (parsed, _) = try parsed()

        #expect(parsed.panes.map(\.kind) == [.tmuxStatus, .program])
        #expect(parsed.panes.compactMap(\.profileName) == ["GentleShellProfile"])
    }

    @Test("A message paragraph is read on its own, cut before the sidebar")
    func messageParagraph() throws {
        let (_, screen) = try parsed()
        let block = try #require(screen.block(row: 10, column: 30, statusBar: .top))

        #expect(block.text == "I reviewed it inline because it is only tests and configuration, with no risk item. It touches no source folder, so it cannot break production.")
        #expect(block.rows == 10...11)
        #expect(block.columns.upperBound < 160)
    }

    @Test("The header, the echo rows, the sidebar, the pill, the editor and the footer give no block")
    func chrome() throws {
        let (_, screen) = try parsed()
        let cells: [(row: Int, column: Int, what: String)] = [
            (0, 5, "tmux status"), (1, 5, "header"), (1, 190, "header, right side"), (2, 3, "took row"),
            (5, 5, "memory echo"), (6, 5, "saved echo"),
            (3, 165, "sidebar title"), (4, 170, "sidebar body"), (6, 165, "sidebar title"), (7, 170, "sidebar body"),
            (9, 170, "sidebar title"), (10, 170, "sidebar body beside a message row"), (11, 170, "sidebar body"),
            (13, 170, "sidebar hint beside a message row"),
            (36, 70, "jump pill"), (38, 10, "editor frame"), (39, 5, "prompt"), (42, 5, "footer"), (42, 190, "footer, right"),
        ]
        for cell in cells {
            #expect(screen.block(row: cell.row, column: cell.column, statusBar: .top) == nil, "\(cell.what): row \(cell.row)")
        }
    }

    @Test("Continuous reading goes from a message to the last answer row and never into the sidebar or the editor")
    func continuousReading() throws {
        let (parsed, screen) = try parsed()
        let block = try #require(parsed.block(at: screen.center(row: 8, column: 3), mode: .continuous))

        #expect(block.text.hasPrefix("Verdict #48: MERGE (with warnings)"))
        #expect(block.text.contains("Clean merge."))
        #expect(block.text.hasSuffix("retries set to zero on purpose."))
        for word in ["AGENTS", "CHANGES", "INTEGRATIONS", "idle", "/tool:", "ctrl+shift", "waiting for input", "type, or", "detached", "reviewer", "saved #", "Took", "Jump to latest"] {
            #expect(!block.text.contains(word), "\(word)")
        }
    }

    @Test("The sidebar column is the one of the ▾ or ▸ section titles, and only in the right half")
    func sidebarColumn() throws {
        let grid = TerminalGrid(lines: try ScreenFixture.load(Self.name).lines)

        #expect(GentleShellProfile.sidebarColumn(in: grid) == 160)
        #expect(GentleShellProfile.sidebarColumn(in: TerminalGrid(lines: ["▾ one      x", "▾ two      y", "text       z"])) == nil)
        #expect(GentleShellProfile.sidebarColumn(in: TerminalGrid(lines: ["abcdefgh ▾ one", "abcdefgh ▸ two"])) == 9)
        // One title is not a sidebar, and OpenCode's ▼ ▶ toggles are not Gentle Shell's.
        #expect(GentleShellProfile.sidebarColumn(in: TerminalGrid(lines: ["abcdefgh ▾ one", "abcdefgh   two"])) == nil)
        #expect(GentleShellProfile.sidebarColumn(in: TerminalGrid(lines: ["abcdefgh ▼ one", "abcdefgh ▶ two"])) == nil)
    }

    @Test("The editor frame row `─ ✿ label ───` counts as a marker, with the gauge; alone it does not")
    func editorFrameMarker() {
        let frame = "─ ✿ waiting for input" + String(repeating: "─", count: 20)

        #expect(profile.matches(paneLines: [frame, "› type", "x ▰▱▱▱▱▱▱▱ 14%"]))
        #expect(!profile.matches(paneLines: [frame, "› type"]))
        #expect(!profile.matches(paneLines: ["────────────────────", "plain rule"]))
    }

    @Test("Everything from the editor frame down is chrome, whatever the user typed")
    func editorIsChrome() {
        let roles = profile.roles(ofPane: [
            " An answer.",
            "",
            "─ ✿ waiting for input" + String(repeating: "─", count: 20),
            "› typed words here",
            "  more typed words",
            "",
            " footer text",
        ])

        #expect(roles[0] != .chrome)
        for row in 2...6 { #expect(roles[row] == .chrome, "row \(row)") }
    }
}
