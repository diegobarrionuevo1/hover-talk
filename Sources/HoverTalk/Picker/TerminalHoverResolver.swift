import CoreGraphics
import HoverTalkCore

/// Finds the terminal block under a point away from the main thread: each AX call waits for
/// the terminal to answer (up to the messaging timeout `AppDelegate` sets), and parsing a
/// changed screen takes milliseconds. One lookup runs at a time, since this is an actor and
/// `lookup(at:)` never suspends; `PickerController` also starts at most one at a time.
actor TerminalHoverResolver {
    enum Lookup: Sendable {
        /// The block under the point, or `nil` over anything that is not a terminal block.
        case target(HoverTarget?)
        /// The Accessibility permission is missing or was revoked.
        case notTrusted
    }

    private var cache = ScreenBlockCache()

    func lookup(at point: CGPoint) -> Lookup {
        do {
            let screen = try TerminalAXSource.screen(at: point)
            return .target(cache.block(at: point, value: screen.value, frame: screen.frame).map { HoverTarget($0) })
        } catch .notTrusted {
            return .notTrusted
        } catch {
            return .target(nil)
        }
    }
}
