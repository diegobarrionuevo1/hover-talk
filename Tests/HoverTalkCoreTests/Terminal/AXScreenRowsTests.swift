import CoreGraphics
import Testing
@testable import HoverTalkCore

@Suite("AXScreenRows")
struct AXScreenRowsTests {
    @Test("Rows separated by newlines, all padded to the same width, stay as they are")
    func paddedRowsUnchanged() {
        let value = "first row \nsecond row\n          "

        #expect(AXScreenRows.split(value) == ["first row ", "second row", "          "])
    }

    @Test("A soft-wrapped line, an exact multiple of the screen width, splits into one row per screen row")
    func wrappedLineSplits() {
        let value = ["head      ", "aaaaaaaaaabbbbbbbbbbcccccccccc", "tail      "].joined(separator: "\n")

        #expect(AXScreenRows.split(value) == ["head      ", "aaaaaaaaaa", "bbbbbbbbbb", "cccccccccc", "tail      "])
    }

    @Test("Wide characters count as two cells when a wrapped line splits")
    func wideCharactersSplitByCells() {
        let value = ["0123456789", "0123456789", "abcd\u{4E00}\u{4E00}\u{4E00}efgh      "].joined(separator: "\n")

        #expect(AXScreenRows.split(value) == ["0123456789", "0123456789", "abcd\u{4E00}\u{4E00}\u{4E00}", "efgh      "])
    }

    @Test("A line wider than the screen width but not a multiple of it stays whole")
    func notAMultipleStaysWhole() {
        let value = ["0123456789", "0123456789", "0123456789abc"].joined(separator: "\n")

        #expect(AXScreenRows.split(value) == ["0123456789", "0123456789", "0123456789abc"])
    }

    @Test("Rows that are not padded to one common width are never split")
    func unpaddedRowsNeverSplit() {
        let value = ["ls", "a.txt b.txt", "abcdefghijklmnopqrstuv", "cd", "pwd"].joined(separator: "\n")

        #expect(AXScreenRows.split(value) == ["ls", "a.txt b.txt", "abcdefghijklmnopqrstuv", "cd", "pwd"])
    }

    @Test("An empty value or a trailing newline keeps its empty rows")
    func emptyRows() {
        #expect(AXScreenRows.split("") == [""])
        #expect(AXScreenRows.split("0123456789\n") == ["0123456789", ""])
    }

    @Test("The cache reads a screen with a wrapped line on the rows it covers")
    func cacheMapsWrappedRows() {
        let value = ["head      ", "          ", "wrapped   text here ", "          ", "tail      "].joined(separator: "\n")
        var cache = ScreenBlockCache()
        let frame = CGRect(x: 0, y: 0, width: 100, height: 120)

        let block = cache.block(at: CGPoint(x: 5, y: 70), value: value, frame: frame)

        #expect(cache.screen(value: value, frame: frame).grid.rowCount == 6)
        #expect(block?.rows == 2...3)
        #expect(block?.text == "wrapped text here")
        #expect(cache.block(at: CGPoint(x: 5, y: 110), value: value, frame: frame)?.text == "tail")
    }
}
