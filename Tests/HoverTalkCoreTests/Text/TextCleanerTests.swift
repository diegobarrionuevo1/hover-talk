import Testing
@testable import HoverTalkCore

@Suite("TextCleaner")
struct TextCleanerTests {
    private let cleaner = TextCleaner()

    // MARK: Glyphs and whitespace

    @Test("Box drawing, block elements, braille and private-use glyphs are dropped and whitespace collapses")
    func dropsDecorativeGlyphs() {
        let text = "  \u{2503} one \u{2502} two\u{2500}\u{2500} \u{2580}\u{2588} \u{2834}three \u{E0B0} four \u{F06A9}five \u{10FFFD} six  "

        #expect(cleaner.clean(text) == "one two three four five six")
    }

    @Test("Letters, digits, punctuation, symbols and emoji are kept")
    func keepsReadableText() {
        let text = "\u{00BF}Qu\u{00E9}? 3.5 ms \u{2014} \u{2713} done \u{23F3} (x \u{2192} y) 100% $2.84 \u{00B7} \u{1F600}"

        #expect(cleaner.clean(text) == text)
    }

    @Test("Each line is cleaned on its own; lines left blank are dropped")
    func lines() {
        #expect(cleaner.clean("first   line\n\u{2500}\u{2500}\u{2500}\n\n  second\tline  \n") == "first line\nsecond line")
        #expect(cleaner.clean("") == "")
        #expect(cleaner.clean("\u{2502} \u{2588}") == "")
    }

    // MARK: Markdown

    @Test("Bold and underline marks, inline-code backticks and heading marks are removed; their text stays")
    func markdownMarks() {
        #expect(cleaner.clean("**Bold** and __strong__ text") == "Bold and strong text")
        #expect(cleaner.clean("Run `swift test` now") == "Run swift test now")
        #expect(cleaner.clean("## Heading two\n# One\n###### Six") == "Heading two\nOne\nSix")
    }

    @Test("A # that is not a heading mark stays")
    func notHeadings() {
        #expect(cleaner.clean("#hashtag, C# and issue #12") == "#hashtag, C# and issue #12")
        #expect(cleaner.clean("####### seven") == "####### seven")
    }

    // MARK: Code blocks

    @Test("A fenced code block becomes \"Code omitted.\" by default")
    func omitsCodeBlocks() {
        let text = "Intro\n```swift\nlet x = **1**\n```\nOutro"

        #expect(cleaner.clean(text) == "Intro\nCode omitted.\nOutro")
        #expect(cleaner.clean("Intro\n  ```\nunclosed code") == "Intro\nCode omitted.")
        #expect(cleaner.clean("```\na\n```\nmiddle\n```\nb\n```") == "Code omitted.\nmiddle\nCode omitted.")
    }

    @Test("With code blocks kept, the fence lines go and the code stays, without markdown cleanup")
    func keepsCodeBlocks() {
        let keeping = TextCleaner(codeBlocks: .keep)

        #expect(keeping.clean("Intro\n```swift\nlet  x = a ** b\n```\n**Outro**") == "Intro\nlet x = a ** b\nOutro")
    }
}

@Suite("TextCleaner on mapped text")
struct MappedTextCleanerTests {
    private let cleaner = TextCleaner()

    @Test("Kept Characters keep their anchors; dropped glyphs and markdown marks drop out; a whitespace run keeps its first anchor")
    func keepsAnchors() {
        // ┃0 1 *2 *3 H4 i5 *6 *7 8 9 `10 x11 `12
        let cleaned = cleaner.clean(MappedText.offsets("\u{2503} **Hi**  `x`"))

        #expect(cleaned.text == "Hi x")
        #expect(cleaned.anchors == [4, 5, 8, 11])
    }

    @Test("A heading mark drops out with the space after it; underline marks drop out")
    func headingAndUnderline() {
        // #0 #1 2 _3 _4 T5 o6 p7 _8 _9
        let cleaned = cleaner.clean(MappedText.offsets("## __Top__"))

        #expect(cleaned.text == "Top")
        #expect(cleaned.anchors == [5, 6, 7])
    }

    @Test("Lines left blank go; the newline joining two kept lines has no anchor")
    func lines() {
        // o0 n1 e2 \n3 ─4 \n5 \n6 t7 w8 o9
        let cleaned = cleaner.clean(MappedText.offsets("one\n\u{2500}\n\ntwo"))

        #expect(cleaned.text == "one\ntwo")
        #expect(cleaned.anchors == [0, 1, 2, nil, 7, 8, 9])
    }

