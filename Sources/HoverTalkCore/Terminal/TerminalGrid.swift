/// A terminal screen as a rectangular grid of cells, built from its rows of text.
///
/// Each Character takes one cell, or two when `cellWidth(of:)` says it is wide; the second
/// cell of a wide Character is a continuation cell. Rows shorter than the widest one are
/// padded with spaces: `tmux capture-pane -p` drops trailing spaces, Ghostty's AX value keeps them.
public struct TerminalGrid: Equatable, Sendable {
    public let rowCount: Int
    /// The widest row, in cells.
    public let columns: Int
    private let cells: [[Cell]]

    private struct Cell: Equatable, Sendable {
        let character: Character
        let isContinuation: Bool
    }

    public init(lines: [String]) {
        var rows = lines.map { line in
            line.flatMap { character -> [Cell] in
                let first = Cell(character: character, isContinuation: false)
                return Self.cellWidth(of: character) == 2 ? [first, Cell(character: character, isContinuation: true)] : [first]
            }
        }
        let width = rows.map(\.count).max() ?? 0
        for index in rows.indices {
            rows[index] += Array(repeating: Cell(character: " ", isContinuation: false), count: width - rows[index].count)
        }
        cells = rows
        rowCount = rows.count
        columns = width
    }

    /// The Character occupying a cell; a wide Character is returned for both of its cells.
    /// `nil` outside the grid.
    public func character(row: Int, column: Int) -> Character? {
        guard cells.indices.contains(row), (0..<columns).contains(column) else { return nil }
        return cells[row][column].character
    }

    /// The text of a row within a column range, clamped to the grid. A wide Character belongs
    /// to the range that holds its first cell.
    public func text(row: Int, in columnRange: ClosedRange<Int>) -> String {
        guard let range = clamped(columnRange), cells.indices.contains(row) else { return "" }
        return String(cells[row][range].filter { !$0.isContinuation }.map(\.character))
    }

    /// The Characters `text(row:in:)` reads, each with the column of its first cell.
    public func characters(row: Int, in columnRange: ClosedRange<Int>) -> [(column: Int, character: Character)] {
        guard let range = clamped(columnRange), cells.indices.contains(row) else { return [] }
        return range.compactMap { column in
            let cell = cells[row][column]
            return cell.isContinuation ? nil : (column, cell.character)
        }
    }

    /// The columns from the first to the last non-whitespace cell of a row within a range
    /// (a wide Character's continuation cell counts), or `nil` when that part of the row is blank.
    public func contentColumns(row: Int, in columnRange: ClosedRange<Int>) -> ClosedRange<Int>? {
        guard let range = clamped(columnRange), cells.indices.contains(row) else { return nil }
        let content = range.filter { !cells[row][$0].character.isWhitespace }
        guard let first = content.first, let last = content.last else { return nil }
        return first...last
    }

    private func clamped(_ range: ClosedRange<Int>) -> ClosedRange<Int>? {
        let lower = max(range.lowerBound, 0)
        let upper = min(range.upperBound, columns - 1)
        return lower <= upper ? lower...upper : nil
    }

    /// Cells a Character takes on a terminal: 2 when its first scalar has default emoji
    /// presentation or falls in a main East Asian Wide/Fullwidth block, otherwise 1.
    /// An approximation: the wide blocks are not the full `EastAsianWidth.txt` table, and
    /// variation selectors (U+FE0F) are not considered.
    public static func cellWidth(of character: Character) -> Int {
        guard let scalar = character.unicodeScalars.first else { return 1 }
        if scalar.properties.isEmojiPresentation { return 2 }
        return wideBlocks.contains { $0.contains(scalar.value) } ? 2 : 1
    }

    /// Hangul Jamo, the angle brackets U+2329/U+232A, CJK radicals to Yi (except U+303F),
    /// Hangul syllables, CJK compatibility ideographs, vertical and compatibility forms,
    /// fullwidth forms, and CJK planes 2 and 3.
    private static let wideBlocks: [ClosedRange<UInt32>] = [
        0x1100...0x115F, 0x2329...0x232A, 0x2E80...0x303E, 0x3040...0xA4CF, 0xAC00...0xD7A3,
        0xF900...0xFAFF, 0xFE10...0xFE19, 0xFE30...0xFE6F, 0xFF00...0xFF60, 0xFFE0...0xFFE6,
        0x20000...0x2FFFD, 0x30000...0x3FFFD,
    ]
}
