import ApplicationServices
import CoreGraphics
import Foundation

/// Reads the terminal screen under a point through Accessibility. Ghostty exposes its whole
/// visible screen as one `AXTextArea` whose `AXValue` holds its rows separated by `\n` (AX
/// probes of 2026-10-16, `odd/tasks/hovertalk.md`), except after a soft-wrapped row (probe of
/// 2026-10-17, see `AXScreenRows`).
enum TerminalAXSource {
    struct Screen: Equatable {
        /// The text area's `AXValue`: rows separated by `\n`, except after a soft-wrapped row
        /// (see `AXScreenRows`). `ScreenBlockCache` splits it into rows and keys on it.
        let value: String
        /// The text area's frame in AX coordinates (top-left origin of the primary screen).
        let frame: CGRect
    }

    /// Holds no screen text: `PickerLog` logs these values.
    enum Failure: Error, Hashable {
        /// The process lacks the Accessibility permission: `AXIsProcessTrusted()` returned false.
        case notTrusted
        /// The hit test at the point returned this `AXError` raw value, with the process trusted
        /// when the call began (and again after `.apiDisabled`, see `element(at:in:)`): the app
        /// under the point did not answer it.
        case hitTestFailed(axError: Int32)
        /// The hit test found no element at the point.
        case noElement
        /// The element at the point is not an `AXTextArea` with a string value; `role` is its
        /// `AXRole`, or `nil` when it has none.
        case notATextArea(role: String?)
        /// The text area has no readable `AXPosition`/`AXSize`.
        case noFrame
    }

    /// The text area at `point`, in AX global coordinates. Use `try?` when the reason does not
    /// matter. `Failure.notTrusted` is thrown only when `AXIsProcessTrusted()` returned false, so
    /// a caller can update its permission status from it; any other failure concerns the app
    /// under the point.
    static func screen(at point: CGPoint) throws(Failure) -> Screen {
        guard AXIsProcessTrusted() else { throw .notTrusted }

        var element = try self.element(at: point, in: AXUIElementCreateSystemWide())
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if pid(of: element) == ownPID {
            // Defensive, not observed: if this app's own window (such as the picker overlay)
            // is the one hit at the point, ask the app whose window lies under it instead.
            guard let owner = windowOwner(at: point, excluding: ownPID) else { throw .noElement }
            element = try self.element(at: point, in: AXUIElementCreateApplication(owner))
        }
        let role = attribute(of: element, kAXRoleAttribute) as? String
        guard role == kAXTextAreaRole, let value = attribute(of: element, kAXValueAttribute) as? String
        else { throw .notATextArea(role: role) }
        guard let frame = frame(of: element) else { throw .noFrame }
        return Screen(value: value, frame: frame)
    }

    /// The process owning the frontmost normal-level window that contains `point`, other than
    /// this app (see `windowOwner(at:excluding:)`). For diagnostics: the app a failure concerns.
    static func applicationPID(at point: CGPoint) -> pid_t? {
        windowOwner(at: point, excluding: ProcessInfo.processInfo.processIdentifier)
    }

    /// Caps how long each AX call of this process waits for an app to answer, so a hung app
    /// cannot stall a reader. Set on the system-wide element, it applies to every element of
    /// the process (AXUIElement.h, `AXUIElementSetMessagingTimeout`). Returns whether it was set.
    @discardableResult
    static func setMessagingTimeout(seconds: Float) -> Bool {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), seconds) == .success
    }

    /// The element at `point` below `root` (the system-wide element or an application element).
    private static func element(at point: CGPoint, in root: AXUIElement) throws(Failure) -> AXUIElement {
        var hit: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &hit)
        guard error == .success else {
            // AXError.h: `.apiDisabled` is "The accessibility API is disabled". Reported on its
            // own as a missing permission, it was the one route to the permission alert that
            // depended on the app under the pointer, and that alert showed over Chrome, Claude and
            // ChatGPT while picking worked in Ghostty (founder report, 2026-10-21). So only a
            // trust check that fails again reports the permission missing; any other error means
            // that app did not answer, which reads as nothing to read.
            if error == .apiDisabled, !AXIsProcessTrusted() { throw .notTrusted }
            throw .hitTestFailed(axError: error.rawValue)
        }
        guard let hit else { throw .noElement }
        return hit
    }

    private static func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }

    /// The process owning the frontmost normal-level (layer 0) on-screen window that contains
    /// `point`, other than `excluded`. `CGWindowListCopyWindowInfo` lists on-screen windows
    /// front to back (CGWindow.h), with bounds in global coordinates whose origin is the
    /// primary screen's top-left corner, as in AX.
    private static func windowOwner(at point: CGPoint, excluding excluded: pid_t) -> pid_t? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != excluded,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let boundsInfo = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                  bounds.contains(point)
            else { continue }
            return pid
        }
        return nil
    }

    private static func attribute(of element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = axValue(attribute(of: element, kAXPositionAttribute)),
              let extent = axValue(attribute(of: element, kAXSizeAttribute)),
              AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(extent, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func axValue(_ value: CFTypeRef?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
