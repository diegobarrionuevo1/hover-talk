import CoreGraphics

/// A paragraph found on a terminal screen.
public struct TerminalTextBlock: Equatable, Sendable {
    /// The paragraph's rows joined into text to read.
    public let text: String
    public let rows: ClosedRange<Int>
    /// From the leftmost to the rightmost non-blank cell of the paragraph's rows, among the
    /// cells its profile reads (so without a stripped gutter or sidebar), inside its pane.
    public let columns: ClosedRange<Int>
    /// `rows` × `columns` in the coordinates of the frame passed to the provider.
    public let rect: CGRect

    public init(text: String, rows: ClosedRange<Int>, columns: ClosedRange<Int>, rect: CGRect) {
        self.text = text
        self.rows = rows
        self.columns = columns
        self.rect = rect
    }
}

/// Finds the paragraph under a point on a terminal screen given as rows of text.
public enum TerminalGridProvider {
    /// Maps `point` (in the coordinates of `frame`, normally AX) to a cell and its pane, reads
    /// the pane with the profile `registry` picks for it, then expands the pointed row to the
    /// run of adjacent rows of that pane that the profile calls non-blank content.
    ///
    /// Returns `nil` when the point is outside `frame`, on a pane divider, in a `.tmuxStatus`
    /// pane, on a row that is blank or chrome, or outside the cells the profile reads on the
    /// pointed row (such as a stripped gutter or sidebar). The block's `columns` and `rect`
    /// cover only the non-blank cells the profile reads.
    ///
    /// Rows are joined with one space, or with a newline before a row that starts with a list
    /// marker (see `startsWithListMarker`), because `SentenceSplitter` splits at every newline
    /// first, so the previous item ends there. A row starting with a code fence (```) and the
    /// row after it also start new lines, so `TextCleaner` sees whole fence lines. Whitespace
    /// runs inside a row become one space.
    ///
    /// Parses the whole screen on every call; use `ParsedScreen` or `ScreenBlockCache` to look
    /// up several points on the same screen.
    public static func block(
        at point: CGPoint,
        frame: CGRect,
        lines: [String],
        registry: TUIProfileRegistry = .standard
    ) -> TerminalTextBlock? {
        ParsedScreen(lines: lines, frame: frame, registry: registry).block(at: point)
    }

    /// As `block(at:frame:lines:registry:)`, but reads every pane with `profile`.
    public static func block(
        at point: CGPoint,
        frame: CGRect,
        lines: [String],
        profile: any TUIProfile
    ) -> TerminalTextBlock? {
        ParsedScreen(lines: lines, frame: frame, profile: profile).block(at: point)
    }

    static func collapsingWhitespace(_ row: String) -> String {
        row.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func joined(_ rows: [String]) -> String {
        var text = ""
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let newLine = startsWithListMarker(row) || isCodeFence(row) || isCodeFence(rows[index - 1])
                text += newLine ? "\n" : " "
            }
            text += row
        }
        return text
    }

    private static func isCodeFence(_ row: String) -> Bool {
        row.hasPrefix("```")
    }

    /// `-`, `*` or `•`; one to three ASCII digits and `.` or `)`; or one ASCII letter and `)`;
    /// after any indentation, and followed by whitespace or the end of the row.
    static func startsWithListMarker(_ line: String) -> Bool {
        let row = line.drop(while: \.isWhitespace)
        guard let first = row.first else { return false }
        let rest: Substring
        if first == "-" || first == "*" || first == "\u{2022}" {
            rest = row.dropFirst()
        } else if first.isASCII, first.isWholeNumber {
            let digits = row.prefix { $0.isASCII && $0.isWholeNumber }
            let afterDigits = row.dropFirst(digits.count)
            guard digits.count <= 3, let mark = afterDigits.first, mark == "." || mark == ")" else { return false }
            rest = afterDigits.dropFirst()
        } else if first.isASCII, first.isLetter {
            let afterLetter = row.dropFirst()
            guard afterLetter.first == ")" else { return false }
            rest = afterLetter.dropFirst()
        } else {
            return false
        }
        return rest.first.map(\.isWhitespace) ?? true
    }
}
