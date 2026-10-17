import CoreGraphics
import Testing
@testable import HoverTalkCore

@Suite("ParsedScreen")
struct ParsedScreenTests {
    @Test(
        "Parsed once, a screen gives the same block as TerminalGridProvider at every point",
        arguments: [(12, 30), (13, 180), (0, 10), (12, 110), (12, 143), (42, 10), (48, 150), (30, 60), (5, 200)]
    )
    func sameBlocksAsProvider(row: Int, column: Int) throws {
        let screen = try FixtureScreen(VSplitPanes.name)
        let parsed = ParsedScreen(lines: screen.lines, frame: screen.frame)
        let point = screen.center(row: row, column: column)

        #expect(parsed.block(at: point) == TerminalGridProvider.block(at: point, frame: screen.frame, lines: screen.lines))
    }

    @Test("The vsplit parses into the tmux status row and two OpenCode panes")
    func vsplitPanes() throws {
        let screen = try FixtureScreen(VSplitPanes.name)
        let parsed = ParsedScreen(lines: screen.lines, frame: screen.frame)

        #expect(parsed.grid.rowCount == 51)
        #expect(parsed.grid.columns == 273)
        #expect(parsed.panes.map(\.pane) == [
            Pane(rows: 0...0, columns: 0...272),
            Pane(rows: VSplitPanes.rows, columns: VSplitPanes.left),
            Pane(rows: VSplitPanes.rows, columns: VSplitPanes.right),
        ])
        #expect(parsed.panes.map(\.kind) == [.tmuxStatus, .program, .program])
        #expect(parsed.panes.map(\.profileName) == [nil, "OpenCodeProfile", "OpenCodeProfile"])
    }

    @Test("A fish screen is one pane read with the plain profile")
    func fishPane() throws {
        let screen = try FixtureScreen("plain-shell-fish")
        let parsed = ParsedScreen(lines: screen.lines, frame: screen.frame)

        #expect(parsed.panes.map(\.profileName) == ["PlainTerminalProfile"])
    }

    @Test("The pane under a point; none on a divider or outside the frame")
    func paneAtPoint() throws {
        let screen = try FixtureScreen(VSplitPanes.name)
        let parsed = ParsedScreen(lines: screen.lines, frame: screen.frame)

        #expect(parsed.pane(at: screen.center(row: 12, column: 30))?.pane.columns == VSplitPanes.left)
        #expect(parsed.pane(at: screen.center(row: 12, column: 200))?.pane.columns == VSplitPanes.right)
        #expect(parsed.pane(at: screen.center(row: 0, column: 5))?.kind == .tmuxStatus)
        #expect(parsed.pane(at: screen.center(row: 12, column: 143)) == nil)
        #expect(parsed.pane(at: CGPoint(x: screen.frame.minX - 1, y: screen.frame.midY)) == nil)
    }

    @Test("A screen parsed with one profile reads every pane with it")
    func singleProfile() throws {
        let screen = try FixtureScreen(VSplitPanes.name)
        let parsed = ParsedScreen(lines: screen.lines, frame: screen.frame, profile: PlainTerminalProfile())
        let point = screen.center(row: 12, column: 110)

        #expect(parsed.panes.compactMap(\.profileName) == ["PlainTerminalProfile", "PlainTerminalProfile"])
        #expect(parsed.block(at: point)
            == TerminalGridProvider.block(at: point, frame: screen.frame, lines: screen.lines, profile: PlainTerminalProfile()))
    }
}
