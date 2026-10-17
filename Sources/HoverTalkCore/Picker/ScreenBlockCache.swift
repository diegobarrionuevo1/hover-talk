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
    /// How many times a screen was parsed; for tests and diagnostics.
    public private(set) var parseCount = 0
    private var key: Key?
    private var parsed: ParsedScreen?

    public init(registry: TUIProfileRegistry = .standard) {
        self.registry = registry
    }

    /// The parsed screen for a terminal text area's `AXValue`, split into rows by
    /// `AXScreenRows.split(_:)`, and its frame in AX coordinates.
    public mutating func screen(value: String, frame: CGRect) -> ParsedScreen {
        let key = Key(value: value, frame: frame)
        if key == self.key, let parsed { return parsed }
        let screen = ParsedScreen(lines: AXScreenRows.split(value), frame: frame, registry: registry)
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
