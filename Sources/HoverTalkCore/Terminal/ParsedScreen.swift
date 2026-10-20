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
    /// documents it. Its `mappedText` anchors each Character to the cell it was read from (a
    /// collapsed whitespace run to the run's first cell; joining spaces and newlines to none),
    /// and its `anchor` records the paragraph's rows within its columns and pane.
    public func block(at point: CGPoint) -> TerminalTextBlock? {
        guard let cell = geometry.cell(at: point),
              let parsed = panes.first(where: { $0.pane.contains(cell) }),
              parsed.kind == .program
        else { return nil }

        let pane = parsed.pane
        let readRows = parsed.readRows
        let pointed = cell.row - pane.rows.lowerBound
        guard let pointedRow = readRows[pointed], pointedRow.columns.contains(cell.column) else { return nil }

        var first = pointed
        var last = pointed
        while first > 0, readRows[first - 1] != nil { first -= 1 }
        while last < readRows.count - 1, readRows[last + 1] != nil { last += 1 }
        let rows = (pane.rows.lowerBound + first)...(pane.rows.lowerBound + last)
        let paragraph = readRows[first...last].compactMap { $0 }

        let spans = zip(rows, paragraph).compactMap { grid.contentColumns(row: $0, in: $1.columns) }
        // Defensive: the bundled profiles take their text from these cells, so a non-blank
        // content row has a non-blank cell; a profile that invents text could break that.
        guard let left = spans.map(\.lowerBound).min(), let right = spans.map(\.upperBound).max() else { return nil }
        let columns = left...right

        return TerminalTextBlock(
            mappedText: TerminalGridProvider.joined(zip(rows, paragraph).map { mappedText(row: $0, $1) }),
            rows: rows,
            columns: columns,
            rect: geometry.rect(rows: rows, columns: columns),
            anchor: ReadingAnchor(grid: grid, rows: rows, columns: columns, paneColumns: pane.columns)
        )
    }

    /// A content row's text with each Character anchored to its cell: the row's cells within
    /// the columns the profile reads, with whitespace collapsed as `ReadRow.text` is. When that
    /// is not the profile's text (a profile may return text that is not on screen), the
    /// profile's text without anchors.
    private func mappedText(row: Int, _ readRow: ReadRow) -> MappedText<CellPosition> {
        var cells = MappedText<CellPosition>()
        for (column, character) in grid.characters(row: row, in: readRow.columns) {
            cells.append(character, anchor: CellPosition(row: row, column: column))
        }
        let collapsed = cells.collapsingWhitespace()
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
