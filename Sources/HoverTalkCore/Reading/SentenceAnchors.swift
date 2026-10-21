/// A cleaned text cut into the sentences the player reads, keeping where each Character came
/// from, so the sentence and the word being spoken can be highlighted where they were read.
/// Generic over the anchor: terminal cells (`CellPosition`) or accessibility text positions
/// (`AXTextAnchor`).
public struct SentenceAnchors<Anchor: Equatable & Sendable>: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let character: Character
        public let anchor: Anchor
    }

    /// Equal to `SentenceSplitter().split(text)`, which is what the player loads.
    public let sentences: [String]
    /// Per sentence, every Character of the sentence string with its anchor, if any.
    private let characters: [[(character: Character, anchor: Anchor?)]]
    /// The indices of the sentences that end a paragraph, ascending; empty without paragraph
    /// information. Paragraph reading stops at one of them (see `paragraphEnd(atOrAfter:)`).
    public let paragraphEnds: [Int]

    /// `paragraph` tells which paragraph an anchor was read from; a sentence belongs to the
    /// paragraph of its first anchored Character, or of the sentence before it when it has none.
    public init(
        _ cleaned: MappedText<Anchor>,
        splitter: SentenceSplitter = SentenceSplitter(),
        paragraph: ((Anchor) -> Int?)? = nil
    ) {
        let text = cleaned.text
        let ranges = splitter.ranges(in: text)
        sentences = ranges.map { String(text[$0]) }
        let pairs = Array(zip(text.indices, cleaned.elements.map(\.1)))
        let characters = ranges.map { range in
            pairs.filter { range.contains($0.0) }.map { (character: text[$0.0], anchor: $0.1) }
        }
        self.characters = characters
        guard let paragraph else {
            paragraphEnds = []
            return
        }
        var owners: [Int?] = []
        for sentence in characters {
            let own = sentence.lazy.compactMap { $0.anchor.flatMap(paragraph) }.first
            owners.append(own ?? owners.last ?? nil)
        }
        guard owners.contains(where: { $0 != nil }) else {
            paragraphEnds = []
            return
        }
        paragraphEnds = owners.indices.filter { $0 == owners.count - 1 || owners[$0 + 1] != owners[$0] }
    }

    /// The first paragraph end at or after sentence `index`: where paragraph reading of the
    /// paragraph holding `index` stops. `nil` without paragraph information.
    public func paragraphEnd(atOrAfter index: Int) -> Int? {
        paragraphEnds.first { $0 >= index }
    }

    /// The anchored, non-whitespace Characters of sentence `index`, in order.
    public func anchors(ofSentence index: Int) -> [Entry] {
        guard characters.indices.contains(index) else { return [] }
        return characters[index].compactMap { item in
            guard let anchor = item.anchor, !item.character.isWhitespace else { return nil }
            return Entry(character: item.character, anchor: anchor)
        }
    }

    /// The anchored Characters of the word that contains the UTF-16 `offset` of sentence
    /// `index` (speech engines report word starts in UTF-16 units): from that Character to the
    /// next whitespace. Empty when the offset lies outside the sentence or on whitespace.
    public func word(inSentence index: Int, atUTF16Offset offset: Int) -> [Entry] {
        guard characters.indices.contains(index), offset >= 0 else { return [] }
        let row = characters[index]
        var position = 0
        var start: Int?
        for (i, item) in row.enumerated() {
            let width = item.character.utf16.count
            if offset < position + width { start = i; break }
            position += width
        }
        guard var i = start else { return [] }
        // An offset inside a word starts at that word's first Character.
        while i > 0, !row[i - 1].character.isWhitespace { i -= 1 }
        var entries: [Entry] = []
        while i < row.count, !row[i].character.isWhitespace {
            if let anchor = row[i].anchor { entries.append(Entry(character: row[i].character, anchor: anchor)) }
            i += 1
        }
        return entries
    }

    public static func == (lhs: SentenceAnchors, rhs: SentenceAnchors) -> Bool {
        lhs.sentences == rhs.sentences
            && lhs.paragraphEnds == rhs.paragraphEnds
            && lhs.characters.count == rhs.characters.count
            && zip(lhs.characters, rhs.characters).allSatisfy { a, b in
                a.count == b.count && zip(a, b).allSatisfy { $0.character == $1.character && $0.anchor == $1.anchor }
            }
    }
}
