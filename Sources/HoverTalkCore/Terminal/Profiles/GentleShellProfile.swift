/// Gentle Shell's terminal UI (a Pi-based coding agent), as captured in
/// `ghostty-tmux-gentle-shell.json` (three Gentle Shell panes in a tmux split in Ghostty,
/// 2026-11-04). The rows it relies on:
/// - A header and a footer row with a context gauge (`ctx ▰▰▱▱▱▱▱▱ 12% ⟡ $0.000`), and a `▔▔▔`
///   rule under the header.
/// - Messages: assistant text indented by one space, no gutter.
/// - Tool calls: a ` $ command` row, wrapped rows under it, and an `Elapsed` row after a blank.
/// - The editor, the todo widget and the status line: rows behind a `▎` gutter.
/// - A floating `↓ Jump to latest message · Ctrl+End` pill drawn over a message row, hiding
///   part of it.
/// - In wide panes, a right sidebar: rows behind a `▎` gutter in the first layout captured, and
///   sections whose titles start with `▾` or `▸` (`▾ AGENTS`, `▾ CHANGES`) in later versions,
///   which also draw no `▔▔▔` rule and no `▎` gutters in the conversation.
/// - The editor: a frame row `─ ✿ waiting for input ────`, the `›` prompt under it, and the
///   footer, in later versions.
///
/// Detection and chrome use glyphs only, not words, so they hold for the sanitized fixtures
/// and for other product names and languages.
public struct GentleShellProfile: TUIProfile {
    public init() {}

    /// At least two kinds of Gentle Shell marker: a context gauge, a `▔▔▔` rule row, two rows
    /// behind a `▎` gutter, an editor frame row (`─ ✿ label ───`), or a sidebar of `▾`/`▸`
    /// section titles.
    public func matches(paneLines: [String]) -> Bool {
        var kinds = Set<Marker>()
        var gutterRows = 0
        for line in paneLines {
            let row = Self.trimmed(line)
            if Self.hasGauge(row) { kinds.insert(.gauge) }
            if Self.isRule(row) { kinds.insert(.rule) }
            if Self.isEditorFrame(row) { kinds.insert(.editorFrame) }
            if row.first == Self.gutter { gutterRows += 1 }
            if gutterRows >= 2 { kinds.insert(.gutter) }
            if kinds.count >= 2 { return true }
        }
        return kinds.count == 1 && Self.toggleSidebarColumn(in: TerminalGrid(lines: paneLines)) != nil
    }

    public func role(of row: String) -> LineRole {
        roles(ofPane: [row])[0]
    }

    /// Chrome: rows behind a `▎` gutter, `▔` rules, rows with a context gauge, rows starting
    /// with the `✿` or `✎` marks (header and footer), key hints such as `ctrl+`, `Elapsed` and
    /// `Took` rows, echo rows of memory and tool calls (starting with `🧠` or `↳`), tool blocks
    /// (a row starting with `$ ` and every row after it up to a blank row), and the editor: the
    /// last frame row (`─ ✿ label ───`) and every row below it.
    /// Content: every other row, cut left of the sidebar (see `sidebarColumn(in:)`), with
    /// trailing spaces trimmed. On a row crossed by the jump pill only the longer side of the
    /// pill is read, since the pill covers the rest. A message that merely quotes the pill's
    /// words is an ordinary row: only the full text with its `· Ctrl+End` counts.
    public func roles(ofPane paneLines: [String]) -> [LineRole] {
        let grid = TerminalGrid(lines: paneLines)
        guard grid.columns > 0 else { return paneLines.map { _ in .content("") } }
        let readable = 0...((Self.sidebarColumn(in: grid) ?? grid.columns) - 1)

        let editorStart = paneLines.indices.last { Self.isEditorFrame(Self.trimmed(grid.text(row: $0, in: 0...(grid.columns - 1)))) }

        var inToolBlock = false
        return paneLines.indices.map { index in
            if let editorStart, index >= editorStart { return .chrome }
            var readable = readable
            if let pill = Self.jumpPillSide(row: index, in: grid, readable: readable) {
                // Only the pill is on the row, or nothing readable beside it.
                guard let side = pill else { return .chrome }
                readable = side
            }
            let row = Self.trimmed(grid.text(row: index, in: readable))
            if row.isEmpty {
                inToolBlock = false
                return .content("")
            }
            if row.hasPrefix("$ ") { inToolBlock = true }
            if inToolBlock || Self.isChrome(row) { return .chrome }
            return .content(grid.text(row: index, in: readable).withoutTrailingWhitespace, columns: readable)
        }
    }

    // MARK: Rows

    static let gutter: Character = "\u{258E}"

    private static func trimmed(_ row: String) -> String {
        String(row.drop(while: \.isWhitespace)).withoutTrailingWhitespace
    }

    private static func isChrome(_ row: String) -> Bool {
        guard let first = row.first else { return false }
        return first == gutter
            || isRule(row)
            || hasGauge(row)
            || first == "\u{273F}" || first == "\u{270E}"
            || first == "\u{1F9E0}" || first == "\u{21B3}"
            || OpenCodeProfile.keyHintPrefixes.contains { row.hasPrefix($0) }
            || isElapsed(row)
    }

