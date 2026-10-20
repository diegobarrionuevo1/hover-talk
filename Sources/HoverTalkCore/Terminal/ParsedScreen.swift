import CoreGraphics

/// A pane of a `ParsedScreen`, with the profile that reads it and the rows it reads.
public struct ParsedPane: Sendable {
    public let pane: Pane
    public let kind: PaneKind
    /// The profile that reads the pane; `nil` for a pane that is never read (not `.program`).
    public let profile: (any TUIProfile)?
    /// One entry per row of the pane: its content, or `nil` for a row that is blank or chrome.
    /// Empty when `profile` is `nil`.
    let readRows: [ReadRow?]

    /// The profile's type name, such as `OpenCodeProfile`.
    public var profileName: String? {
        profile.map { String(describing: type(of: $0)) }
    }
}

/// A content row: its collapsed text and the screen columns the profile reads it from.
struct ReadRow: Equatable, Sendable {
    let text: String
    let columns: ClosedRange<Int>
}

/// A terminal screen parsed once into its grid, panes and per-pane profile reading, so that
/// finding the block under one point after another does not parse the screen again (see
/// `ScreenBlockCache`). `TerminalGridProvider` parses and looks up in one call.
public struct ParsedScreen: Sendable {
    public let grid: TerminalGrid
    public let geometry: TerminalGeometry
    /// As `PaneLayout.classify(_:)` lists them.
    public let panes: [ParsedPane]

    /// Reads each `.program` pane with the profile `registry` picks for it.
    public init(lines: [String], frame: CGRect, registry: TUIProfileRegistry = .standard) {
        self.init(lines: lines, frame: frame) { registry.profile(for: $0) }
    }

    /// Reads every `.program` pane with `profile`.
    public init(lines: [String], frame: CGRect, profile: any TUIProfile) {
        self.init(lines: lines, frame: frame) { _ in profile }
    }

    private init(lines: [String], frame: CGRect, profileForPane: ([String]) -> any TUIProfile) {
        let grid = TerminalGrid(lines: lines)
        self.grid = grid
        geometry = TerminalGeometry(frame: frame, rows: grid.rowCount, columns: grid.columns)
        panes = PaneLayout.classify(grid).map { classified in
            guard classified.kind == .program else {
                return ParsedPane(pane: classified.pane, kind: classified.kind, profile: nil, readRows: [])
            }
            let pane = classified.pane
            let paneLines = pane.rows.map { grid.text(row: $0, in: pane.columns) }
            let profile = profileForPane(paneLines)
            let roles = profile.roles(ofPane: paneLines)
            let readRows: [ReadRow?] = paneLines.indices.map { index in
                // Defensive: a profile that returns fewer roles than rows leaves the rest unread.
                guard roles.indices.contains(index), case let .content(content, columns) = roles[index] else { return nil }
                let text = TerminalGridProvider.collapsingWhitespace(content)
                guard !text.isEmpty, let screenColumns = Self.screenColumns(columns, in: pane) else { return nil }
                return ReadRow(text: text, columns: screenColumns)
            }
            return ParsedPane(pane: pane, kind: .program, profile: profile, readRows: readRows)
        }
    }

    /// The pane under `point` (in the frame's coordinates), or `nil` outside the frame or on a
    /// divider cell.
    public func pane(at point: CGPoint) -> ParsedPane? {
        guard let cell = geometry.cell(at: point) else { return nil }
        return panes.first { $0.pane.contains(cell) }
    }

