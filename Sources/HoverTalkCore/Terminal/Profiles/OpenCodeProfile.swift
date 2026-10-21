/// OpenCode's terminal UI, as captured in `ghostty-tmux-vsplit-opencode.json` (one OpenCode in
/// each pane of a tmux vertical split in Ghostty, 2026-10-16). The rows it relies on:
/// - Messages: user and tool blocks behind a `┃` gutter; assistant text indented without one.
/// - Running tools: a braille spinner or `⏳`, then deeper-indented `↳` detail rows.
/// - A `▣  agent · model` footer after a message, and key-hint rows such as `ctrl+x …`.
/// - The input box: `┃` rows closed by a `╹▀▀▀` border, with the status line below it.
/// - A right sidebar (title, context, tokens, cost, sections) with no separator line.
public struct OpenCodeProfile: TUIProfile {
    public init() {}

    /// At least two kinds of OpenCode marker: the input box border `╹▀▀▀`, the `▣ ` message
    /// footer, the status hints `ctrl+<key> commands` or `esc interrupt`, or an
    /// `OpenCode N.N.N` version label.
    public func matches(paneLines: [String]) -> Bool {
        var kinds = Set<Marker>()
        for line in paneLines {
            kinds.formUnion(Self.markers(in: line))
            if kinds.count >= 2 { return true }
        }
        return false
    }

    public func role(of row: String) -> LineRole {
        roles(ofPane: [row])[0]
    }

    /// Chrome: the input box (the last row starting with `╹▀`, every row below it, and the `┃`
    /// rows directly above it up to the first row without one); running tool blocks (a row
    /// starting with a braille spinner or `⏳`, and the deeper-indented rows right under it);
    /// rows starting with `▣` (the message footer, returned as `.end`) or a key such as
    /// `ctrl+`; rows of only progress glyphs.
    /// Content: the cells left of the sidebar (see `sidebarColumn(in:)`), after a leading `┃`
    /// gutter when there is one, with trailing spaces trimmed.
    public func roles(ofPane paneLines: [String]) -> [LineRole] {
        let grid = TerminalGrid(lines: paneLines)
        guard grid.columns > 0 else { return paneLines.map { _ in .content("") } }
        let readable = 0...((Self.sidebarColumn(in: grid) ?? grid.columns) - 1)
        let rows = (0..<grid.rowCount).map { Row(grid: grid, index: $0, readable: readable) }

        var chrome = rows.map(\.isChromeOnItsOwn)
        if let border = rows.lastIndex(where: \.isInputBoxBorder) {
            for index in border..<rows.count { chrome[index] = true }
            var index = border - 1
            while index >= 0, rows[index].hasGutter {
                chrome[index] = true
                index -= 1
            }
        }
        var toolColumn: Int?
        for (index, row) in rows.enumerated() {
            if row.startsToolBlock {
                toolColumn = row.firstColumn
                chrome[index] = true
            } else if let column = toolColumn, let first = row.firstColumn, first > column {
                chrome[index] = true
            } else {
                toolColumn = nil
            }
        }
        return rows.indices.map { index in
            if rows[index].isMessageFooter { return .end }
            return chrome[index] ? .chrome : rows[index].content(in: grid)
        }
    }

    // MARK: Rows

    private struct Row {
        let index: Int
        let readable: ClosedRange<Int>
        /// The first non-blank cell left of the sidebar.
        let firstColumn: Int?
        /// The row from `firstColumn` to the sidebar; empty when that part is blank.
        let trimmed: String

        init(grid: TerminalGrid, index: Int, readable: ClosedRange<Int>) {
            self.index = index
            self.readable = readable
            firstColumn = grid.contentColumns(row: index, in: readable)?.lowerBound
            trimmed = firstColumn.map { grid.text(row: index, in: $0...readable.upperBound) } ?? ""
        }

        var hasGutter: Bool { trimmed.first == "\u{2503}" }

        var isInputBoxBorder: Bool { trimmed.hasPrefix("\u{2579}\u{2580}") }

        var startsToolBlock: Bool {
            guard let first = trimmed.first else { return false }
            return first == "\u{23F3}" || OpenCodeProfile.isBraille(first)
        }

        /// The `▣ agent · model · time` footer under an answer: the end of that message.
        var isMessageFooter: Bool { trimmed.hasPrefix("\u{25A3}") }

        var isChromeOnItsOwn: Bool {
            trimmed.hasPrefix("\u{25A3}")
                || OpenCodeProfile.keyHintPrefixes.contains { trimmed.hasPrefix($0) }
                || (!trimmed.isEmpty && trimmed.allSatisfy { $0.isWhitespace || OpenCodeProfile.isProgressGlyph($0) })
        }

