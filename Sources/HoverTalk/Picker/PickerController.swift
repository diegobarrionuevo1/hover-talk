import AppKit
import HoverTalkCore

/// Runs picker mode: feeds the hotkey, pointer moves, clicks and Esc to a `PickerState` and
/// performs the effects it returns, from capturing input and highlighting to reading aloud.
@MainActor
final class PickerController {
    /// About 30 pointer checks per second.
    private static let trackingInterval: TimeInterval = 1.0 / 30
    /// While the pointer stays still, look up again every this many checks (about four times a
    /// second), so the highlight follows text that changes under it.
    private static let stillRefreshTicks = 8

    /// Called when input capture could not start (see `PickerEventTap.start()`) or an AX read
    /// reported the Accessibility permission missing. Picking has already ended.
    var onNeedsAccessibility: (() -> Void)?

    private let readingSession: ReadingSession
    private var state = PickerState()
    private let eventTap = PickerEventTap()
    private let overlay = HighlightOverlay()
    private let resolver = TerminalHoverResolver()

    private var trackingTimer: Timer?
    private var lastPoint: CGPoint?
    private var ticksSinceLookup = 0
    private var isLookingUp = false
    /// Increases with each picking session, so a lookup that finishes after its session ended
    /// is dropped.
    private var session = 0

    init(readingSession: ReadingSession) {
        self.readingSession = readingSession
        eventTap.onEvent = { [weak self] event in
            self?.send(event)
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
            overlay.show()
        case .hideOverlay:
            overlay.hide()
        case let .highlight(rect):
            overlay.highlight(rect)
        case let .read(text):
            readingSession.read(text)
        }
        return true
    }

    // MARK: - Pointer tracking

    private func startTracking() {
        session += 1
        lastPoint = nil
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
    }

    /// Looks up the block under the pointer when the pointer moved, or now and then while it
    /// stays still. A move during a lookup is picked up by the first check after it ends.
    private func track() {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        let point = AXCoordinates.fromCocoa(NSEvent.mouseLocation, primaryScreenHeight: primaryHeight)
        ticksSinceLookup += 1
        guard !isLookingUp, point != lastPoint || ticksSinceLookup >= Self.stillRefreshTicks else { return }

        lastPoint = point
        ticksSinceLookup = 0
        isLookingUp = true
        let session = session
        Task {
            let lookup = await resolver.lookup(at: point)
            finishLookup(lookup, session: session)
        }
    }

    private func finishLookup(_ lookup: TerminalHoverResolver.Lookup, session: Int) {
        isLookingUp = false
        guard session == self.session, trackingTimer != nil else { return }
        switch lookup {
        case let .target(target):
            send(.hoverChanged(target))
        case .notTrusted:
            send(.cancel)
            onNeedsAccessibility?()
        }
    }
}
