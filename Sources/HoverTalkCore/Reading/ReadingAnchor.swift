/// Where a block was read on a terminal screen, so its highlight can follow it when the screen
/// scrolls or changes: the cells of every row read, their text, and the pane.
///
/// The captured text stays in memory and is never part of `description`.
public struct ReadingAnchor: Equatable, Sendable, CustomStringConvertible {
    /// From the first to the last row read.
    public let rows: ClosedRange<Int>
    /// From the leftmost to the rightmost column of the rows read.
    public let columns: ClosedRange<Int>
    /// The columns of the pane the block was read in.
    public let paneColumns: ClosedRange<Int>
    /// Every row read, top to bottom, with the text of its cells as captured. Rows of `rows`
    /// that were not read, such as blank or chrome rows between two paragraphs, are absent.
    private let captured: [CapturedRow]

    private struct CapturedRow: Equatable, Sendable {
        let span: RowSpan
        let text: String
    }

    /// `nil` when `spans` is empty. `spans` lists the cells read, one span per row, top to
    /// bottom; the cells' text on `grid` is captured now.
    init?(grid: TerminalGrid, spans: [RowSpan], paneColumns: ClosedRange<Int>) {
        guard let first = spans.first, let last = spans.last,
              let left = spans.map(\.columns.lowerBound).min(), let right = spans.map(\.columns.upperBound).max()
        else { return nil }
        rows = first.row...last.row
        columns = left...right
        self.paneColumns = paneColumns
        captured = spans.map { CapturedRow(span: $0, text: grid.text(row: $0.row, in: $0.columns)) }
    }

    /// How many rows the captured rows moved on `screen` (negative: up), or `nil` when they are
    /// not all visible there.
    ///
    /// Looks only inside the `.program` pane of `screen` with the same columns, for a vertical
    /// shift at which every captured row's text, within that row's captured cells, equals the
    /// captured text. Text beside those cells, such as a sidebar, and rows between them that
    /// were not read, such as a tool block with a spinner, can change without losing it. The
    /// nearest match wins; at equal distance the upward one, since a terminal scrolls up as
    /// output grows.
    public func rowOffset(in screen: ParsedScreen) -> Int? {
        guard let pane = screen.panes.first(where: { $0.kind == .program && $0.pane.columns == paneColumns })?.pane else {
            return nil
        }
        let lowest = pane.rows.lowerBound - rows.lowerBound
        let highest = pane.rows.upperBound - rows.upperBound
        guard lowest <= highest else { return nil }

        func matches(_ offset: Int) -> Bool {
            captured.allSatisfy { screen.grid.text(row: $0.span.row + offset, in: $0.span.columns) == $0.text }
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
