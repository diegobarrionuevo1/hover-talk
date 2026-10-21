import ApplicationServices
import CoreGraphics
import Foundation
import HoverTalkCore

/// Finds text under a point, or dragged over, away from the main thread: terminal text areas
/// first (`TerminalAXSource`), and any other app through its accessibility tree
/// (`AccessibleAXSource`, `AXBlockReader`). Each AX
/// call waits for the terminal to answer (up to the messaging timeout `AppDelegate` sets), and
/// parsing a changed screen takes milliseconds. One lookup runs at a time, since this is an
/// actor and none of its methods suspends; `PickerController` and the `ReadingHighlighter` it
/// shares this resolver with each start at most one at a time, except a drag's final
/// selection, which `PickerController` starts while a live lookup may still run.
actor TerminalHoverResolver {
    enum Lookup: Sendable {
        /// The block or selection found on a terminal screen, or `nil` when none is there.
        case target(HoverTarget?)
        /// No terminal screen could be read at the point, such as over an app that is not a
        /// terminal or did not answer; never `.notTrusted`. Means nothing to read, as
        /// `.target(nil)` does.
        case unreadable(TerminalAXSource.Failure)
        /// The Accessibility permission is missing or was revoked: `AXIsProcessTrusted()`
        /// returned false.
        case notTrusted
    }

    private var cache = ScreenBlockCache()
    private let blockReader = AXBlockReader()
    /// The last accessibility snapshot, reused while the pointer stays over the same area for
    /// `snapshotLifetime`: hover lookups run several times a second, and a snapshot of a chat
    /// transcript costs tens of milliseconds.
    private var snapshot: (value: AccessibleAXSource.Snapshot, time: Date)?
    private static let snapshotLifetime: TimeInterval = 1.5
    /// Apps already asked to build their web accessibility tree.
    private var webAccessibilityRequested = Set<pid_t>()

    /// The block under `point`, read as `mode` says (see `ParsedScreen.block(at:mode:)`).
    func lookup(at point: CGPoint, mode: ReadingMode) -> Lookup {
        read(at: point, terminal: { $0.block(at: point, mode: mode) }, accessible: { reader, root in
            // Outline only the pointed block, even in continuous mode, so a long page is not
            // covered by one outline; the continuation is what a click reads.
            guard let block = reader.block(at: point, in: root) else { return nil }
            let read = mode == .continuous ? reader.continuation(from: point, in: root) ?? block : block
            return (outline: block, read: read)
        })
    }

    /// The text dragged over from `start` to `end`, on the terminal text area under `start`
    /// (see `ParsedScreen.selection(from:to:)`).
    func selection(from start: CGPoint, to end: CGPoint) -> Lookup {
        read(at: start, terminal: { $0.selection(from: start, to: end) }, accessible: { reader, root in
            reader.selection(from: start, to: end, in: root).map { (outline: $0, read: $0) }
        })
    }

    /// The terminal screen at `point`, parsed through the same cache as `lookup(at:mode:)`, or
    /// `nil` when no terminal text area can be read there (the Accessibility permission included).
    func screen(at point: CGPoint) -> ParsedScreen? {
        guard let screen = try? TerminalAXSource.screen(at: point) else { return nil }
        return cache.screen(value: screen.value, frame: screen.frame)
    }

    /// `terminal` on the parsed screen of the terminal text area at `point`; when the element
    /// there is not a terminal text area, `accessible` on the accessibility snapshot of its
    /// reading area.
    private func read(
        at point: CGPoint,
        terminal: (ParsedScreen) -> TerminalTextBlock?,
        accessible: (AXBlockReader, AXNode) -> (outline: AXBlock, read: AXBlock)?
    ) -> Lookup {
        do throws(TerminalAXSource.Failure) {
            let screen = try TerminalAXSource.screen(at: point)
            return .target(terminal(cache.screen(value: screen.value, frame: screen.frame)).map { HoverTarget($0) })
        } catch .notTrusted {
            return .notTrusted
        } catch .notATextArea {
            return readAccessible(at: point, accessible)
        } catch {
            return .unreadable(error)
        }
    }

    private func readAccessible(at point: CGPoint, _ find: (AXBlockReader, AXNode) -> (outline: AXBlock, read: AXBlock)?) -> Lookup {
        let area: (element: AXUIElement, pid: pid_t, hash: Int)
        do throws(AccessibleAXSource.Failure) {
            area = try AccessibleAXSource.area(at: point)
        } catch .notTrusted {
            return .notTrusted
        } catch {
            return .target(nil)
        }
        if webAccessibilityRequested.insert(area.pid).inserted {
            PickerLog.webAccessibilityRequested(results: AccessibleAXSource.requestWebAccessibility(pid: area.pid))
        }
        let now = Date()
        let current: AccessibleAXSource.Snapshot
        if let cached = snapshot, cached.value.pid == area.pid, cached.value.areaHash == area.hash,
           now.timeIntervalSince(cached.time) < Self.snapshotLifetime {
            current = cached.value
        } else {
            current = AccessibleAXSource.snapshot(of: area)
            snapshot = (current, now)
        }
        guard let found = find(blockReader, current.root), !found.outline.rects.isEmpty,
              !found.read.text.text.allSatisfy(\.isWhitespace)
        else { return .target(nil) }
        return .target(HoverTarget(rects: found.outline.rects, text: found.read.text.text, accessible: found.read.text))
    }
}
