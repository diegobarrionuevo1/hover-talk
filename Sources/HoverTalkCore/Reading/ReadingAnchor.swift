/// Where a block was read on a terminal screen, so its highlight can follow it when the screen
/// scrolls or changes: the block's rows, their text within the block's columns, and its pane.
///
/// The captured text stays in memory and is never part of `description`.
public struct ReadingAnchor: Equatable, Sendable, CustomStringConvertible {
    public let rows: ClosedRange<Int>
    public let columns: ClosedRange<Int>
    /// The columns of the pane the block was read in.
    public let paneColumns: ClosedRange<Int>
    /// The text of each row of `rows` within `columns`, as captured.
    private let rowTexts: [String]

    init(grid: TerminalGrid, rows: ClosedRange<Int>, columns: ClosedRange<Int>, paneColumns: ClosedRange<Int>) {
        self.rows = rows
        self.columns = columns
        self.paneColumns = paneColumns
        rowTexts = rows.map { grid.text(row: $0, in: columns) }
    }

    /// How many rows the captured rows moved on `screen` (negative: up), or `nil` when they are
    /// not all visible there.
    ///
    /// Looks only inside the `.program` pane of `screen` with the same columns, for a run of
    /// rows whose text within `columns` equals the captured text, row by row. Text beside the
    /// block, such as a sidebar, can change without losing it. The nearest match wins; at equal
    /// distance the upward one, since a terminal scrolls up as output grows.
    public func rowOffset(in screen: ParsedScreen) -> Int? {
        guard let pane = screen.panes.first(where: { $0.kind == .program && $0.pane.columns == paneColumns })?.pane else {
            return nil
        }
        let lowest = pane.rows.lowerBound - rows.lowerBound
        let highest = pane.rows.upperBound - rows.upperBound
        guard lowest <= highest else { return nil }

        let texts = pane.rows.map { screen.grid.text(row: $0, in: columns) }
        func matches(_ offset: Int) -> Bool {
            let start = rows.lowerBound + offset - pane.rows.lowerBound
            return texts[start..<(start + rowTexts.count)].elementsEqual(rowTexts)
        }
        for distance in 0...max(abs(lowest), abs(highest)) {
            for offset in Set([-distance, distance]).sorted() where (lowest...highest).contains(offset) && matches(offset) {
                return offset
            }
        }
        return nil
    }

    public var description: String {
        "ReadingAnchor(rows: \(rows), columns: \(columns), paneColumns: \(paneColumns))"
    }
}
