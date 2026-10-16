import Foundation

/// One captured screen, as stored in a JSON fixture: the text area's frame in AX coordinates
/// (top-left origin), or `nil` when the source has none, and the screen's lines.
public struct ScreenFixture: Codable, Equatable, Sendable {
    public struct Frame: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    public var frame: Frame?
    public var lines: [String]

    public init(frame: Frame?, lines: [String]) {
        self.frame = frame
        self.lines = lines
    }

    private enum CodingKeys: String, CodingKey {
        case frame, lines
    }

    /// Writes `"frame": null` instead of omitting the key, so every fixture has both keys.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frame, forKey: .frame)
        try container.encode(lines, forKey: .lines)
    }

    /// Ghostty's `AXValue` separates rows with `\n`; every row is kept, including trailing spaces.
    public static func lines(fromAXValue value: String) -> [String] {
        value.components(separatedBy: "\n")
    }

    /// `tmux capture-pane -p` ends every row with `\n`, so the empty piece after the last one is dropped.
    public static func lines(fromTmuxCapture output: String) -> [String] {
        var lines = output.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    public func sanitized(with sanitizer: FixtureSanitizer) -> ScreenFixture {
        ScreenFixture(frame: frame, lines: lines.map(sanitizer.sanitize))
    }

    /// Pretty-printed, sorted keys, one array element per line, slashes not escaped.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// Turns a raw capture into the bytes the capture tool writes; `HoverTalkCapture` writes
/// nothing else.
public enum FixtureExport {
    public struct Prepared: Sendable {
        public let fixture: ScreenFixture
        public let data: Data
    }

    public enum Failure: Error, Equatable {
        case leak(LeakGuard.Term)

        /// Names the kind of term only, never the term or the captured text.
        public var message: String {
            switch self {
            case let .leak(term):
                return "Refusing to write: the sanitized output still contains \(term.rawValue)."
            }
        }
    }

    /// Sanitizes `raw`, encodes it, and checks both the sanitized lines and the encoded JSON
    /// with `leakGuard`.
    /// - Throws: `Failure.leak` when a sensitive term survives; encoding errors otherwise.
    public static func prepare(
        _ raw: ScreenFixture,
        sanitizer: FixtureSanitizer,
        leakGuard: LeakGuard
    ) throws -> Prepared {
        let fixture = raw.sanitized(with: sanitizer)
        let data = try fixture.encoded()
        for text in [fixture.lines.joined(separator: "\n"), String(decoding: data, as: UTF8.self)] {
            if let term = leakGuard.firstLeak(in: text) { throw Failure.leak(term) }
        }
        return Prepared(fixture: fixture, data: data)
    }
}

/// What the capture tool prints about a sanitized fixture.
public struct FixtureSummary: Equatable, Sendable {
    public let lineCount: Int
    /// Longest line, in Characters.
    public let maxWidth: Int
    /// Distinct non-ASCII scalars as `U+XXXX`, in scalar order.
    public let nonASCIIScalars: [String]
    public let firstLines: [String]

    public init(_ fixture: ScreenFixture) {
        lineCount = fixture.lines.count
        maxWidth = fixture.lines.map(\.count).max() ?? 0
        let scalars = Set(fixture.lines.flatMap(\.unicodeScalars).filter { !$0.isASCII })
        nonASCIIScalars = scalars.map(\.value).sorted().map { String(format: "U+%04X", $0) }
        firstLines = Array(fixture.lines.prefix(3))
    }
}
