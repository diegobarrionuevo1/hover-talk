import CoreGraphics
import Testing
@testable import HoverTalkCore

/// Rows starting with `==` are chrome; rows starting with `##` end a message.
private struct EndTestProfile: TUIProfile {
    func matches(paneLines: [String]) -> Bool { true }

    func role(of row: String) -> LineRole {
        if row.hasPrefix("##") { return .end }
        return row.hasPrefix("==") ? .chrome : .content(row.withoutTrailingWhitespace)
    }
}

@Suite("Message end and hover outline in terminals")
struct MessageEndTests {
    private func parsed(_ lines: [String]) -> ParsedScreen {
        let grid = TerminalGrid(lines: lines)
        let frame = CGRect(x: 0, y: 0, width: CGFloat(max(grid.columns, 1)) * 10, height: CGFloat(lines.count) * 20)
        return ParsedScreen(lines: lines, frame: frame, profile: EndTestProfile())
    }

    private func point(row: Int) -> CGPoint { CGPoint(x: 5, y: (CGFloat(row) + 0.5) * 20) }

    private let screen = [
        "First answer one.",
        "",
        "First answer two.",
        "== tool",
        "First answer three.",
        "## footer",
        "",
        "Second question.",
    ]

    @Test("Continuous reading skips chrome but stops at a message end")
    func stopsAtEnd() throws {
        let block = try #require(parsed(screen).block(at: point(row: 0), mode: .continuous))
        #expect(block.text == "First answer one.\nFirst answer two.\nFirst answer three.")
    }

    @Test("The outline covers only the pointed paragraph, also in continuous mode")
    func outlineOnlyPointed() throws {
        let screen = parsed(screen)
        let continuous = try #require(screen.block(at: point(row: 0), mode: .continuous))
        let paragraph = try #require(screen.block(at: point(row: 0)))
        #expect(continuous.rects == [paragraph.rect])
    }

    @Test("A block knows the rows of each of its paragraphs")
    func paragraphRows() throws {
        let block = try #require(parsed(screen).block(at: point(row: 0), mode: .continuous))
        #expect(block.paragraphRows == [0...0, 2...2, 4...4])
    }

    @Test("OpenCode's message footer ends a message")
    func openCodeFooter() {
        let roles = OpenCodeProfile().roles(ofPane: [
            "     Answer text.",
            "",
            "     \u{25A3}  build \u{00B7} model \u{00B7} 3.2s",
        ])
        #expect(roles[2] == .end)
    }
}
