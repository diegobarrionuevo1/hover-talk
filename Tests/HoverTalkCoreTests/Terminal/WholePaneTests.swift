import CoreGraphics
import Testing
@testable import HoverTalkCore

/// Rows starting with `==` end a message, as OpenCode's `▣` footer does.
private struct EndRowProfile: TUIProfile {
    func matches(paneLines: [String]) -> Bool { true }

    func role(of row: String) -> LineRole {
        row.hasPrefix("==") ? .end : .content(row.withoutTrailingWhitespace)
    }
}

@Suite("ParsedScreen whole pane")
struct WholePaneTests {
    private let lines = ["intro one", "", "mid", "== end of message", "later paragraph", "", "another"]

    private func screen(statusBar: StatusEdge? = nil, lines: [String]? = nil) -> (ParsedScreen, CGRect) {
        let lines = lines ?? self.lines
        let grid = TerminalGrid(lines: lines)
        let frame = CGRect(x: 0, y: 0, width: CGFloat(grid.columns) * 10, height: CGFloat(grid.rowCount) * 20)
        return (ParsedScreen(lines: lines, frame: frame, profile: EndRowProfile(), statusBar: statusBar), frame)
    }

    private func point(row: Int, column: Int = 1) -> CGPoint {
        CGPoint(x: (CGFloat(column) + 0.5) * 10, y: (CGFloat(row) + 0.5) * 20)
    }

    @Test("Reading all starts at the first paragraph of the pane and goes past message ends to the last row")
    func readsEverything() throws {
        let (parsed, _) = screen()

        let whole = try #require(parsed.wholePane(at: point(row: 4)))

        #expect(whole.text == "intro one\nmid\nlater paragraph\nanother")
        #expect(whole.rows == 0...6)
    }

    @Test("Any cell of the pane works, even a blank row or a blank cell; continuous reading from a paragraph still stops at the end")
    func anyCellInThePane() throws {
        let (parsed, _) = screen()

        #expect(try #require(parsed.wholePane(at: point(row: 1))).text.hasPrefix("intro one"))
        #expect(try #require(parsed.wholePane(at: point(row: 6, column: 7))).text.hasPrefix("intro one"))
        #expect(parsed.block(at: point(row: 0), mode: .continuous)?.text == "intro one\nmid")
    }

    @Test("The status row, a point outside the screen and a pane without content give nothing")
    func nothingToRead() {
        let (parsed, frame) = screen(statusBar: .top, lines: ["status bar here", "", ""])

        #expect(parsed.wholePane(at: point(row: 0)) == nil)
        #expect(parsed.wholePane(at: CGPoint(x: frame.maxX + 50, y: 10)) == nil)
        #expect(parsed.wholePane(at: point(row: 2)) == nil)
    }

    @Test("In a split, only the pane under the point is read")
    func onlyOnePane() throws {
        let (parsed, _) = screen(lines: ["left a│right a", "      │", "left b│right b"])

        #expect(try #require(parsed.wholePane(at: point(row: 0, column: 2))).text == "left a\nleft b")
        #expect(try #require(parsed.wholePane(at: point(row: 0, column: 9))).text == "right a\nright b")
    }
}
