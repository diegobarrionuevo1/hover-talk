/// Text that remembers, for each of its Characters, where that Character came from: its
/// anchor, such as the terminal cell it was read from (`CellPosition`). Transformations that
/// build their result with `append` keep the anchor of every Character they keep, so text that
/// was cleaned and then cut into sentences can still be traced back to its source.
public struct MappedText<Anchor: Equatable & Sendable>: Equatable, Sendable {
    public private(set) var text: String
    /// One entry per Character of `text`, in order: its anchor, or `nil` for a Character with no
    /// source, such as a space that joins two rows or a replacement text.
    public private(set) var anchors: [Anchor?]

    public init() {
        text = ""
        anchors = []
    }

    /// `text` with no anchor for any of its Characters.
    public init(_ text: String) {
        self.text = text
        anchors = Array(repeating: nil, count: text.count)
    }

    /// Characters with their anchors, appended in order (see `append(_:anchor:)`).
    public init<Elements: Sequence>(elements: Elements) where Elements.Element == (Character, Anchor?) {
        self.init()
        for (character, anchor) in elements {
            append(character, anchor: anchor)
        }
    }

    /// Each Character of `text` with its anchor, in order.
    public var elements: Zip2Sequence<String, [Anchor?]> {
        zip(text, anchors)
    }

    /// Appends `character` with `anchor`. When `character` combines with the last Character
    /// into one (such as a combining accent after a letter), the combined Character keeps the
    /// last Character's anchor, so `anchors` keeps one entry per Character of `text`.
    public mutating func append(_ character: Character, anchor: Anchor?) {
        let oldEnd = text.endIndex
        text.append(character)
        // Walk back from the new end: the last Character starts before the old end only when
        // `character` merged into it. (Stepping forward from an index taken before the append
        // missed the merge in `MappedTextTests`; such an index may keep its old Character length.)
        if text.index(before: text.endIndex) < oldEnd { return }
        anchors.append(anchor)
    }

    /// Appends every Character of `string`, each with `anchor`.
    public mutating func append(_ string: String, anchor: Anchor?) {
        for character in string {
            append(character, anchor: anchor)
        }
    }

    /// Appends `other`'s Characters with their anchors.
    public mutating func append(_ other: MappedText) {
        for (character, anchor) in other.elements {
            append(character, anchor: anchor)
        }
    }

    /// The mapped form of `text.split(whereSeparator: \.isWhitespace).joined(separator: " ")`:
    /// every whitespace run between two words becomes one space with the anchor of the run's
    /// first Character, and leading and trailing whitespace goes.
    public func collapsingWhitespace() -> MappedText {
        var result = MappedText()
        var space: (pending: Bool, anchor: Anchor?) = (false, nil)
        for (character, anchor) in elements {
            if character.isWhitespace {
                if !space.pending { space = (true, anchor) }
                continue
            }
            if space.pending, !result.text.isEmpty {
                result.append(" ", anchor: space.anchor)
            }
            space = (false, nil)
            result.append(character, anchor: anchor)
        }
        return result
    }

    /// The mapped form of `text.replacing(pattern, with: "")`: removes every occurrence of
    /// `pattern`'s Characters, matched from left to right without overlapping.
    func removing(_ pattern: String) -> MappedText {
        let marks = Array(pattern)
        let items = Array(elements)
        var result = MappedText()
        var index = 0
        while index < items.count {
            if !marks.isEmpty, index + marks.count <= items.count,
               items[index..<(index + marks.count)].map(\.0) == marks {
                index += marks.count
            } else {
                result.append(items[index].0, anchor: items[index].1)
                index += 1
            }
        }
        return result
    }
}