    static let jumpPill = "\u{2193} Jump to latest message \u{00B7} Ctrl+End"

    /// For a row crossed by the jump pill: the columns of the longer side of the pill, or `.some(nil)`
    /// when neither side has text. `nil` when the row has no pill. The pill is a floating
    /// overlay: the cells under it are lost, so only one side can be read as a single run.
    private static func jumpPillSide(row: Int, in grid: TerminalGrid, readable: ClosedRange<Int>) -> ClosedRange<Int>?? {
        let cells = grid.characters(row: row, in: readable)
        let text = String(cells.map(\.character))
        guard let found = text.range(of: jumpPill) else { return nil }
        let start = text.distance(from: text.startIndex, to: found.lowerBound)
        let end = text.distance(from: text.startIndex, to: found.upperBound) - 1
        let left = start > 0 ? readable.lowerBound...(cells[start].column - 1) : nil
        let right = end + 1 < cells.count ? (cells[end + 1].column)...readable.upperBound : nil
        func weight(_ range: ClosedRange<Int>?) -> Int {
            range.map { grid.text(row: row, in: $0).filter { !$0.isWhitespace }.count } ?? 0
        }
        let longer = weight(right) > weight(left) ? right : left
        return .some(weight(longer) > 0 ? longer : nil)
    }

    /// `▔▔▔▔`: a row of at least ten `▔` and nothing else.
    private static func isRule(_ row: String) -> Bool {
        row.count >= 10 && row.allSatisfy { $0 == "\u{2594}" }
    }

    /// The editor's top row: `─`, a space, a label (starting with the `✿` or `✾` mark) and a run
    /// of at least six `─`. A row of `─` alone is not one.
    private static func isEditorFrame(_ row: String) -> Bool {
        guard row.hasPrefix("\u{2500} "), row.filter({ $0 == "\u{2500}" }).count >= 6 else { return false }
        return row.dropFirst(2).first.map { $0 == "\u{273F}" || $0 == "\u{273E}" } ?? false
    }

    /// A run of at least six gauge cells, `▰` or `▱`.
    private static func hasGauge(_ row: String) -> Bool {
        var run = 0
        for character in row {
            run = character == "\u{25B0}" || character == "\u{25B1}" ? run + 1 : 0
            if run >= 6 { return true }
        }
        return false
    }

    /// `Elapsed` or `Took`, a space and a digit: the line after a tool call.
    private static func isElapsed(_ row: String) -> Bool {
        for word in ["Elapsed ", "Took "] where row.hasPrefix(word) {
            return row.dropFirst(word.count).first?.isNumber ?? false
        }
        return false
    }

    // MARK: Detection

    private enum Marker {
        case gauge, rule, gutter, editorFrame
    }

    // MARK: Sidebar

    /// Blank cells required between the message area and the sidebar.
    static let sidebarGap = 3

    /// The column of the `▎` gutter of Gentle Shell's right sidebar in a pane, or `nil` when it
    /// shows none: a column in the right half of the pane where at least three rows have a `▎`
    /// after `sidebarGap` blank cells. The editor's gutter sits at the left edge, so it never
    /// counts. When several columns qualify, the one with the most rows wins, then the leftmost.
    static func sidebarColumn(in grid: TerminalGrid) -> Int? {
        gutterSidebarColumn(in: grid) ?? toggleSidebarColumn(in: grid)
    }

    /// The column of the `▾` or `▸` that starts the section titles of the sidebar of later
    /// versions (`▾ AGENTS`): a column in the right half where at least two rows have one,
    /// with a blank cell before it and a space after it. OpenCode's `▼` and `▶` toggles are a
    /// different glyph and never count. The leftmost such column wins.
    static func toggleSidebarColumn(in grid: TerminalGrid) -> Int? {
        guard grid.columns > 2 else { return nil }
        var rowsByColumn: [Int: Int] = [:]
        for row in 0..<grid.rowCount {
            for (column, character) in grid.characters(row: row, in: (grid.columns / 2)...(grid.columns - 1))
            where (character == "\u{25BE}" || character == "\u{25B8}") && column >= 1
                && grid.character(row: row, column: column - 1)?.isWhitespace == true
                && grid.character(row: row, column: column + 1)?.isWhitespace == true {
                rowsByColumn[column, default: 0] += 1
            }
        }
        return rowsByColumn.filter { $0.value >= 2 }.keys.min()
    }

    private static func gutterSidebarColumn(in grid: TerminalGrid) -> Int? {
        guard grid.columns > sidebarGap else { return nil }
        var rowsByColumn: [Int: Int] = [:]
        for row in 0..<grid.rowCount {
            for (column, character) in grid.characters(row: row, in: (grid.columns / 2)...(grid.columns - 1))
            where character == gutter && column >= sidebarGap
                && grid.text(row: row, in: (column - sidebarGap)...(column - 1)).allSatisfy(\.isWhitespace) {
                rowsByColumn[column, default: 0] += 1
            }
        }
        return rowsByColumn.filter { $0.value >= 3 }
            .max { ($0.value, -$0.key) < ($1.value, -$1.key) }?.key
    }
}
