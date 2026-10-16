import Testing

/// Structural facts only, so the provider tests (T4b) can rely on these fixtures.
@Suite("Screen fixtures")
struct FixtureLoadingTests {
    @Test("The Ghostty AX capture of a tmux vertical split has a frame and both gutter glyphs")
    func ghosttyTmuxVerticalSplit() throws {
        let fixture = try ScreenFixture.load("ghostty-tmux-vsplit-opencode")
        let frame = try #require(fixture.frame)
        let scalars = Set(fixture.lines.joined().unicodeScalars)

        #expect(!fixture.lines.isEmpty)
        #expect(frame.width > 0 && frame.height > 0)
        #expect(scalars.contains("\u{2502}"))  // │ tmux pane divider
        #expect(scalars.contains("\u{2503}"))  // ┃ OpenCode message gutter
    }

    @Test("The tmux pane capture of a plain fish shell has lines and no frame")
    func plainShellFish() throws {
        let fixture = try ScreenFixture.load("plain-shell-fish")

        #expect(!fixture.lines.isEmpty)
        #expect(fixture.frame == nil)
    }
}
