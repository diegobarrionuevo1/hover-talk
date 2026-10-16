import Foundation
import Testing
@testable import HoverTalkFixtureKit

@Suite("ScreenFixture")
struct ScreenFixtureTests {
    @Test("An AX value splits on newlines and keeps trailing spaces and blank lines")
    func axLines() {
        #expect(ScreenFixture.lines(fromAXValue: "ab  \n\n cd") == ["ab  ", "", " cd"])
    }

    @Test("tmux output drops only the newline that ends its last line")
    func tmuxLines() {
        #expect(ScreenFixture.lines(fromTmuxCapture: "ab\ncd\n") == ["ab", "cd"])
        #expect(ScreenFixture.lines(fromTmuxCapture: "ab\n\n") == ["ab", ""])
        #expect(ScreenFixture.lines(fromTmuxCapture: "") == [])
    }

    @Test("A missing frame is written as null, and slashes are not escaped")
    func encodesNullFrame() throws {
        let fixture = ScreenFixture(frame: nil, lines: ["~/a/b $ ", "┃ x"])
        let json = String(decoding: try fixture.encoded(), as: UTF8.self)

        #expect(json.contains("\"frame\" : null"))
        #expect(json.contains("~/a/b $ "))
        #expect(try JSONDecoder().decode(ScreenFixture.self, from: try fixture.encoded()) == fixture)
    }

    @Test("A frame round-trips")
    func encodesFrame() throws {
        let fixture = ScreenFixture(frame: .init(x: 0, y: 65, width: 1470, height: 801), lines: ["a"])
        #expect(try JSONDecoder().decode(ScreenFixture.self, from: try fixture.encoded()) == fixture)
    }

    @Test("Sanitizing keeps the frame and the line structure")
    func sanitized() {
        let frame = ScreenFixture.Frame(x: 1, y: 2, width: 3, height: 4)
        let fixture = ScreenFixture(frame: frame, lines: ["Hello  ", "", "│ 42"])
        let sanitized = fixture.sanitized(with: FixtureSanitizer(salt: 3))

        #expect(sanitized.frame == frame)
        #expect(sanitized.lines.count == 3)
        #expect(sanitized.lines[0].count == 7 && sanitized.lines[0] != "Hello  ")
        #expect(sanitized.lines[1] == "")
        #expect(sanitized.lines[2].hasPrefix("│ ") && sanitized.lines[2] != "│ 42")
    }
}

@Suite("FixtureSummary")
struct FixtureSummaryTests {
    @Test("Counts lines, the widest line, the non-ASCII scalars and the first three lines")
    func summary() {
        let fixture = ScreenFixture(frame: nil, lines: ["ab │", "┃ c", "", "defgh", "│"])
        let summary = FixtureSummary(fixture)

        #expect(summary.lineCount == 5)
        #expect(summary.maxWidth == 5)
        #expect(summary.nonASCIIScalars == ["U+2502", "U+2503"])
        #expect(summary.firstLines == ["ab │", "┃ c", ""])
    }
}