    /// The paragraph under `point`, as `TerminalGridProvider.block(at:frame:lines:registry:)`
    /// documents it; with `.continuous`, that paragraph and then every paragraph below it in
    /// its pane, one after another.
    ///
    /// Continuous reading goes down the pane from the pointed paragraph to the pane's last
    /// content row. Blank and chrome rows only separate paragraphs, so a tool block, a key hint
    /// or the `▣` footer of an earlier message between two paragraphs is skipped, never a stop
    /// (in `synthetic-claude-code.json`, rows 14 to 20 hold two tool calls between two
    /// answers). On the fixture screens, the OpenCode and Claude Code profiles read every row
    /// below the last message as blank or chrome (running tools, key hints, footers, input box,
    /// status and hint rows), so reading ends at the last message row; the plain profile has
    /// no chrome, so in a shell it ends at the last non-blank row, prompt included. Rows above
    /// the pointed paragraph and other panes are never read.
    ///
    /// Paragraphs are joined with a newline, which `SentenceSplitter` always treats as a
    /// sentence boundary. The block's `mappedText` anchors each Character to the cell it was
    /// read from (a collapsed whitespace run to the run's first cell; joining spaces and
    /// newlines to none), its `rects` hold one rect per paragraph, and its `anchor` records
    /// each paragraph's rows within that paragraph's columns, and the pane.
    public func block(at point: CGPoint, mode: ReadingMode = .paragraph) -> TerminalTextBlock? {
        guard let cell = geometry.cell(at: point),
              let parsed = panes.first(where: { $0.pane.contains(cell) }),
              parsed.kind == .program
        else { return nil }

        let readRows = parsed.readRows
        let pointed = cell.row - parsed.pane.rows.lowerBound
        guard let pointedRow = readRows[pointed], pointedRow.columns.contains(cell.column) else { return nil }

        let pointedRange = Self.paragraphRange(around: pointed, in: readRows)
        guard let first = paragraph(pointedRange, in: parsed) else { return nil }
        var paragraphs = [first]
        if mode == .continuous {
            var index = pointedRange.upperBound + 1
            while index < readRows.count {
                guard readRows[index] != nil else {
                    index += 1
                    continue
                }
                let range = Self.paragraphRange(around: index, in: readRows)
                // Defensive, as in `paragraph(_:in:)`: a paragraph without a non-blank cell is left out.
                if let paragraph = paragraph(range, in: parsed) { paragraphs.append(paragraph) }
                index = range.upperBound + 1
            }
        }
        return block(
            paragraphs,
            rects: paragraphs.map { geometry.rect(rows: $0.rows, columns: $0.columns) },
            paneColumns: parsed.pane.columns
        )
    }

    /// The text dragged over from `start` to `end` (in the frame's coordinates), or `nil` when
    /// `start` is not in a `.program` pane or nothing readable lies between the two.
    ///
    /// Only the pane under `start` is read: `end` is moved into it when it lies outside (see
    /// `TerminalGeometry.cell(nearest:in:)`). In reading order from the earlier to the later of
    /// the two cells, row by row: the first row from the earlier cell on, the last row up to
    /// the later cell (both included), the rows between whole; on each row only the cells its
    /// profile reads as content, so chrome rows, a stripped gutter and a sidebar are left out.
    /// Rows join as a paragraph's rows do; a blank or chrome row in between starts a new line.
    /// Characters are taken from the screen's cells, so a profile only decides which cells are
    /// read. The block's `rects` hold one rect per row read.
    public func selection(from start: CGPoint, to end: CGPoint) -> TerminalTextBlock? {
        guard let startCell = geometry.cell(at: start),
              let parsed = panes.first(where: { $0.pane.contains(startCell) }),
              parsed.kind == .program,
              let endCell = geometry.cell(nearest: end, in: parsed.pane)
        else { return nil }
        let pane = parsed.pane
        let (first, last) = (startCell.row, startCell.column) <= (endCell.row, endCell.column)
            ? (startCell, endCell) : (endCell, startCell)

        var pieces: [Piece] = []
        var rows: [(text: MappedText<CellPosition>, span: RowSpan)] = []
        func endPiece() {
            if let piece = Piece(text: TerminalGridProvider.joined(rows.map(\.text)), spans: rows.map(\.span)) {
                pieces.append(piece)
            }
            rows = []
        }
        for row in first.row...last.row {
            guard let readRow = parsed.readRows[row - pane.rows.lowerBound] else {
                endPiece()
                continue
            }
            let lower = row == first.row ? max(first.column, readRow.columns.lowerBound) : readRow.columns.lowerBound
            let upper = row == last.row ? min(last.column, readRow.columns.upperBound) : readRow.columns.upperBound
            guard lower <= upper, let span = grid.contentColumns(row: row, in: lower...upper) else { continue }
            rows.append((cells(row: row, in: span).collapsingWhitespace(), RowSpan(row: row, columns: span)))
        }
        endPiece()
        let spans = pieces.flatMap(\.spans)
        return block(pieces, rects: spans.map { geometry.rect(rows: $0.row...$0.row, columns: $0.columns) }, paneColumns: pane.columns)
    }

    // MARK: Building blocks

