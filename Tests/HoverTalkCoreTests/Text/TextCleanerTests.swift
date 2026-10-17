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
