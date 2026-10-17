/// What one terminal row is, as far as reading aloud goes.
public enum LineRole: Equatable, Sendable {
    /// Text to read, as cleaned by the profile. Blank content ends a paragraph.
    case content(String)
    /// Decoration such as borders, footers or status lines: never read, and ends a paragraph.
    case chrome
}

/// Knowledge about one terminal program's screen layout, such as a plain shell's or OpenCode's.
public protocol TUIProfile: Sendable {
    /// Whether this profile fits a pane, given every row of the pane cut to its columns.
    /// `TerminalGridProvider` does not call it; it is the hook for picking a profile per pane.
    func matches(paneLines: [String]) -> Bool

    /// The role of one row, cut to its pane's columns.
    func role(of row: String) -> LineRole
}

/// Any terminal: every row is content, with trailing whitespace trimmed.
public struct PlainTerminalProfile: TUIProfile {
    public init() {}

    public func matches(paneLines: [String]) -> Bool {
        true
    }

    public func role(of row: String) -> LineRole {
        var text = Substring(row)
        while text.last?.isWhitespace == true {
            text.removeLast()
        }
        return .content(String(text))
    }
}
