/// Turns text read from a screen into text worth speaking; meant for a provider's text right
/// before it is spoken. Pure.
///
/// Line by line:
/// - Box drawing (U+2500–U+257F), block elements (U+2580–U+259F), braille (U+2800–U+28FF) and
///   private-use glyphs (U+E000–U+F8FF and planes 15–16, where Nerd Font icons live) become
///   spaces; whitespace runs then collapse to one space, and lines left blank are dropped.
/// - Markdown marks go and their text stays: `**`, `__`, inline-code backticks, and a leading
///   heading mark (one to six `#` and a space).
/// - A fenced code block (from a line starting with ``` to the next one, or to the end) becomes
///   one line `Code omitted.`, or with `.keep`, its code lines without the fences, with glyphs
///   and whitespace cleaned but no markdown cleanup.
public struct TextCleaner: Sendable {
    public enum CodeBlocks: Equatable, Sendable {
        case omit
        case keep
    }

    /// Spoken in place of an omitted code block.
    public static let codeOmitted = "Code omitted."

    public var codeBlocks: CodeBlocks

    public init(codeBlocks: CodeBlocks = .omit) {
        self.codeBlocks = codeBlocks
    }

    /// The text of `clean(_:)` on the text without anchors.
    public func clean(_ text: String) -> String {
        clean(MappedText<Never>(text)).text
    }

    /// Cleans `mapped.text` and keeps the anchor of every Character it keeps:
    /// - removed glyphs and marks take their anchors with them;
    /// - a whitespace run collapsed to one space keeps the run's first anchor;
    /// - `Code omitted.` takes, for each of its Characters, the anchor of the opening fence
    ///   line's first non-blank anchored Character (`nil` when it has none);
    /// - the newline that joins two kept lines has no anchor.
    public func clean<Anchor>(_ mapped: MappedText<Anchor>) -> MappedText<Anchor> {
        var lines: [MappedText<Anchor>] = []
        var inCodeBlock = false
        for line in Self.lines(of: mapped) {
            if line.text.drop(while: \.isWhitespace).hasPrefix("```") {
                if !inCodeBlock, codeBlocks == .omit {
                    let fence = line.elements.first { !$0.0.isWhitespace && $0.1 != nil }?.1
                    var omitted = MappedText<Anchor>()
                    omitted.append(Self.codeOmitted, anchor: fence)
                    lines.append(omitted)
                }
                inCodeBlock.toggle()
            } else if !inCodeBlock {
                lines.append(Self.cleanGlyphs(Self.cleanMarkdown(line)))
            } else if codeBlocks == .keep {
                lines.append(Self.cleanGlyphs(line))
            }
        }

        var result = MappedText<Anchor>()
        for line in lines where !line.text.isEmpty {
            if !result.text.isEmpty { result.append("\n", anchor: nil) }
            result.append(line)
        }
        return result
    }

    /// The text's lines, split at every `\n` Character; empty lines are kept.
    private static func lines<Anchor>(of mapped: MappedText<Anchor>) -> [MappedText<Anchor>] {
        var lines = [MappedText<Anchor>()]
        for (character, anchor) in mapped.elements {
            if character == "\n" {
                lines.append(MappedText())
            } else {
                lines[lines.count - 1].append(character, anchor: anchor)
            }
        }
        return lines
    }

    private static let droppedScalars: [ClosedRange<UInt32>] = [
        0x2500...0x257F, 0x2580...0x259F, 0x2800...0x28FF, 0xE000...0xF8FF, 0xF0000...0x10FFFF,
    ]

    private static func cleanGlyphs<Anchor>(_ line: MappedText<Anchor>) -> MappedText<Anchor> {
        var kept = MappedText<Anchor>()
        for (character, anchor) in line.elements {
            let dropped = character.unicodeScalars.first.map { scalar in
                droppedScalars.contains { $0.contains(scalar.value) }
            } ?? false
            kept.append(dropped ? " " : character, anchor: anchor)
        }
        return kept.collapsingWhitespace()
    }

    private static func cleanMarkdown<Anchor>(_ line: MappedText<Anchor>) -> MappedText<Anchor> {
        var items = Array(line.elements.drop { $0.0.isWhitespace })
        let hashes = items.prefix { $0.0 == "#" }.count
        if (1...6).contains(hashes), items.dropFirst(hashes).first?.0.isWhitespace == true {
            items.removeFirst(hashes)
        }
        return MappedText(elements: items).removing("**").removing("__").removing("`")
    }
}
