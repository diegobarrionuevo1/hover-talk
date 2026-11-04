/// Finds out, from tmux itself, whether a terminal screen has a tmux status bar and on which
/// edge. The text of a window without splits has no divider that gives the bar away, so
/// `PaneLayout` cannot tell the bar from the program's first row.
public enum TmuxClients {
    /// The format to pass to `tmux list-clients -F`, which `statusBar(in:columns:rows:)` reads.
    public static let listFormat = "#{client_width} #{client_height} #{status} #{status-position}"

    /// The status bar edge of the attached tmux client whose size is exactly `columns` × `rows`
    /// (the screen size, status row included). `nil` when no client has that size, when its
    /// status bar is off or has more than one row, or when matching clients disagree: the
    /// caller then reads the screen without a hint, as it always did.
    public static func statusBar(in listClientsOutput: String, columns: Int, rows: Int) -> StatusEdge? {
        var edges = Set<StatusEdge?>()
        for line in listClientsOutput.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ")
            guard fields.count == 4, Int(fields[0]) == columns, Int(fields[1]) == rows else { continue }
            edges.insert(fields[2] == "on" ? StatusEdge(position: fields[3]) : nil)
        }
        guard edges.count == 1, let edge = edges.first else { return nil }
        return edge
    }
}

private extension StatusEdge {
    init?(position: Substring) {
        switch position {
        case "top": self = .top
        case "bottom": self = .bottom
        default: return nil
        }
    }
}
