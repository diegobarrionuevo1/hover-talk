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

    enum Failure: Error, Equatable {
        /// The process lacks the Accessibility permission.
        case notTrusted
        /// No element could be read at the point.
        case noElement
        /// The element at the point is not an `AXTextArea` with a string value.
        case notATextArea
        /// The text area has no readable `AXPosition`/`AXSize`.
        case noFrame
    }

    /// The text area at `point`, in AX global coordinates. Use `try?` when the reason does not
    /// matter. `Failure.notTrusted` means `AXIsProcessTrusted()` was false at call time, or AX
    /// reported its API disabled, so a caller can update its permission status from it.
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
        guard attribute(of: element, kAXRoleAttribute) as? String == kAXTextAreaRole,
              let value = attribute(of: element, kAXValueAttribute) as? String
        else { throw .notATextArea }
        guard let frame = frame(of: element) else { throw .noFrame }
        return Screen(value: value, frame: frame)
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
        switch AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &hit) {
        case .success:
            break
        case .apiDisabled:
            // AXError.h: "The accessibility API is disabled". Defensive, not observed: it would
            // cover a permission revoked between the trust check and this call.
            throw .notTrusted
        default:
            throw .noElement
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
