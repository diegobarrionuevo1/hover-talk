import CoreGraphics

/// Cells of one terminal row, from the first to the last column.
public struct RowSpan: Equatable, Sendable {
    public let row: Int
    public let columns: ClosedRange<Int>

    public init(row: Int, columns: ClosedRange<Int>) {
        self.row = row
        self.columns = columns
    }
}

/// Text to read aloud, cut into the sentences the player moves between, with the terminal
/// cells each sentence was read from, so the sentence being spoken can be highlighted.
public struct ReadingDocument: Equatable, Sendable {
    /// The cleaned text; `SentenceSplitter().split(text)` gives `sentences`, which is what
    /// `PlaybackQueue.load(_:)` does with it.
    public let text: String
    public let sentences: [String]
    /// For each sentence, the cells its non-whitespace Characters were read from: one span per
    /// row, from the first to the last of those cells (a wide Character's two cells included),
    /// top to bottom. Empty for a sentence without anchored Characters.
    public let sentenceSpans: [[RowSpan]]
    /// The same for every non-whitespace anchored Character of the text.
    public let spans: [RowSpan]
    /// Each sentence's Characters with their cells, for the word being spoken.
    public let anchors: SentenceAnchors<CellPosition>

    /// `cleaned` is a block's `TerminalTextBlock.mappedText` after `TextCleaner`.
    /// `paragraph` tells which paragraph a cell was read from (see `SentenceAnchors`).
    public init(
        _ cleaned: MappedText<CellPosition>,
        splitter: SentenceSplitter = SentenceSplitter(),
        paragraph: ((CellPosition) -> Int?)? = nil
    ) {
        let text = cleaned.text
        let ranges = splitter.ranges(in: text)
        self.text = text
        sentences = ranges.map { String(text[$0]) }

        var perSentence = Array(repeating: SpanCollector(), count: ranges.count)
        var whole = SpanCollector()
        var sentence = 0
        for (index, (character, anchor)) in zip(text.indices, cleaned.elements) {
            guard let anchor, !character.isWhitespace else { continue }
            whole.add(anchor, character)
            // A Character belongs to the sentence whose range holds its first scalar.
            while sentence < ranges.count, ranges[sentence].upperBound <= index { sentence += 1 }
            if sentence < ranges.count, ranges[sentence].lowerBound <= index {
                perSentence[sentence].add(anchor, character)
            }
        }
        sentenceSpans = perSentence.map(\.spans)
        spans = whole.spans
        anchors = SentenceAnchors(cleaned, splitter: splitter, paragraph: paragraph)
    }

    /// The cells of the word at the UTF-16 `utf16Offset` of sentence `sentence` (see
    /// `PlaybackQueue.wordOffset`), one span per row; empty when there is no such word.
    public func wordSpans(sentence: Int, utf16Offset: Int) -> [RowSpan] {
        var collector = SpanCollector()
        for entry in anchors.word(inSentence: sentence, atUTF16Offset: utf16Offset) {
            collector.add(entry.anchor, entry.character)
        }
        return collector.spans
    }
}

/// Gathers cells into one span per row.
private struct SpanCollector {
    private var columns: [Int: ClosedRange<Int>] = [:]

    mutating func add(_ cell: CellPosition, _ character: Character) {
        let last = cell.column + TerminalGrid.cellWidth(of: character) - 1
        let span = columns[cell.row].map { min($0.lowerBound, cell.column)...max($0.upperBound, last) }
        columns[cell.row] = span ?? cell.column...last
    }

    var spans: [RowSpan] {
        columns.sorted { $0.key < $1.key }.map { RowSpan(row: $0.key, columns: $0.value) }
    }
}

extension TerminalGeometry {
    /// One rect per span, with its row moved by `rowOffset` rows (up when negative), in the
    /// coordinates of `frame`.
    public func rects(for spans: [RowSpan], rowOffset: Int = 0) -> [CGRect] {
        spans.map { span in
            let row = span.row + rowOffset
            return rect(rows: row...row, columns: span.columns)
        }
    }
}