        func content(in grid: TerminalGrid) -> LineRole {
            let start = hasGutter ? (firstColumn ?? readable.lowerBound) + 1 : readable.lowerBound
            guard start <= readable.upperBound else { return .content("") }
            let columns = start...readable.upperBound
            return .content(grid.text(row: index, in: columns).withoutTrailingWhitespace, columns: columns)
        }
    }

    static let keyHintPrefixes = ["ctrl+", "alt+", "shift+", "esc "]

    static func isBraille(_ character: Character) -> Bool {
        character.unicodeScalars.first.map { (0x2800...0x28FF).contains($0.value) } ?? false
    }

    /// Braille spinners and the `⬝ ■ ▪` progress dots.
    static func isProgressGlyph(_ character: Character) -> Bool {
        isBraille(character) || ["\u{2B1D}", "\u{25A0}", "\u{25AA}"].contains(character)
    }

    // MARK: Detection

    private enum Marker {
        case inputBoxBorder, messageFooter, statusHints, versionLabel
    }

    private static func markers(in line: String) -> Set<Marker> {
        var found = Set<Marker>()
        if line.contains("\u{2579}\u{2580}\u{2580}\u{2580}") { found.insert(.inputBoxBorder) }
        if line.contains("\u{25A3} ") { found.insert(.messageFooter) }
        if line.contains("esc interrupt") || hasCommandsHint(line) { found.insert(.statusHints) }
        if hasVersionLabel(line) { found.insert(.versionLabel) }
        return found
    }

    /// `ctrl+`, one key, then ` commands`.
    private static func hasCommandsHint(_ line: String) -> Bool {
        var rest = Substring(line)
        while let range = rest.firstRange(of: "ctrl+") {
            rest = rest[range.upperBound...]
            if rest.dropFirst().hasPrefix(" commands") { return true }
        }
        return false
    }

    /// `OpenCode ` followed by three dot-separated runs of ASCII digits, such as `1.2.3`.
    private static func hasVersionLabel(_ line: String) -> Bool {
        var rest = Substring(line)
        while let range = rest.firstRange(of: "OpenCode ") {
            rest = rest[range.upperBound...]
            let parts = rest.prefix { !$0.isWhitespace }.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) {
                return true
            }
        }
        return false
    }

    // MARK: Sidebar

    /// Blank cells required between the message area and the sidebar.
    static let sidebarGap = 3

    /// The first column of OpenCode's right sidebar in a pane, or `nil` when it shows none.
    ///
    /// The sidebar has no separator line, so it is found from the data: the rightmost column C
    /// in the right half of the pane such that
    /// - at least 3 rows have text starting exactly at C after `sidebarGap` blank cells,
    /// - those `sidebarGap` cells are blank on all but a tenth of the rows from the first to
    ///   the last row with text at or after C, and
    /// - the text at or after C on those rows shows at least two kinds of sidebar marker: the
    ///   word `Context`, the word `tokens`, a `$` amount, a `%` figure, or a `▼`/`▶` toggle.
    static func sidebarColumn(in grid: TerminalGrid) -> Int? {
        guard grid.rowCount >= 3, grid.columns > sidebarGap else { return nil }
        let last = grid.columns - 1
        let rows = 0..<grid.rowCount
        // Each cell is looked up once; the checks below repeat for every candidate column.
        let blank = rows.map { row in (0...last).map { grid.character(row: row, column: $0)?.isWhitespace ?? true } }
        let lastText = blank.map { $0.lastIndex(of: false) ?? -1 }
        func isBlank(_ row: Int, _ columns: ClosedRange<Int>) -> Bool {
            columns.allSatisfy { blank[row][$0] }
        }

        for column in stride(from: last, through: max(grid.columns / 2, sidebarGap), by: -1) {
            let gap = (column - sidebarGap)...(column - 1)
            let starts = rows.filter { !blank[$0][column] && isBlank($0, gap) }
            guard starts.count >= 3 else { continue }
            let withText = rows.filter { lastText[$0] >= column }
            guard let top = withText.first, let bottom = withText.last else { continue }
            let extent = top...bottom
            guard extent.filter({ !isBlank($0, gap) }).count * 10 <= extent.count else { continue }
            if sidebarMarkerKinds(in: extent.map { grid.text(row: $0, in: column...last) }) >= 2 {
                return column
            }
        }
        return nil
    }

    private static func sidebarMarkerKinds(in rows: [String]) -> Int {
        let text = rows.joined(separator: "\n")
        let pairs = Array(zip(text, text.dropFirst()))
        let kinds = [
            text.contains("Context"),
            text.contains("tokens"),
            pairs.contains { $0 == "$" && $1.isASCII && $1.isNumber },
            pairs.contains { $0.isASCII && $0.isNumber && $1 == "%" },
            text.contains("\u{25BC}") || text.contains("\u{25B6}"),
        ]
        return kinds.filter { $0 }.count
    }
}
