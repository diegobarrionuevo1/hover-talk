import CoreGraphics
import Testing
@testable import HoverTalkCore

@Suite("ReadingDocument")
struct ReadingDocumentTests {
    /// `text` laid on `row` from `column` on, one or two cells per Character as on a terminal.
    private func cells(_ text: String, row: Int, from column: Int) -> MappedText<CellPosition> {
        var mapped = MappedText<CellPosition>()
        var next = column
        for character in text {
            mapped.append(character, anchor: CellPosition(row: row, column: next))
            next += TerminalGrid.cellWidth(of: character)
        }
        return mapped
    }

    @Test("The word being spoken maps to its own cells, even across a wrapped row")
    func wordSpans() {
        var mapped = cells("One two. Three", row: 3, from: 2)
        mapped.append(" ", anchor: nil)
        mapped.append(cells("four.", row: 4, from: 2))
        let document = ReadingDocument(mapped)
        #expect(document.wordSpans(sentence: 0, utf16Offset: 4) == [RowSpan(row: 3, columns: 6...9)])
        #expect(document.wordSpans(sentence: 1, utf16Offset: 6) == [RowSpan(row: 4, columns: 2...6)])
        #expect(document.wordSpans(sentence: 5, utf16Offset: 0) == [])
    }

    @Test("Each sentence maps to its own cells, one span per row; the document spans every row it was read from")
    func sentenceSpans() {
        var mapped = cells("One two. Three", row: 3, from: 2)
        mapped.append(" ", anchor: nil)
        mapped.append(cells("four.", row: 4, from: 2))
        let document = ReadingDocument(mapped)

        #expect(document.text == "One two. Three four.")
        #expect(document.sentences == ["One two.", "Three four."])
        #expect(document.sentenceSpans == [
            [RowSpan(row: 3, columns: 2...9)],
            [RowSpan(row: 3, columns: 11...15), RowSpan(row: 4, columns: 2...6)],
        ])
        #expect(document.spans == [RowSpan(row: 3, columns: 2...15), RowSpan(row: 4, columns: 2...6)])
    }

    @Test("A wide Character's span covers both of its cells")
    func wideCharacters() {
        // ⏳ 2-3, "wait." 5-9, "Done" 11-14, 😀 16-17.
        let document = ReadingDocument(cells("\u{23F3} wait. Done \u{1F600}", row: 0, from: 2))

        #expect(document.sentenceSpans == [[RowSpan(row: 0, columns: 2...9)], [RowSpan(row: 0, columns: 11...17)]])
    }

    @Test("The player gets the same sentences from the document's text")
    func sentencesMatchThePlayersSplit() {
        var mapped = cells("Intro line", row: 0, from: 0)
        mapped.append("\n", anchor: nil)
        mapped.append(cells("- item one. Item two", row: 1, from: 0))
        let document = ReadingDocument(mapped)

        #expect(SentenceSplitter().split(document.text) == document.sentences)
        #expect(document.sentences == ["Intro line", "- item one.", "Item two"])
        #expect(document.sentenceSpans.map { $0.map(\.row) } == [[0], [1], [1]])
    }

    @Test("Characters without an anchor give no span")
    func unanchored() {
        let document = ReadingDocument(MappedText("Hello there. Bye."))

        #expect(document.sentences == ["Hello there.", "Bye."])
        #expect(document.sentenceSpans == [[], []])
        #expect(document.spans.isEmpty)
    }

    @Test("\"Code omitted.\" spans the one cell its fence started at")
    func omittedCode() {
        var mapped = cells("Run:", row: 4, from: 0)
        mapped.append("\n", anchor: nil)
        mapped.append(cells("```sh", row: 5, from: 0))
        mapped.append("\n", anchor: nil)
        mapped.append(cells("make", row: 6, from: 0))
        mapped.append("\n", anchor: nil)
        mapped.append(cells("```", row: 7, from: 0))
        let document = ReadingDocument(TextCleaner().clean(mapped))

        #expect(document.sentences == ["Run:", "Code omitted."])
        #expect(document.sentenceSpans == [[RowSpan(row: 4, columns: 0...3)], [RowSpan(row: 5, columns: 0...0)]])
    }

    @Test("Claude Code fixture: a cleaned block's sentences map back to the cells they were read from")
    func fixtureSentences() throws {
        let block = try #require(try FixtureScreen("synthetic-claude-code").block(row: 8, column: 10))
        let document = ReadingDocument(TextCleaner().clean(block.mappedText))

        #expect(document.sentences == [
            "The garden has three beds along the north wall.",
            "Each bed holds herbs, and the paths between them are gravel.",
        ])
        #expect(document.sentenceSpans == [
            [RowSpan(row: 8, columns: 2...48)],
            [RowSpan(row: 8, columns: 50...57), RowSpan(row: 9, columns: 2...52)],
        ])
        #expect(document.spans == [RowSpan(row: 8, columns: 2...57), RowSpan(row: 9, columns: 2...52)])
    }

    @Test("Row spans become one rect per span, moved by a row offset")
    func rects() {
        let geometry = TerminalGeometry(frame: CGRect(x: 100, y: 50, width: 200, height: 100), rows: 10, columns: 20)
        let spans = [RowSpan(row: 2, columns: 3...5), RowSpan(row: 3, columns: 0...0)]

        #expect(geometry.rects(for: spans) == [CGRect(x: 130, y: 70, width: 30, height: 10), CGRect(x: 100, y: 80, width: 10, height: 10)])
        #expect(geometry.rects(for: spans, rowOffset: -1) == [CGRect(x: 130, y: 60, width: 30, height: 10), CGRect(x: 100, y: 70, width: 10, height: 10)])
    }
}
