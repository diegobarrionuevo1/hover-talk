import CoreGraphics
import Foundation

/// A sanitized screen from `Fixtures/` (format and capture steps in `Fixtures/README.md`).
/// Decoded here rather than shared with `HoverTalkFixtureKit`, so these tests depend only on
/// the JSON format.
struct ScreenFixture: Decodable {
    /// The text area's frame in AX coordinates (top-left origin); `nil` for tmux pane captures.
    let frame: CGRect?
    let lines: [String]

    struct NotFound: Error {
        let name: String
    }

    /// Loads `Fixtures/<name>.json` from the test bundle.
    static func load(_ name: String) throws -> ScreenFixture {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw NotFound(name: name)
        }
        return try JSONDecoder().decode(ScreenFixture.self, from: Data(contentsOf: url))
    }

    private enum CodingKeys: String, CodingKey {
        case frame, lines
    }

    private struct Frame: Decodable {
        let x, y, width, height: Double
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frame = try container.decodeIfPresent(Frame.self, forKey: .frame)
            .map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        lines = try container.decode([String].self, forKey: .lines)
    }
}
