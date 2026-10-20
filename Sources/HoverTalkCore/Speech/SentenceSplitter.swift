import Foundation
import NaturalLanguage

/// Splits text into the sentences that back/forward navigation moves between.
public struct SentenceSplitter: Sendable {
    public init() {}

    /// Returns the trimmed, non-empty sentences of `text`, in order: the text of `ranges(in:)`.
    ///
    /// Every hard line break is a boundary, so list items and headings without terminal
    /// punctuation become their own sentences. Within a line, `NLTokenizer` finds the
    /// sentence boundaries.
    public func split(_ text: String) -> [String] {
        ranges(in: text).map { String(text[$0]) }
    }

    /// Where `split(_:)`'s sentences lie in `text`, in order. Each line is tokenized as a String
    /// of its own, and each sentence is trimmed of the Unicode scalars in
    /// `CharacterSet.whitespacesAndNewlines`, as Foundation's `trimmingCharacters(in:)` trims
    /// them; so a range may start or end inside a Character that mixes whitespace and other scalars.
    public func ranges(in text: String) -> [Range<String.Index>] {
        text.split(whereSeparator: \.isNewline).flatMap(sentenceRanges(inLine:))
    }

    private func sentenceRanges(inLine line: Substring) -> [Range<String.Index>] {
        let lineText = String(line)
        // NLTokenizer is not Sendable, so each call creates its own instance.
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = lineText
        var result: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: lineText.startIndex..<lineText.endIndex) { range, _ in
            // Unicode scalar offsets carry the token from the copy back to `line`, whose indices
            // are those of the whole text.
            let scalars = lineText.unicodeScalars
            let lower = scalars.distance(from: scalars.startIndex, to: range.lowerBound)
            let upper = scalars.distance(from: scalars.startIndex, to: range.upperBound)
            let start = line.unicodeScalars.index(line.startIndex, offsetBy: lower)
            let end = line.unicodeScalars.index(line.startIndex, offsetBy: upper)
            if let trimmed = Self.trimmed(start..<end, in: line) {
                result.append(trimmed)
            }
            return true
        }
        return result
    }

    /// `range` without leading and trailing whitespace scalars, or `nil` when nothing is left.
    private static func trimmed(_ range: Range<String.Index>, in line: Substring) -> Range<String.Index>? {
        let scalars = line.unicodeScalars
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, CharacterSet.whitespacesAndNewlines.contains(scalars[lower]) {
            lower = scalars.index(after: lower)
        }
        while lower < upper, CharacterSet.whitespacesAndNewlines.contains(scalars[scalars.index(before: upper)]) {
            upper = scalars.index(before: upper)
        }
        return lower < upper ? lower..<upper : nil
    }
}
