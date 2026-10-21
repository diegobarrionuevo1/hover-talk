import Carbon.HIToolbox
import CoreGraphics
import HoverTalkCore

/// While started, a session-level event tap, inserted ahead of the other session-level taps,
/// that consumes left clicks, drags and Esc as `PickerInputFilter` decides, so they never reach
/// the app under the pointer (Esc would interrupt a running OpenCode agent; a click could move
/// tmux's pane focus), and reports each click and Esc through `onEvent` and each drag through
/// `onDrag`. Mouse locations are `CGEvent.location`: global display coordinates with the origin
/// at the main display's top-left corner, the coordinates AX uses.
@MainActor
final class PickerEventTap {
    /// Called on the main thread after the tap's callback has returned, so it may stop the tap.
    var onEvent: ((PickerEvent) -> Void)?
    /// Called like `onEvent`, with the drag the event moved or released.
    var onDrag: ((PickerDrag) -> Void)?

    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var filter = PickerInputFilter()

    /// Returns `false` when macOS refuses the tap (`CGEvent.tapCreate` returns `nil`), such as
    /// for a tap that can consume events in a process without the Accessibility permission.
    /// Logs the result (`PickerLog`).
    func start() -> Bool {
        guard port == nil else { return true }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: pickerEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        PickerLog.inputCapture(created: port != nil)
        guard let port else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        // The main run loop runs the callback on the main thread, which the callback relies on.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        filter = PickerInputFilter()
        self.port = port
        self.source = source
        return true
    }

    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
        self.port = nil
        source = nil
    }

    /// Whether to consume the event.
    fileprivate func handle(_ type: CGEventType, keyCode: Int64, location: CGPoint, flags: CGEventFlags) -> Bool {
        switch type {
        case .tapDisabledByTimeout:
            // macOS disables a tap whose callback is too slow; keep capturing while started.
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        case .tapDisabledByUserInput:
            // Clicks and Esc would now reach the app under the pointer, so picking must end.
            deliver(.cancel)
            return false
        case .keyDown where PickerInputFilter.isSystemShortcut(
            command: flags.contains(.maskCommand), shift: flags.contains(.maskShift)
        ):
            // A screenshot or other system chord: let it through and end capture, so its
            // crosshair click reaches the system instead of being read as a pick.
            deliver(.systemShortcut)
            return false
        default:
            break
        }
        guard port != nil, let input = Self.input(for: type, keyCode: keyCode, location: location) else { return false }
        let decision = filter.handle(input)
        if let event = decision.event { deliver(event) }
        if let drag = decision.drag { deliver(drag) }
        return decision.consume
    }

    /// Delivers `event` after the current callback returns: the handler may stop this tap, and
    /// a quick callback keeps macOS from disabling the tap.
    private func deliver(_ event: PickerEvent) {
        Task { @MainActor [weak self] in
            self?.onEvent?(event)
        }
    }

    /// As `deliver(_:)` for an event.
    private func deliver(_ drag: PickerDrag) {
        Task { @MainActor [weak self] in
            self?.onDrag?(drag)
        }
    }

    private static func input(for type: CGEventType, keyCode: Int64, location: CGPoint) -> PickerInput? {
        let isEscape = keyCode == Int64(kVK_Escape)
        switch type {
        case .leftMouseDown: return .mouseDown(location)
        case .leftMouseDragged: return .mouseDragged(location)
        case .leftMouseUp: return .mouseUp(location)
        case .keyDown where isEscape: return .escapeDown
        case .keyUp where isEscape: return .escapeUp
        default: return nil
        }
    }
}

/// The tap's run loop source is on the main run loop (`PickerEventTap.start()`), so this runs on
/// the main thread, which `MainActor.assumeIsolated` checks at run time. Returning `nil` consumes
/// the event.
private func pickerEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<PickerEventTap>.fromOpaque(userInfo).takeUnretainedValue()
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let location = event.location
    let flags = event.flags
    let consume = MainActor.assumeIsolated {
        tap.handle(type, keyCode: keyCode, location: location, flags: flags)
    }
    return consume ? nil : Unmanaged.passUnretained(event)
}
