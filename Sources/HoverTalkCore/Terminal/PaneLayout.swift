/// A rectangle of grid cells that one program draws into, such as a tmux pane.
public struct Pane: Equatable, Sendable {
    public let rows: ClosedRange<Int>
    public let columns: ClosedRange<Int>

    public init(rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
        self.rows = rows
        self.columns = columns
    }

    public func contains(_ cell: CellPosition) -> Bool {
        rows.contains(cell.row) && columns.contains(cell.column)
    }
}

/// Finds the panes of a terminal screen from the divider lines drawn between them (tmux's
/// default single-line borders).
public enum PaneLayout {
    /// `│` and its junctions. `┃` (U+2503) is deliberately absent: OpenCode draws it as a
    /// message gutter. Rounded corners (`╭╮╰╯`) are box borders, not dividers.
    static let verticalDividers: Set<Character> = ["\u{2502}", "\u{251C}", "\u{2524}", "\u{253C}", "\u{252C}", "\u{2534}"]
    /// `─` and its junctions.
    static let horizontalDividers: Set<Character> = ["\u{2500}", "\u{251C}", "\u{2524}", "\u{253C}", "\u{252C}", "\u{2534}"]

    /// Splits the whole grid recursively. Inside a rectangle, the first column with a vertical
    /// divider glyph on every row splits it; otherwise the first row with a horizontal divider
    /// glyph on every column does. Divider cells belong to no pane. A divider must span at
    /// least two cells. When neither exists, the top row and then the bottom row (such as a
    /// tmux status bar) are tried once as a pane of their own; that is kept only if the rest
    /// then splits. Panes are listed in split order: left before right, top before bottom.
    public static func detect(_ grid: TerminalGrid) -> [Pane] {
        guard grid.rowCount > 0, grid.columns > 0 else { return [] }
        return split(Pane(rows: 0...(grid.rowCount - 1), columns: 0...(grid.columns - 1)), in: grid, allowPeel: true)
    }

    private static func split(_ rect: Pane, in grid: TerminalGrid, allowPeel: Bool) -> [Pane] {
        let (top, bottom) = (rect.rows.lowerBound, rect.rows.upperBound)
        let (left, right) = (rect.columns.lowerBound, rect.columns.upperBound)

        if rect.rows.count >= 2, let column = rect.columns.first(where: { column in
            rect.rows.allSatisfy { verticalDividers.contains(grid.character(row: $0, column: column) ?? " ") }
        }) {
            return split(rows: top, bottom, columns: left, column - 1, in: grid)
                + split(rows: top, bottom, columns: column + 1, right, in: grid)
        }
        if rect.columns.count >= 2, let row = rect.rows.first(where: { row in
            rect.columns.allSatisfy { horizontalDividers.contains(grid.character(row: row, column: $0) ?? " ") }
        }) {
            return split(rows: top, row - 1, columns: left, right, in: grid)
                + split(rows: row + 1, bottom, columns: left, right, in: grid)
        }
        // A one-row rest never yields more than one pane, so peeling needs at least three rows.
        if allowPeel, rect.rows.count >= 3 {
            let belowTop = split(Pane(rows: (top + 1)...bottom, columns: rect.columns), in: grid, allowPeel: false)
            if belowTop.count > 1 { return [Pane(rows: top...top, columns: rect.columns)] + belowTop }

            let aboveBottom = split(Pane(rows: top...(bottom - 1), columns: rect.columns), in: grid, allowPeel: false)
            if aboveBottom.count > 1 { return aboveBottom + [Pane(rows: bottom...bottom, columns: rect.columns)] }
        }
        return [rect]
    }

    /// Splits the rectangle between the given bounds, or returns nothing when it is empty
    /// (a divider on the edge of its parent).
    private static func split(rows top: Int, _ bottom: Int, columns left: Int, _ right: Int, in grid: TerminalGrid) -> [Pane] {
        guard top <= bottom, left <= right else { return [] }
        return split(Pane(rows: top...bottom, columns: left...right), in: grid, allowPeel: true)
    }
}
