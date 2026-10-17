import CoreGraphics

/// A paragraph found on a terminal screen.
public struct TerminalTextBlock: Equatable, Sendable {
    /// The paragraph's rows joined into text to read.
    public let text: String
    public let rows: ClosedRange<Int>
    /// From the leftmost to the rightmost non-blank cell of the paragraph's rows, inside its pane.
    public let columns: ClosedRange<Int>
    /// `rows` × `columns` in the coordinates of the frame passed to the provider.
    public let rect: CGRect

    public init(text: String, rows: ClosedRange<Int>, columns: ClosedRange<Int>, rect: CGRect) {
        self.text = text
        self.rows = rows
        self.columns = columns
        self.rect = rect
    }
}

/// Finds the paragraph under a point on a terminal screen given as rows of text.
public enum TerminalGridProvider {
    /// Maps `point` (in the coordinates of `frame`, normally AX) to a cell and its pane, then
    /// expands the pointed row to the run of adjacent rows of that pane that `profile` calls
    /// non-blank content. Returns `nil` when the point is outside `frame`, on a pane divider,
    /// or on a row that is blank or chrome.
    ///
    /// Rows are joined with one space, or with a newline before a row that starts with a list
    /// marker (see `startsWithListMarker`), because `SentenceSplitter` splits at every newline
    /// first, so the previous item ends there. Whitespace runs inside a row become one space.
    public static func block(
        at point: CGPoint,
        frame: CGRect,
        lines: [String],
        profile: any TUIProfile = PlainTerminalProfile()
    ) -> TerminalTextBlock? {
        let grid = TerminalGrid(lines: lines)
        let geometry = TerminalGeometry(frame: frame, rows: grid.rowCount, columns: grid.columns)
        guard let cell = geometry.cell(at: point),
              let pane = PaneLayout.detect(grid).first(where: { $0.contains(cell) })
        else { return nil }

        let paneRows = Array(pane.rows)
        let texts: [String?] = paneRows.map { row in
            guard case let .content(content) = profile.role(of: grid.text(row: row, in: pane.columns)) else { return nil }
            let collapsed = collapsingWhitespace(content)
            return collapsed.isEmpty ? nil : collapsed
        }
        let pointed = cell.row - pane.rows.lowerBound
        guard texts[pointed] != nil else { return nil }

        var first = pointed
        var last = pointed
        while first > 0, texts[first - 1] != nil { first -= 1 }
        while last < texts.count - 1, texts[last + 1] != nil { last += 1 }
        let rows = paneRows[first]...paneRows[last]

        let spans = rows.compactMap { grid.contentColumns(row: $0, in: pane.columns) }
        // Defensive: the plain profile's content is the raw row, so a non-blank content row
        // always has a non-blank cell; a profile that invents text could break that.
        guard let left = spans.map(\.lowerBound).min(), let right = spans.map(\.upperBound).max() else { return nil }
        let columns = left...right

        return TerminalTextBlock(
            text: joined(texts[first...last].compactMap { $0 }),
            rows: rows,
            columns: columns,
            rect: geometry.rect(rows: rows, columns: columns)
        )
    }

    private static func collapsingWhitespace(_ row: String) -> String {
        row.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func joined(_ rows: [String]) -> String {
        var text = ""
        for (index, row) in rows.enumerated() {
            if index > 0 { text += startsWithListMarker(row) ? "\n" : " " }
            text += row
        }
        return text
    }

    /// `-`, `*` or `•`; one to three ASCII digits and `.` or `)`; or one ASCII letter and `)`;
    /// after any indentation, and followed by whitespace or the end of the row.
    static func startsWithListMarker(_ line: String) -> Bool {
        let row = line.drop(while: \.isWhitespace)
        guard let first = row.first else { return false }
        let rest: Substring
        if first == "-" || first == "*" || first == "\u{2022}" {
            rest = row.dropFirst()
        } else if first.isASCII, first.isWholeNumber {
            let digits = row.prefix { $0.isASCII && $0.isWholeNumber }
            let afterDigits = row.dropFirst(digits.count)
            guard digits.count <= 3, let mark = afterDigits.first, mark == "." || mark == ")" else { return false }
            rest = afterDigits.dropFirst()
        } else if first.isASCII, first.isLetter {
            let afterLetter = row.dropFirst()
            guard afterLetter.first == ")" else { return false }
            rest = afterLetter.dropFirst()
        } else {
            return false
        }
        return rest.first.map(\.isWhitespace) ?? true
    }
}
