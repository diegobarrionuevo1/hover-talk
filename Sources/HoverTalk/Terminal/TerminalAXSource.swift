import ApplicationServices
import CoreGraphics

/// Reads the terminal screen under a point through Accessibility. Ghostty exposes its whole
/// visible screen as one `AXTextArea` whose `AXValue` holds every row separated by `\n`
/// (AX probes of 2026-10-16, `odd/tasks/hovertalk.md`).
enum TerminalAXSource {
    struct Screen: Equatable {
        /// One string per row, as `TerminalGridProvider` expects.
        let lines: [String]
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

        var hit: AXUIElement?
        switch AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) {
        case .success:
            break
        case .apiDisabled:
            // AXError.h: "The accessibility API is disabled". Defensive, not observed: it would
            // cover a permission revoked between the check above and this call.
            throw .notTrusted
        default:
            throw .noElement
        }
        guard let element = hit else { throw .noElement }
        guard attribute(of: element, kAXRoleAttribute) as? String == kAXTextAreaRole,
              let value = attribute(of: element, kAXValueAttribute) as? String
        else { throw .notATextArea }
        guard let frame = frame(of: element) else { throw .noFrame }
        return Screen(lines: value.components(separatedBy: "\n"), frame: frame)
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
