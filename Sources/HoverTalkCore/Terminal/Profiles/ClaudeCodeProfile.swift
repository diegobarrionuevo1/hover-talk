/// Claude Code's terminal UI, modelled on its well-known layout in the hand-written fixture
/// `synthetic-claude-code.json`; not yet checked against a live capture. The rows it relies on:
/// - Assistant text starts with `⏺ ` and continues with a two-space indent.
/// - Tool calls are `⏺ Name(args)`, followed by `⎿` result rows and their deeper indent.
/// - Echoed user prompts start with `> `.
/// - Rounded boxes (`╭─╮`, `│ … │`, `╰─╯`) for the welcome banner and the input box, then
///   hint rows such as `? for shortcuts`, and a status row containing `esc to interrupt`.
///
/// In this layout the box's `│` is no pane divider: it is only on the box rows, and
/// `PaneLayout` splits only at a divider on every row of a pane.
public struct ClaudeCodeProfile: TUIProfile {
    public init() {}

    /// A rounded box (a row starting with `╭` and one with `╰`) together with a `⏺` row or the
    /// `? for shortcuts` hint.
    public func matches(paneLines: [String]) -> Bool {
        let starts = paneLines.map { $0.drop(while: \.isWhitespace) }
        let hasBox = starts.contains { $0.hasPrefix("\u{256D}") } && starts.contains { $0.hasPrefix("\u{2570}") }
        let hasMark = starts.contains { $0.hasPrefix("\u{23FA}") } || starts.contains { $0.hasPrefix("? for shortcuts") }
        return hasBox && hasMark
    }

    public func role(of row: String) -> LineRole {
        roles(ofPane: [row])[0]
    }

    /// Chrome: box rows (starting with `╭`, `│` or `╰`), hint and status rows, and tool blocks
    /// (a tool call or a `⎿` row, and every row after it up to a blank row or the next `⏺` or
    /// `>` row). Content: other rows, without a leading `⏺ ` or `> ` mark.
    public func roles(ofPane paneLines: [String]) -> [LineRole] {
        let grid = TerminalGrid(lines: paneLines)
        guard grid.columns > 0 else { return paneLines.map { _ in .content("") } }
        let all = 0...(grid.columns - 1)
        var inToolBlock = false

        return (0..<grid.rowCount).map { row in
            guard let first = grid.contentColumns(row: row, in: all)?.lowerBound else {
                inToolBlock = false
                return .content("")
            }
            let text = grid.text(row: row, in: first...all.upperBound)
            if Self.boxEdges.contains(where: { text.hasPrefix($0) }) || Self.isHint(text) {
                inToolBlock = false
                return .chrome
            }
            if text.hasPrefix("\u{23BF}") || (text.hasPrefix("\u{23FA}") && Self.isToolCall(text)) {
                inToolBlock = true
                return .chrome
            }
            if text.hasPrefix("\u{23FA}") || text.hasPrefix("> ") {
                inToolBlock = false
                return Self.content(of: row, in: grid, from: first + 1)
            }
            return inToolBlock ? .chrome : Self.content(of: row, in: grid, from: 0)
        }
    }

    private static let boxEdges = ["\u{256D}", "\u{2502}", "\u{2570}"]

    private static func isHint(_ text: String) -> Bool {
        text.hasPrefix("? for shortcuts") || text.contains("esc to interrupt")
    }

    /// `⏺ `, then a capitalised name directly followed by `(`, such as `⏺ Read(file)`.
    private static func isToolCall(_ text: String) -> Bool {
        let rest = text.dropFirst().drop(while: \.isWhitespace)
        let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return name.first?.isUppercase == true && rest.dropFirst(name.count).first == "("
    }

    /// The row from `column` to the end of the pane. After a mark (`column` > 0), from the first
    /// non-blank cell at or after `column`, so the space after the mark is left out too.
    private static func content(of row: Int, in grid: TerminalGrid, from column: Int) -> LineRole {
        let end = grid.columns - 1
        guard column <= end else { return .content("") }
        let start = column == 0 ? 0 : (grid.contentColumns(row: row, in: column...end)?.lowerBound ?? column)
        let columns = start...end
        return .content(grid.text(row: row, in: columns).withoutTrailingWhitespace, columns: columns)
    }
}