    @Test("\"Code omitted.\" maps every Character to the opening fence's first cell")
    func omittedCodeMapsToFence() {
        // "Intro\n" 0-5, "  ```swift" 6-15 (first backtick 8), "\n" 16, "let x" 17-21, "\n" 22,
        // "```" 23-25, "\n" 26, "Out" 27-29.
        let cleaned = cleaner.clean(MappedText.offsets("Intro\n  ```swift\nlet x\n```\nOut"))

        #expect(cleaned.text == "Intro\nCode omitted.\nOut")
        #expect(cleaned.anchors == [0, 1, 2, 3, 4, nil] + Array(repeating: 8, count: 13) + [nil, 27, 28, 29])
    }

    @Test("Kept code keeps the anchors of its code Characters")
    func keptCodeKeepsAnchors() {
        // a0 \n1 `2 `3 `4 \n5 x6 7 8 *9 *10 11 y12 \n13 `14 `15 `16
        let cleaned = TextCleaner(codeBlocks: .keep).clean(MappedText.offsets("a\n```\nx  ** y\n```"))

        #expect(cleaned.text == "a\nx ** y")
        #expect(cleaned.anchors == [0, nil, 6, 7, 9, 10, 11, 12])
    }

    @Test("Text without anchors cleans to text without anchors")
    func unanchored() {
        let cleaned = cleaner.clean(MappedText<Int>("```\ncode\n```\n**Done**"))

        #expect(cleaned.text == "Code omitted.\nDone")
        #expect(cleaned.anchors.allSatisfy { $0 == nil })
        #expect(cleaned.anchors.count == cleaned.text.count)
    }

    static let equivalenceCases = [
        "", "\n", "plain", "  \u{2503} one \u{2502} two\u{2500}\u{2500} \u{2580}\u{2588} \u{2834}three \u{E0B0} four  ",
        "\u{00BF}Qu\u{00E9}? 3.5 ms \u{2014} \u{2713} done \u{23F3} (x \u{2192} y) 100% $2.84 \u{00B7} \u{1F600}",
        "first   line\n\u{2500}\u{2500}\u{2500}\n\n  second\tline  \n", "**Bold** and __strong__ text", "Run `swift test` now",
        "## Heading two\n# One\n###### Six", "#hashtag, C# and issue #12", "####### seven", "***x*** _**y**_ ``z``",
        "Intro\n```swift\nlet x = **1**\n```\nOutro", "Intro\n  ```\nunclosed code", "```\na\n```\nmiddle\n```\nb\n```",
        "e\u{301}**\u{301} combining", "tabs\tand\r\nreturns\u{00A0}nbsp",
    ]

    @Test("Cleaning text gives what the line-by-line String implementation gave", arguments: equivalenceCases)
    func sameAsStringImplementation(text: String) {
        for codeBlocks in [TextCleaner.CodeBlocks.omit, .keep] {
            let cleaner = TextCleaner(codeBlocks: codeBlocks)
            #expect(cleaner.clean(text) == ReferenceCleaner.clean(text, codeBlocks: codeBlocks))
            #expect(cleaner.clean(MappedText.offsets(text)).text == cleaner.clean(text))
        }
    }
}

/// The String-only `TextCleaner.clean(_:)` as it was before the mapped variant replaced it,
/// kept as the reference the mapped variant must reproduce.
private enum ReferenceCleaner {
    static func clean(_ text: String, codeBlocks: TextCleaner.CodeBlocks) -> String {
        var lines: [String] = []
        var inCodeBlock = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.drop(while: \.isWhitespace).hasPrefix("```") {
                if !inCodeBlock, codeBlocks == .omit { lines.append(TextCleaner.codeOmitted) }
                inCodeBlock.toggle()
            } else if !inCodeBlock {
                lines.append(cleanGlyphs(cleanMarkdown(line)))
            } else if codeBlocks == .keep {
                lines.append(cleanGlyphs(line))
            }
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static let droppedScalars: [ClosedRange<UInt32>] = [
        0x2500...0x257F, 0x2580...0x259F, 0x2800...0x28FF, 0xE000...0xF8FF, 0xF0000...0x10FFFF,
    ]

    private static func cleanGlyphs(_ line: some StringProtocol) -> String {
        let kept = line.map { character -> Character in
            let dropped = character.unicodeScalars.first.map { scalar in
                droppedScalars.contains { $0.contains(scalar.value) }
            } ?? false
            return dropped ? " " : character
        }
        return String(kept).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func cleanMarkdown(_ line: some StringProtocol) -> String {
        var text = String(line.drop(while: \.isWhitespace))
        let hashes = text.prefix { $0 == "#" }.count
        if (1...6).contains(hashes), text.dropFirst(hashes).first?.isWhitespace == true {
            text.removeFirst(hashes)
        }
        return text.replacing("**", with: "").replacing("__", with: "").replacing("`", with: "")
    }
}
