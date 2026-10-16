import Foundation
import NaturalLanguage

/// Splits text into the sentences that back/forward navigation moves between.
public struct SentenceSplitter: Sendable {
    public init() {}

    /// Returns the trimmed, non-empty sentences of `text`, in order.
    ///
    /// Every hard line break is a boundary, so list items and headings without terminal
    /// punctuation become their own sentences. Within a line, `NLTokenizer` finds the
    /// sentence boundaries.
    public func split(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).flatMap { sentences(inLine: String($0)) }
    }

    private func sentences(inLine line: String) -> [String] {
        // NLTokenizer is not Sendable, so each call creates its own instance.
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = line
        var result: [String] = []
        tokenizer.enumerateTokens(in: line.startIndex..<line.endIndex) { range, _ in
            let sentence = line[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                result.append(sentence)
            }
            return true
        }
        return result
    }
}