    /// Rows read together, a paragraph or the rows of a selection between two unread rows:
    /// their joined text and the cells read, one span per row, top to bottom.
    private struct Piece {
        let text: MappedText<CellPosition>
        let spans: [RowSpan]
        /// From the first to the last span's row.
        let rows: ClosedRange<Int>
        /// From the leftmost to the rightmost span column.
        let columns: ClosedRange<Int>

        /// `nil` without spans.
        init?(text: MappedText<CellPosition>, spans: [RowSpan]) {
            guard let first = spans.first, let last = spans.last,
                  let left = spans.map(\.columns.lowerBound).min(), let right = spans.map(\.columns.upperBound).max()
            else { return nil }
            self.text = text
            self.spans = spans
            rows = first.row...last.row
            columns = left...right
        }
    }

    /// The pieces joined with a newline into one block; `nil` without pieces.
    private func block(_ pieces: [Piece], rects: [CGRect], paneColumns: ClosedRange<Int>) -> TerminalTextBlock? {
        let spans = pieces.flatMap(\.spans)
        guard let anchor = ReadingAnchor(grid: grid, spans: spans, paneColumns: paneColumns) else { return nil }
        var text = MappedText<CellPosition>()
        for (index, piece) in pieces.enumerated() {
            if index > 0 { text.append("\n", anchor: nil) }
            text.append(piece.text)
        }
        return TerminalTextBlock(
            mappedText: text,
            rows: anchor.rows,
            columns: anchor.columns,
            rect: geometry.rect(rows: anchor.rows, columns: anchor.columns),
            rects: rects,
            anchor: anchor
        )
    }

    /// The pane-relative rows of the run of content rows around `index`, which is a content row.
    private static func paragraphRange(around index: Int, in readRows: [ReadRow?]) -> ClosedRange<Int> {
        var first = index
        var last = index
        while first > 0, readRows[first - 1] != nil { first -= 1 }
        while last < readRows.count - 1, readRows[last + 1] != nil { last += 1 }
        return first...last
    }

    /// The paragraph on the pane-relative `rows` of `parsed`, all content rows: its rows
    /// joined, and every row's span from the leftmost to the rightmost non-blank cell of the
    /// whole paragraph among the cells read.
    private func paragraph(_ rows: ClosedRange<Int>, in parsed: ParsedPane) -> Piece? {
        let top = parsed.pane.rows.lowerBound
        let screenRows = (top + rows.lowerBound)...(top + rows.upperBound)
        let content = parsed.readRows[rows].compactMap { $0 }
        let filled = zip(screenRows, content).compactMap { grid.contentColumns(row: $0, in: $1.columns) }
        // Defensive: the bundled profiles take their text from these cells, so a non-blank
        // content row has a non-blank cell; a profile that invents text could break that.
        guard let left = filled.map(\.lowerBound).min(), let right = filled.map(\.upperBound).max() else { return nil }
        return Piece(
            text: TerminalGridProvider.joined(zip(screenRows, content).map { mappedText(row: $0, $1) }),
            spans: screenRows.map { RowSpan(row: $0, columns: left...right) }
        )
    }

    /// A row's cells within `columns`, each Character anchored to its first cell.
    private func cells(row: Int, in columns: ClosedRange<Int>) -> MappedText<CellPosition> {
        var cells = MappedText<CellPosition>()
        for (column, character) in grid.characters(row: row, in: columns) {
            cells.append(character, anchor: CellPosition(row: row, column: column))
        }
        return cells
    }

    /// A content row's text with each Character anchored to its cell: the row's cells within
    /// the columns the profile reads, with whitespace collapsed as `ReadRow.text` is. When that
    /// is not the profile's text (a profile may return text that is not on screen), the
    /// profile's text without anchors.
    private func mappedText(row: Int, _ readRow: ReadRow) -> MappedText<CellPosition> {
        let collapsed = cells(row: row, in: readRow.columns).collapsingWhitespace()
        return collapsed.text == readRow.text ? collapsed : MappedText(readRow.text)
    }

    /// A role's pane-relative columns on screen, clamped to the pane; the whole pane for `nil`.
    private static func screenColumns(_ columns: ClosedRange<Int>?, in pane: Pane) -> ClosedRange<Int>? {
        guard let columns else { return pane.columns }
        let lower = max(pane.columns.lowerBound + columns.lowerBound, pane.columns.lowerBound)
        let upper = min(pane.columns.lowerBound + columns.upperBound, pane.columns.upperBound)
        return lower <= upper ? lower...upper : nil
    }
}
