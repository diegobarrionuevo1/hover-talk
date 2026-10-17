import Carbon.HIToolbox
import HoverTalkCore

/// A system-wide shortcut registered with Carbon's `RegisterEventHotKey`, which needs no
/// Accessibility permission. Calls `action` each time the shortcut is pressed, whichever app
/// is active.
@MainActor
final class GlobalHotkey {
    /// 'HvTk': identifies this app's hotkeys in Carbon events.
    private static let signature: OSType = "HvTk".utf8.reduce(0) { $0 << 8 | OSType($1) }

    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// `nil` when the shortcut cannot be registered, such as when another app already holds it.
    init?(_ hotkey: Hotkey, action: @escaping () -> Void) {
        self.action = action

        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotkeyHandler,
            1,
            &pressed,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installed == noErr else { return nil }

        let registered = RegisterEventHotKey(
            hotkey.keyCode,
            Self.carbonModifiers(hotkey.modifiers),
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registered == noErr else {
            RemoveEventHandler(handlerRef)
            handlerRef = nil
            return nil
        }
    }

    /// Releases the shortcut. The handler holds an unretained pointer to this object, so call
    /// this before releasing it; the app keeps its one hotkey for its whole run.
    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }

    fileprivate func fire() {
        action()
    }

    private static func carbonModifiers(_ modifiers: Hotkey.Modifiers) -> UInt32 {
        var flags = 0
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        if modifiers.contains(.command) { flags |= cmdKey }
        return UInt32(flags)
    }
}

/// Carbon calls handlers installed on the application event target from the main run loop,
/// hence on the main thread, which `MainActor.assumeIsolated` checks at run time.
private func globalHotkeyHandler(
    _ call: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        hotkey.fire()
    }
    return noErr
}
