/// How much a click reads while picking.
public enum ReadingMode: String, CaseIterable, Equatable, Sendable {
    /// Only the paragraph under the pointer.
    case paragraph
    /// The paragraph under the pointer, then every paragraph below it in its pane, as
    /// `ParsedScreen.block(at:mode:)` documents it.
    case continuous

    /// The mode until the user picks one.
    public static let `default`: ReadingMode = .continuous

    /// The other mode.
    public var toggled: ReadingMode {
        self == .paragraph ? .continuous : .paragraph
    }
}
