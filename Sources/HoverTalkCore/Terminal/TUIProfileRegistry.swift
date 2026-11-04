/// Picks the `TUIProfile` that reads a pane: each profile in `profiles` is asked in order whether
/// it `matches(paneLines:)`, the first match wins, and `fallback` reads every other pane.
///
/// To support another terminal program:
/// 1. Add a type conforming to `TUIProfile` in `Terminal/Profiles/`: detection markers in
///    `matches(paneLines:)`, and chrome and content in `role(of:)`, or in `roles(ofPane:)`
///    when a row's role depends on other rows. Test it against a sanitized fixture.
/// 2. Add an instance to the list in `standard`, before any profile whose markers its screens
///    could also show.
public struct TUIProfileRegistry: Sendable {
    public let profiles: [any TUIProfile]
    public let fallback: any TUIProfile

    public init(profiles: [any TUIProfile], fallback: any TUIProfile = PlainTerminalProfile()) {
        self.profiles = profiles
        self.fallback = fallback
    }

    /// Gentle Shell, OpenCode, then Claude Code; the plain profile for anything else. Gentle
    /// Shell goes first: its markers are glyphs a screen about the other programs does not
    /// show, while their markers are plain text a Gentle Shell conversation can quote.
    public static let standard = TUIProfileRegistry(profiles: [GentleShellProfile(), OpenCodeProfile(), ClaudeCodeProfile()])

    /// The profile for a pane, given every row of the pane cut to its columns.
    public func profile(for paneLines: [String]) -> any TUIProfile {
        profiles.first { $0.matches(paneLines: paneLines) } ?? fallback
    }
}
