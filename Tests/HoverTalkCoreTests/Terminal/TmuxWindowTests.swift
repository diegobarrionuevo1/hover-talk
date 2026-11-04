import CoreGraphics
import Testing
@testable import HoverTalkCore

/// A tmux window without splits (what `ctrl+b c` opens): no divider gives the status bar away.
@Suite("tmux window without splits")
struct TmuxWindowTests {
    /// The real status row of the Ghostty tmux fixture, over a single unsplit pane.
    private func screen() throws -> (lines: [String], frame: CGRect) {
        let status = try ScreenFixture.load("ghostty-tmux-vsplit-opencode").lines[0]
        func pad(_ s: String) -> String { s + String(repeating: " ", count: max(0, status.count - s.count)) }
        let lines = [status, pad("user@host ~/code> ls"), pad("README.md  Package.swift"), pad("user@host ~/code> ")]
        let grid = TerminalGrid(lines: lines)
        return (lines, CGRect(x: 0, y: 0, width: CGFloat(grid.columns) * 10, height: CGFloat(grid.rowCount) * 20))
    }

    @Test("With the status bar known, the unsplit screen is the status row and one program pane")
    func classifiesStatusRow() throws {
        let grid = TerminalGrid(lines: try screen().lines)

        #expect(PaneLayout.classify(grid, statusBar: .top).map(\.kind) == [.tmuxStatus, .program])
        #expect(PaneLayout.classify(grid, statusBar: .top).map(\.pane.rows) == [0...0, 1...3])
        #expect(PaneLayout.classify(grid, statusBar: .bottom).map(\.pane.rows) == [0...2, 3...3])
    }

    @Test("Without the hint, the screen is read as before")
    func noHintKeepsOldBehavior() throws {
        let grid = TerminalGrid(lines: try screen().lines)

        #expect(PaneLayout.classify(grid).map(\.kind) == [.program])
    }

    @Test("The first row under the status row is read without the status row")
    func statusRowNotMerged() throws {
        let (lines, frame) = try screen()
        let block = TerminalGridProvider.block(at: CGPoint(x: 5, y: 30), frame: frame, lines: lines, statusBar: .top)

        #expect(block?.text == "user@host ~/code> ls README.md Package.swift user@host ~/code>")
        #expect(block?.rows == 1...3)
    }

    @Test("Pointing at the status row reads nothing")
    func statusRowNotRead() throws {
        let (lines, frame) = try screen()

        #expect(TerminalGridProvider.block(at: CGPoint(x: 15, y: 10), frame: frame, lines: lines, statusBar: .top) == nil)
    }

    @Test("The cache asks for the status bar with the screen size and applies it")
    func cacheUsesProvider() throws {
        let (lines, frame) = try screen()
        let grid = TerminalGrid(lines: lines)
        var cache = ScreenBlockCache(statusBar: { columns, rows in
            columns == grid.columns && rows == grid.rowCount ? .top : nil
        })

        let parsed = cache.screen(value: lines.joined(separator: "\n"), frame: frame)

        #expect(parsed.panes.map(\.kind) == [.tmuxStatus, .program])
    }
}

@Suite("TmuxClients")
struct TmuxClientsTests {
    private func edge(_ output: String) -> StatusEdge? {
        TmuxClients.statusBar(in: output, columns: 209, rows: 43)
    }

    @Test("The client of the same size gives its status bar edge")
    func matchingClient() {
        #expect(edge("209 43 on top") == .top)
        #expect(edge("120 30 on top\n209 43 on bottom\n") == .bottom)
        #expect(edge("209 43 on top\n209 43 on top") == .top)
    }

    @Test("No client of that size, a status bar that is off or taller, or clients that disagree give no hint")
    func noHint() {
        #expect(edge("") == nil)
        #expect(edge("120 30 on top") == nil)
        #expect(edge("209 43 off top") == nil)
        #expect(edge("209 43 2 top") == nil)
        #expect(edge("209 43 on top\n209 43 on bottom") == nil)
        #expect(edge("209 43 on top\n209 43 off top") == nil)
    }
}
