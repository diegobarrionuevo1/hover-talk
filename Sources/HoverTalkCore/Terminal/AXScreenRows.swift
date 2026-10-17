/// Splits a terminal text area's `AXValue` into screen rows.
///
/// Ghostty separates rows with `\n` and pads every row to the screen width, but puts no `\n`
/// after a soft-wrapped row, so a line that wrapped over k rows arrives as one string of
/// k × width cells. Observed with `HoverTalkCapture probe` on 2026-10-17 (Ghostty 1.3.1): 38
/// lines of 209 cells and one of 1463 = 7 × 209 cells, on the 45-row screen of the earlier probes.
public enum AXScreenRows {
    /// The screen width is the most common non-zero line width in cells
    /// (`TerminalGrid.cellWidth(of:)`), provided more than half of the non-empty lines have it.
    /// A line whose width is an exact multiple (two or more) of it is cut into rows of that
    /// width; every other line is one row. Without such a width, as for unpadded rows from
    /// `tmux capture-pane`, every line is one row.
    public static func split(_ value: String) -> [String] {
        let lines = value.components(separatedBy: "\n")
        let widths = lines.map(cellCount)
        let nonEmpty = widths.filter { $0 > 0 }
        let counts = Dictionary(grouping: nonEmpty, by: { $0 }).mapValues(\.count)
        guard let mode = counts.max(by: { $0.value < $1.value }), mode.value * 2 > nonEmpty.count else { return lines }

        let width = mode.key
        return zip(lines, widths).flatMap { line, lineWidth in
            lineWidth > width && lineWidth.isMultiple(of: width) ? rows(of: line, width: width) : [line]
        }
    }

    private static func cellCount(_ line: String) -> Int {
        line.reduce(0) { $0 + TerminalGrid.cellWidth(of: $1) }
    }

    /// Cuts a line into consecutive rows of at most `width` cells; a wide character that does
    /// not fit at the end of a row starts the next one.
    private static func rows(of line: String, width: Int) -> [String] {
        var rows: [String] = []
        var row = ""
        var cells = 0
        for character in line {
            let characterWidth = TerminalGrid.cellWidth(of: character)
            if cells + characterWidth > width {
                rows.append(row)
                row = ""
                cells = 0
            }
            row.append(character)
            cells += characterWidth
        }
        rows.append(row)
        return rows
    }
}
