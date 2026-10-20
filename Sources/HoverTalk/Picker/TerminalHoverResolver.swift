import CoreGraphics
import HoverTalkCore

/// Finds terminal text under a point, or dragged over, away from the main thread: each AX
/// call waits for the terminal to answer (up to the messaging timeout `AppDelegate` sets), and
/// parsing a changed screen takes milliseconds. One lookup runs at a time, since this is an
/// actor and none of its methods suspends; `PickerController` and the `ReadingHighlighter` it
/// shares this resolver with each start at most one at a time, except a drag's final
/// selection, which `PickerController` starts while a live lookup may still run.
actor TerminalHoverResolver {
    enum Lookup: Sendable {
        /// The block or selection found, or `nil` over anything that is not terminal text.
        case target(HoverTarget?)
        /// The Accessibility permission is missing or was revoked.
        case notTrusted
    }

    private var cache = ScreenBlockCache()

    /// The block under `point`, read as `mode` says (see `ParsedScreen.block(at:mode:)`).
    func lookup(at point: CGPoint, mode: ReadingMode) -> Lookup {
        read(at: point) { $0.block(at: point, mode: mode) }
    }

    /// The text dragged over from `start` to `end`, on the terminal text area under `start`
    /// (see `ParsedScreen.selection(from:to:)`).
    func selection(from start: CGPoint, to end: CGPoint) -> Lookup {
        read(at: start) { $0.selection(from: start, to: end) }
    }

    /// The terminal screen at `point`, parsed through the same cache as `lookup(at:mode:)`, or
    /// `nil` when no terminal text area can be read there (the Accessibility permission included).
    func screen(at point: CGPoint) -> ParsedScreen? {
        guard let screen = try? TerminalAXSource.screen(at: point) else { return nil }
        return cache.screen(value: screen.value, frame: screen.frame)
    }

    /// `find` on the parsed screen of the terminal text area at `point`.
    private func read(at point: CGPoint, _ find: (ParsedScreen) -> TerminalTextBlock?) -> Lookup {
        do {
            let screen = try TerminalAXSource.screen(at: point)
            return .target(find(cache.screen(value: screen.value, frame: screen.frame)).map { HoverTarget($0) })
        } catch .notTrusted {
            return .notTrusted
        } catch {
            return .target(nil)
        }
    }
}
