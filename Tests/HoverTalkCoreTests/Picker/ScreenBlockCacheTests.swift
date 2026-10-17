import CoreGraphics
import Testing
@testable import HoverTalkCore

@Suite("ScreenBlockCache")
struct ScreenBlockCacheTests {
    /// The fixture as Ghostty's AX value: rows separated by `\n`.
    private func value(_ screen: FixtureScreen) -> String {
        screen.lines.joined(separator: "\n")
    }

    @Test("A block from the cache is the provider's block for the same screen")
    func sameBlockAsProvider() throws {
        let screen = try FixtureScreen(VSplitPanes.name)
        var cache = ScreenBlockCache()
        let point = screen.center(row: 12, column: 30)

        let block = cache.block(at: point, value: value(screen), frame: screen.frame)

        #expect(block != nil)
        #expect(block == TerminalGridProvider.block(at: point, frame: screen.frame, lines: screen.lines))
    }

    @Test("Moving over the same screen parses it once")
    func sameScreenParsesOnce() throws {
        let screen = try FixtureScreen(VSplitPanes.name)
        var cache = ScreenBlockCache()

        _ = cache.block(at: screen.center(row: 12, column: 30), value: value(screen), frame: screen.frame)
        _ = cache.block(at: screen.center(row: 13, column: 180), value: value(screen), frame: screen.frame)
        _ = cache.block(at: screen.center(row: 0, column: 10), value: value(screen), frame: screen.frame)

        #expect(cache.parseCount == 1)
    }

    @Test("A changed value parses again and reads the new rows")
    func changedValueParsesAgain() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        var cache = ScreenBlockCache()
        let point = CGPoint(x: 5, y: 5)

        #expect(cache.block(at: point, value: "first text\n", frame: frame)?.text == "first text")
        #expect(cache.block(at: point, value: "second text\n", frame: frame)?.text == "second text")
        #expect(cache.parseCount == 2)
    }

    @Test("A moved frame parses again and the block's rect follows it")
    func changedFrameParsesAgain() {
        var cache = ScreenBlockCache()
        let value = "some text\n"

        let first = cache.block(at: CGPoint(x: 5, y: 5), value: value, frame: CGRect(x: 0, y: 0, width: 90, height: 40))
        let moved = cache.block(at: CGPoint(x: 1475, y: 67), value: value, frame: CGRect(x: 1470, y: 62, width: 90, height: 40))

        #expect(first?.rect == CGRect(x: 0, y: 0, width: 90, height: 20))
        #expect(moved?.rect == CGRect(x: 1470, y: 62, width: 90, height: 20))
        #expect(cache.parseCount == 2)
    }

    @Test("A point outside the frame has no block and keeps the parsed screen")
    func outsidePointKeepsCache() {
        var cache = ScreenBlockCache()
        let frame = CGRect(x: 0, y: 0, width: 100, height: 40)

        #expect(cache.block(at: CGPoint(x: 500, y: 5), value: "text\n", frame: frame) == nil)
        #expect(cache.block(at: CGPoint(x: 5, y: 5), value: "text\n", frame: frame)?.text == "text")
        #expect(cache.parseCount == 1)
    }

    @Test("The cache reads with the registry it was given")
    func usesRegistry() throws {
        let screen = try FixtureScreen(VSplitPanes.name)
        var cache = ScreenBlockCache(registry: TUIProfileRegistry(profiles: []))
        let point = screen.center(row: 12, column: 110)

        #expect(cache.screen(value: value(screen), frame: screen.frame).panes.compactMap(\.profileName)
            == ["PlainTerminalProfile", "PlainTerminalProfile"])
        #expect(cache.block(at: point, value: value(screen), frame: screen.frame)
            == TerminalGridProvider.block(at: point, frame: screen.frame, lines: screen.lines, profile: PlainTerminalProfile()))
    }
}
