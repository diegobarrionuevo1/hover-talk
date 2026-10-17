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

    public func clean(_ text: String) -> String {
        var lines: [String] = []
        var inCodeBlock = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.drop(while: \.isWhitespace).hasPrefix("```") {
                if !inCodeBlock, codeBlocks == .omit { lines.append(Self.codeOmitted) }
                inCodeBlock.toggle()
            } else if !inCodeBlock {
                lines.append(Self.cleanGlyphs(Self.cleanMarkdown(line)))
            } else if codeBlocks == .keep {
                lines.append(Self.cleanGlyphs(line))
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
