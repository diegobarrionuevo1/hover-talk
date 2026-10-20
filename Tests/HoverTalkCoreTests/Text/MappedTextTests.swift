import Testing
@testable import HoverTalkCore

extension MappedText where Anchor == Int {
    /// `text` with each Character anchored to its offset in `text`, so a test can see which
    /// source Characters a transformation kept.
    static func offsets(_ text: String) -> MappedText<Int> {
        MappedText(elements: text.enumerated().map { ($0.element, Optional($0.offset)) })
    }
}

@Suite("MappedText")
struct MappedTextTests {
    @Test("Plain text has one empty anchor per Character, wide and combined Characters included")
    func unanchored() {
        let text = MappedText<Int>("he\u{301}llo \u{1F600}")

        #expect(text.text == "he\u{301}llo \u{1F600}")
        #expect(text.anchors == [nil, nil, nil, nil, nil, nil, nil])
    }

    @Test("Appending Characters and strings keeps one anchor per Character")
    func append() {
        var text = MappedText<Int>()
        text.append("a", anchor: 1)
        text.append(" ", anchor: nil)
        text.append("bc", anchor: 7)

        #expect(text.text == "a bc")
        #expect(text.anchors == [1, nil, 7, 7])
        #expect(Array(text.elements.map(\.1)) == text.anchors)
    }

    @Test("A Character that combines with the last one into one Character keeps the last one's anchor")
    func combiningCharacterKeepsFirstAnchor() {
        var text = MappedText<Int>()
        text.append("e", anchor: 1)
        text.append("\u{301}", anchor: 2)
        text.append("x", anchor: 3)

        #expect(text.text == "e\u{301}x")
        #expect(text.anchors == [1, 3])
        #expect(text.anchors.count == text.text.count)
    }

    @Test("Collapsing whitespace keeps the first anchor of each inner run and drops leading and trailing runs")
    func collapsingWhitespace() {
        let collapsed = MappedText.offsets("  ab \t\n cd  e ").collapsingWhitespace()

        #expect(collapsed.text == "ab cd e")
        #expect(collapsed.anchors == [2, 3, 4, 8, 9, 10, 12])
    }

    @Test(
        "Collapsing whitespace gives the text of splitting at whitespace and joining with one space",
        arguments: ["", "   ", "one", "  a  b  ", "tab\there\nand\r\nthere", "\u{00A0}nbsp\u{2003}em", "e\u{301} \u{1F600}  x"]
    )
    func collapsingMatchesString(text: String) {
        let collapsed = MappedText.offsets(text).collapsingWhitespace()

        #expect(collapsed.text == text.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        #expect(collapsed.anchors.count == collapsed.text.count)
    }

    @Test("Removing a pattern matches from left to right without overlapping, as String.replacing does")
    func removing() {
        for text in ["***bold***", "a**b", "__x__ and **", "`a``b`", "no marks"] {
            let removed = MappedText.offsets(text).removing("**")
            #expect(removed.text == text.replacing("**", with: ""))
            #expect(removed.anchors.count == removed.text.count)
        }
        #expect(MappedText.offsets("a**b*").removing("**").anchors == [0, 3, 4])
    }
}
