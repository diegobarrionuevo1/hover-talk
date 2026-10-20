import AppKit
import HoverTalkCore

/// Runs picker mode: feeds the hotkey, pointer moves, clicks, drags and Esc to a `PickerState`
/// and performs the effects it returns, from capturing input and outlining to reading aloud.
@MainActor
final class PickerController {
    /// About 30 pointer checks per second.
    private static let trackingInterval: TimeInterval = 1.0 / 30
    /// While the pointer stays still, look up again every this many checks (about four times a
    /// second), so the outline follows text that changes under it.
    private static let stillRefreshTicks = 8

    /// Called when input capture could not start (see `PickerEventTap.start()`) or an AX read
    /// reported the Accessibility permission missing. Picking has already ended.
    var onNeedsAccessibility: (() -> Void)?

    /// What a lookup asks the resolver for.
    private enum Request: Equatable, Sendable {
        /// The block under the pointer, read as the mode says.
        case hover(CGPoint, ReadingMode)
        /// The text of the drag going on.
        case selection(from: CGPoint, to: CGPoint)
    }

    private let readingSession: ReadingSession
    private let preferences: Preferences
    private var state = PickerState()
    private let eventTap = PickerEventTap()
    private let overlay = HighlightOverlay()
    private let resolver = TerminalHoverResolver()

    private var trackingTimer: Timer?
    private var lastRequest: Request?
    private var ticksSinceLookup = 0
    private var isLookingUp = false
    /// Increases with each picking session, so a lookup that finishes after its session ended
    /// is dropped.
    private var session = 0
    /// The drag going on, from its press to the pointer's latest location (AX coordinates).
    private var drag: (start: CGPoint, end: CGPoint)?
    /// Increases when a drag is released, so a live selection lookup that finishes afterwards
    /// is dropped.
    private var dragGeneration = 0
    /// Where the next reading's screen source reads the screen again: the press of a released
    /// drag; `nil` for a click, which uses the point of the latest hover lookup.
    private var readPoint: CGPoint?

    init(readingSession: ReadingSession, preferences: Preferences) {
        self.readingSession = readingSession
        self.preferences = preferences
        eventTap.onEvent = { [weak self] event in
            self?.send(event)
        }
        eventTap.onDrag = { [weak self] drag in
            self?.handle(drag)
        }
    }

    /// Starts picking, or ends it when already picking: the hotkey and the menu item.
    func toggle() {
        send(.hotkey)
    }

    private func send(_ event: PickerEvent) {
        for effect in state.handle(event) {
            guard perform(effect) else {
                // Capture could not start: end picking before the rest of the effects, such as
                // showing the overlay, run.
                for cleanup in state.handle(.cancel) {
                    _ = perform(cleanup)
                }
                onNeedsAccessibility?()
                return
            }
        }
    }

    /// Returns `false` only when input capture could not start.
    private func perform(_ effect: PickerEffect) -> Bool {
        switch effect {
        case .startCapture:
            guard eventTap.start() else { return false }
            startTracking()
        case .stopCapture:
            eventTap.stop()
            stopTracking()
        case .showOverlay:
            readingSession.setPicking(true)
            overlay.show()
        case .hideOverlay:
            overlay.hide()
            readingSession.setPicking(false)
        case let .highlight(rects):
            overlay.highlight(rects)
        case let .read(text):
            readingSession.read(text)
        case let .readBlock(document, anchor):
            let point = readPoint ?? hoverPoint() ?? currentPoint() ?? .zero
            readingSession.read(document: document, screenSource: ReadingScreenSource(resolver: resolver, anchor: anchor, point: point))
        }
        return true
    }

    /// The pointer in AX coordinates, or `nil` without a screen.
    private func currentPoint() -> CGPoint? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        return AXCoordinates.fromCocoa(NSEvent.mouseLocation, primaryScreenHeight: primaryHeight)
    }

    /// Where the latest hover lookup looked.
    private func hoverPoint() -> CGPoint? {
        guard case let .hover(point, _) = lastRequest else { return nil }
        return point
    }

    // MARK: - Drags

    /// A moved drag only records where the pointer is; the tracking timer looks up its
    /// selection. A released drag looks up the final selection at once, which ends picking
    /// with a read or goes back to picking (`PickerState`).
    private func handle(_ drag: PickerDrag) {
        guard trackingTimer != nil else { return }
        switch drag {
        case let .moved(start, end):
            self.drag = (start, end)
        case let .released(start, end):
            self.drag = nil
            dragGeneration += 1
            let session = session
            Task {
                let lookup = await resolver.selection(from: start, to: end)
                finishSelection(lookup, start: start, session: session)
            }
        }
    }

    private func finishSelection(_ lookup: TerminalHoverResolver.Lookup, start: CGPoint, session: Int) {
        guard session == self.session, trackingTimer != nil else { return }
        switch lookup {
        case let .target(target):
            readPoint = start
            send(.selectionEnded(target))
            readPoint = nil
        case .notTrusted:
            send(.cancel)
            onNeedsAccessibility?()
        }
    }

    // MARK: - Pointer tracking

    private func startTracking() {
        session += 1
        lastRequest = nil
        drag = nil
        readPoint = nil
        ticksSinceLookup = 0
        let timer = Timer(timeInterval: Self.trackingInterval, repeats: true) { [weak self] _ in
            // Added to the main run loop below, so the block runs on the main thread.
            MainActor.assumeIsolated {
                self?.track()
            }
        }
        // `.common` keeps tracking while a menu or a modal panel runs its own run loop mode.
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
        track()
    }

    private func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        drag = nil
    }

    /// Looks up the block under the pointer, or during a drag its selection, when that changed,
    /// or now and then while it stays the same. A change during a lookup is picked up by the
    /// first check after it ends. The reading mode is read on every check, so a change applies
    /// to the next pick, even during this picking session.
    private func track() {
        let request: Request
        if let drag {
            request = .selection(from: drag.start, to: drag.end)
        } else if let point = currentPoint() {
            request = .hover(point, preferences.readingMode)
        } else {
            return
        }
        ticksSinceLookup += 1
        guard !isLookingUp, request != lastRequest || ticksSinceLookup >= Self.stillRefreshTicks else { return }

        lastRequest = request
        ticksSinceLookup = 0
        isLookingUp = true
        let session = session
        let dragGeneration = dragGeneration
        Task {
            let lookup = switch request {
            case let .hover(point, mode): await resolver.lookup(at: point, mode: mode)
            case let .selection(start, end): await resolver.selection(from: start, to: end)
            }
            finishLookup(lookup, for: request, session: session, dragGeneration: dragGeneration)
        }
    }

    private func finishLookup(_ lookup: TerminalHoverResolver.Lookup, for request: Request, session: Int, dragGeneration: Int) {
        isLookingUp = false
        guard session == self.session, trackingTimer != nil else { return }
        switch (lookup, request) {
        case let (.target(target), .hover):
            send(.hoverChanged(target))
        case let (.target(target), .selection):
            // A drag released meanwhile has its final selection looked up on its own.
            guard dragGeneration == self.dragGeneration, drag != nil else { return }
            send(.selectionChanged(target))
        case (.notTrusted, _):
            send(.cancel)
            onNeedsAccessibility?()
        }
    }
}
