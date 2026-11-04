import Testing
@testable import HoverTalkCore

/// Matches when `accepts` is true; every row is the content `name`, so a test can tell profiles apart.
private struct NamedProfile: TUIProfile {
    let name: String
    let accepts: Bool

    func matches(paneLines: [String]) -> Bool { accepts }

    func role(of row: String) -> LineRole { .content(name) }
}

@Suite("TUIProfileRegistry")
struct TUIProfileRegistryTests {
    @Test("The standard registry reads both vsplit panes with OpenCode, the synthetic screen with Claude Code, and fish with the plain profile")
    func standardPicks() throws {
        let registry = TUIProfileRegistry.standard
        let vsplit = try FixtureScreen(VSplitPanes.name)

        #expect(registry.profile(for: vsplit.paneLines(rows: VSplitPanes.rows, columns: VSplitPanes.left)) is OpenCodeProfile)
        #expect(registry.profile(for: vsplit.paneLines(rows: VSplitPanes.rows, columns: VSplitPanes.right)) is OpenCodeProfile)
        #expect(registry.profile(for: try ScreenFixture.load("synthetic-claude-code").lines) is ClaudeCodeProfile)
        let gentleShell = try FixtureScreen("ghostty-tmux-gentle-shell")
        #expect(registry.profile(for: gentleShell.paneLines(rows: 1...42, columns: 0...44)) is GentleShellProfile)
        #expect(registry.profile(for: try ScreenFixture.load("plain-shell-fish").lines) is PlainTerminalProfile)
        #expect(registry.profile(for: []) is PlainTerminalProfile)
    }

    @Test("Profiles are tried in order and the first match wins; the fallback reads every other pane")
    func orderAndFallback() {
        let registry = TUIProfileRegistry(
            profiles: [
                NamedProfile(name: "a", accepts: false),
                NamedProfile(name: "b", accepts: true),
                NamedProfile(name: "c", accepts: true),
            ],
            fallback: NamedProfile(name: "fallback", accepts: false)
        )
        let none = TUIProfileRegistry(profiles: [NamedProfile(name: "a", accepts: false)], fallback: NamedProfile(name: "fallback", accepts: false))

        #expect(registry.profile(for: ["row"]).role(of: "") == .content("b"))
        #expect(none.profile(for: ["row"]).role(of: "") == .content("fallback"))
        #expect(TUIProfileRegistry(profiles: []).profile(for: ["row"]) is PlainTerminalProfile)
    }
}
