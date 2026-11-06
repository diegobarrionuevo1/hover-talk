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
    /// The rows of that pane. Panes stacked by a horizontal split share their columns, so the
    /// rows tell them apart.
    public let paneRows: ClosedRange<Int>
    /// Every row read, top to bottom, with the text of its cells as captured. Rows of `rows`
    /// that were not read, such as blank or chrome rows between two paragraphs, are absent.
    private let captured: [CapturedRow]

    private struct CapturedRow: Equatable, Sendable {
        let span: RowSpan
        let text: String
    }

    /// `nil` when `spans` is empty. `spans` lists the cells read, one span per row, top to
    /// bottom; the cells' text on `grid` is captured now.
    init?(grid: TerminalGrid, spans: [RowSpan], paneColumns: ClosedRange<Int>, paneRows: ClosedRange<Int>) {
        guard let first = spans.first, let last = spans.last,
              let left = spans.map(\.columns.lowerBound).min(), let right = spans.map(\.columns.upperBound).max()
        else { return nil }
        rows = first.row...last.row
        columns = left...right
        self.paneColumns = paneColumns
        self.paneRows = paneRows
        captured = spans.map { CapturedRow(span: $0, text: grid.text(row: $0.row, in: $0.columns)) }
    }

    /// How many rows the captured rows moved on `screen` (negative: up), or `nil` when they are
    /// not all visible there.
    ///
    /// Looks only inside the `.program` pane of `screen` the block was read in (see the pane
    /// choice below), for a vertical
    /// shift at which every captured row's text, within that row's captured cells, equals the
    /// captured text. Text beside those cells, such as a sidebar, and rows between them that
    /// were not read, such as a tool block with a spinner, can change without losing it. The
    /// nearest match wins; at equal distance the upward one, since a terminal scrolls up as
    /// output grows.
    public func rowOffset(in screen: ParsedScreen) -> Int? {
        // The same pane: same columns and rows; when the layout changed, the pane with the
        // same columns that overlaps the rows read (two stacked panes never both do).
        let sameColumns = screen.panes.filter { $0.kind == .program && $0.pane.columns == paneColumns }.map(\.pane)
        guard let pane = sameColumns.first(where: { $0.rows == paneRows })
            ?? sameColumns.first(where: { $0.rows.overlaps(rows) })
        else { return nil }
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

    /// Where a document is on a screen when only some of its rows are found.
    public struct Placement: Equatable, Sendable {
        /// How many rows the found rows moved (negative: up).
        public let rowOffset: Int
        /// The rows of the captured document, as they were captured, that match at `rowOffset`.
        public let visibleRows: Set<Int>

        public init(rowOffset: Int, visibleRows: Set<Int>) {
            self.rowOffset = rowOffset
            self.visibleRows = visibleRows
        }

        /// The spans on rows that are visible: the rest scrolled out of view or changed.
        public func visible(_ spans: [RowSpan]) -> [RowSpan] {
            spans.filter { visibleRows.contains($0.row) }
        }
    }

    /// At least this many non-blank characters in the rows found, unless every row was found: a
    /// few short rows can show up by chance elsewhere on a screen.
    private static let minimumEvidence = 20

    /// Where the document is on `screen`, even when only part of it is there: text that scrolled
    /// partly out of view, or whose last rows changed because the program is still writing them.
    /// `rowOffset(in:)` needs every row and returns `nil` then.
    ///
    /// Looks only inside the same `.program` pane as `rowOffset(in:)`, at every vertical shift,
    /// counting the captured rows that lie in the pane and equal the captured text, cell for
    /// cell. The shift with the most rows wins, then the nearest to where it was, upward first.
    /// `nil` when no row matches, or when the rows found are not all of them and hold fewer than
    /// `minimumEvidence` non-blank characters.
    public func placement(in screen: ParsedScreen) -> Placement? {
        let sameColumns = screen.panes.filter { $0.kind == .program && $0.pane.columns == paneColumns }.map(\.pane)
        guard let pane = sameColumns.first(where: { $0.rows == paneRows })
            ?? sameColumns.first(where: { $0.rows.overlaps(rows) })
        else { return nil }

        // Any shift that leaves at least one captured row inside the pane.
        let lowest = pane.rows.lowerBound - rows.upperBound
        let highest = pane.rows.upperBound - rows.lowerBound
        var best: (offset: Int, rows: Set<Int>, characters: Int)?
        for distance in 0...max(abs(lowest), abs(highest)) {
            for offset in Set([-distance, distance]).sorted() where (lowest...highest).contains(offset) {
                var found = Set<Int>()
                var characters = 0
                for row in captured where pane.rows.contains(row.span.row + offset)
                    && screen.grid.text(row: row.span.row + offset, in: row.span.columns) == row.text {
                    found.insert(row.span.row)
                    characters += row.text.filter { !$0.isWhitespace }.count
                }
                if found.count > (best?.rows.count ?? 0) { best = (offset, found, characters) }
            }
        }
        guard let best, best.rows.count == captured.count || best.characters >= Self.minimumEvidence else { return nil }
        return Placement(rowOffset: best.offset, visibleRows: best.rows)
    }

    public var description: String {
        "ReadingAnchor(rows: \(rows), columns: \(columns), paneColumns: \(paneColumns))"
    }
}
