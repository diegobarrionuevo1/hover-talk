import AppKit
import ApplicationServices
import HoverTalkCore

/// Reads the text selected in the frontmost app: the Accessibility selection first, then a
/// Cmd+C copy with the user's clipboard put back (`SelectionCopy`). Terminals expose no selected
/// text through Accessibility, so they always take the copy route.
@MainActor
final class SelectionReadController {
    /// Called when the Accessibility permission is missing: both routes need it.
    var onUnavailable: ((PickerUnavailableReason) -> Void)?

    private let readingSession: ReadingSession
    private let cleaner = TextCleaner()
    private var running: Task<Void, Never>?

    init(readingSession: ReadingSession) {
        self.readingSession = readingSession
    }

    /// Reads what is selected now. A second press while a read is being fetched is ignored.
    func readSelection() {
        guard AccessibilityPermission.currentStatus() == .granted else {
            onUnavailable?(.notTrusted)
            return
        }
        guard running == nil else { return }
        running = Task { [weak self] in
            let text = await SelectionReader.read(axSelection: Self.accessibilitySelection, copy: Self.copySelection)
            guard let self else { return }
            self.running = nil
            guard let text else { return }
            let spoken = self.cleaner.clean(text)
            if !spoken.isEmpty { self.readingSession.read(spoken) }
        }
    }

    // MARK: - Sources

    /// `AXSelectedText` of the focused element, as the system-wide element reports it.
    private nonisolated static func accessibilitySelection() -> String? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success
        else { return nil }
        return selected as? String
    }

    private nonisolated static func copySelection() async -> String? {
        await waitForModifiersReleased()
        return await SelectionCopy.copiedText(
            from: SystemPasteboard(),
            sendCopy: sendCommandC,
            sleep: { try? await Task.sleep(for: .seconds($0)) }
        )
    }

    /// The hotkey's own modifiers are still down when this runs; a Cmd+C sent then would reach
    /// the app as Control-Option-Cmd-C. Gives up after a second and sends it anyway.
    private nonisolated static func waitForModifiersReleased() async {
        let held: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        for _ in 0..<50 where !CGEventSource.flagsState(.combinedSessionState).isDisjoint(with: held) {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Cmd+C (key code 0x08, `kVK_ANSI_C`) with exactly the Command flag.
    private nonisolated static func sendCommandC() {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: keyDown) else { continue }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
    }
}
