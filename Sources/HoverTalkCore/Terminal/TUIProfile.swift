/// What one terminal row is, as far as reading aloud goes.
public enum LineRole: Equatable, Sendable {
    /// Text to read, as cleaned by the profile. Blank content ends a paragraph.
    ///
    /// `columns` are the pane-relative cells the text comes from: `TerminalGridProvider` reads
    /// the row only when the pointer is inside them, and highlights only their non-blank cells.
    /// `nil` means the whole row.
    case content(String, columns: ClosedRange<Int>? = nil)
    /// Decoration such as borders, footers or status lines: never read, and ends a paragraph.
    case chrome
}

/// Knowledge about one terminal program's screen layout, such as a plain shell's or OpenCode's.
public protocol TUIProfile: Sendable {
    /// Whether this profile fits a pane, given every row of the pane cut to its columns.
    /// `TUIProfileRegistry` calls it to pick the profile for each pane.
    func matches(paneLines: [String]) -> Bool

    /// The role of one row, cut to its pane's columns, judged without the rest of the pane.
    func role(of row: String) -> LineRole

    /// The roles of every row of a pane, in order, one per row; `TerminalGridProvider` calls it
    /// once per read. A profile overrides it when a row's role depends on other rows, such as
    /// the rows of an input box or a column shared by every row. The default judges each row
    /// alone with `role(of:)`.
    func roles(ofPane paneLines: [String]) -> [LineRole]
}

extension TUIProfile {
    public func roles(ofPane paneLines: [String]) -> [LineRole] {
        paneLines.map(role(of:))
    }
}

/// Any terminal: every row is content, with trailing whitespace trimmed.
public struct PlainTerminalProfile: TUIProfile {
    public init() {}

    public func matches(paneLines: [String]) -> Bool {
        true
    }

    public func role(of row: String) -> LineRole {
        .content(row.withoutTrailingWhitespace)
    }
}

extension StringProtocol {
    var withoutTrailingWhitespace: String {
        var text = Substring(self)
        while text.last?.isWhitespace == true {
            text.removeLast()
        }
        return String(text)
    }
}
