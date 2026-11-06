import CoreGraphics
@testable import HoverTalkCore

/// A fixture screen for provider tests, with its captured AX frame, or 10 × 20 points per cell
/// at the origin when the fixture has none.
struct FixtureScreen {
    let lines: [String]
    let grid: TerminalGrid
    let frame: CGRect

    init(_ name: String) throws {
        let fixture = try ScreenFixture.load(name)
        lines = fixture.lines
        grid = TerminalGrid(lines: fixture.lines)
        frame = fixture.frame
            ?? CGRect(x: 0, y: 0, width: CGFloat(grid.columns) * 10, height: CGFloat(grid.rowCount) * 20)
    }

    var cellWidth: CGFloat { frame.width / CGFloat(grid.columns) }

    /// The left edge of a column, in the frame's coordinates.
    func x(column: Int) -> CGFloat {
        frame.minX + CGFloat(column) * cellWidth
    }

    func center(row: Int, column: Int) -> CGPoint {
        CGPoint(
            x: x(column: column) + cellWidth / 2,
            y: frame.minY + (CGFloat(row) + 0.5) * frame.height / CGFloat(grid.rowCount)
        )
    }

    /// The block under the centre of a cell, with the standard profile registry.
    func block(row: Int, column: Int, statusBar: StatusEdge? = nil) -> TerminalTextBlock? {
        TerminalGridProvider.block(at: center(row: row, column: column), frame: frame, lines: lines, statusBar: statusBar)
    }

    /// Rows cut to a pane's columns: what a profile receives.
    func paneLines(rows: ClosedRange<Int>, columns: ClosedRange<Int>) -> [String] {
        rows.map { grid.text(row: $0, in: columns) }
    }
}

/// The panes of `ghostty-tmux-vsplit-opencode.json` (see `PaneLayoutTests`).
enum VSplitPanes {
    static let name = "ghostty-tmux-vsplit-opencode"
    static let rows = 1...50
    static let left = 0...142
    static let right = 144...272
}
