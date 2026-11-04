import CoreGraphics

/// Keeps the last parsed terminal screen, so moving the pointer over a screen that has not
/// changed does not parse it again. The key is the text area's AX value and frame: a change
/// to either parses again.
public struct ScreenBlockCache: Sendable {
    private struct Key: Equatable, Sendable {
        let value: String
        let frame: CGRect
    }

    public let registry: TUIProfileRegistry
    /// The tmux status bar edge for a screen of `columns` × `rows` cells, asked once per parse;
    /// `nil` when unknown (see `TmuxClients`).
    public let statusBar: @Sendable (_ columns: Int, _ rows: Int) -> StatusEdge?
    /// How many times a screen was parsed; for tests and diagnostics.
    public private(set) var parseCount = 0
    private var key: Key?
    private var parsed: ParsedScreen?

    public init(
        registry: TUIProfileRegistry = .standard,
        statusBar: @escaping @Sendable (_ columns: Int, _ rows: Int) -> StatusEdge? = { _, _ in nil }
    ) {
        self.registry = registry
        self.statusBar = statusBar
    }

    /// The parsed screen for a terminal text area's `AXValue`, split into rows by
    /// `AXScreenRows.split(_:)`, and its frame in AX coordinates.
    public mutating func screen(value: String, frame: CGRect) -> ParsedScreen {
        let key = Key(value: value, frame: frame)
        if key == self.key, let parsed { return parsed }
        let lines = AXScreenRows.split(value)
        let size = TerminalGrid(lines: lines)
        let screen = ParsedScreen(
            lines: lines, frame: frame, registry: registry,
            statusBar: statusBar(size.columns, size.rowCount)
        )
        self.key = key
        parsed = screen
        parseCount += 1
        return screen
    }

    /// The block under `point` (AX coordinates) on that screen.
    public mutating func block(at point: CGPoint, value: String, frame: CGRect) -> TerminalTextBlock? {
        screen(value: value, frame: frame).block(at: point)
    }
}
