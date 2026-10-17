import AppKit
import ApplicationServices
import HoverTalkCore
import HoverTalkFixtureKit

/// Reads the frontmost app's text area through Accessibility. The raw text stays in memory;
/// callers sanitize it before anything is written or printed.
enum AXCapture {
    enum Failure: Error {
        case notTrusted
        case noFrontmostApp
        case noTextArea(app: String, focusedRole: String?, hoveredRole: String?)
        case noFrame

        var message: String {
            switch self {
            case .notTrusted:
                return "This process is not trusted for Accessibility. Grant it to the terminal app in System Settings > Privacy & Security > Accessibility."
            case .noFrontmostApp:
                return "There is no frontmost app."
            case let .noTextArea(app, focusedRole, hoveredRole):
                return "Frontmost app \(app): neither the focused element (\(focusedRole ?? "none")) nor the element under the mouse (\(hoveredRole ?? "none")) is an AXTextArea with a string value."
            case .noFrame:
                return "The text area has no readable AXPosition/AXSize."
            }
        }
    }

    @MainActor
    static func capture() throws(Failure) -> ScreenFixture {
        guard AXIsProcessTrusted() else { throw .notTrusted }
        guard let app = NSWorkspace.shared.frontmostApplication else { throw .noFrontmostApp }
        let appName = "\(app.localizedName ?? "?") (\(app.bundleIdentifier ?? "no bundle id"))"

        let focused = element(attribute(of: AXUIElementCreateApplication(app.processIdentifier), kAXFocusedUIElementAttribute))
        let hovered = elementUnderMouse()
        guard let (textArea, value) = [focused, hovered].lazy.compactMap({ textAreaValue($0) }).first else {
            throw .noTextArea(app: appName, focusedRole: role(of: focused), hoveredRole: role(of: hovered))
        }
        guard let frame = frame(of: textArea) else { throw .noFrame }
        // The rows the app parses: also split after soft-wrapped rows, which Ghostty's value
        // does not end with `\n`.
        return ScreenFixture(frame: frame, lines: AXScreenRows.split(value))
    }

    private static func attribute(of element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func role(of element: AXUIElement?) -> String? {
        element.flatMap { attribute(of: $0, kAXRoleAttribute) as? String }
    }

    private static func textAreaValue(_ element: AXUIElement?) -> (AXUIElement, String)? {
        guard let element, role(of: element) == kAXTextAreaRole,
              let value = attribute(of: element, kAXValueAttribute) as? String
        else { return nil }
        return (element, value)
    }

    /// AX coordinates start at the top-left of the primary screen; `NSEvent.mouseLocation`
    /// starts at its bottom-left.
    @MainActor
    private static func elementUnderMouse() -> AXUIElement? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        let mouse = NSEvent.mouseLocation
        var hit: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(), Float(mouse.x), Float(primaryHeight - mouse.y), &hit
        )
        return result == .success ? hit : nil
    }

    private static func frame(of element: AXUIElement) -> ScreenFixture.Frame? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = axValue(attribute(of: element, kAXPositionAttribute)),
              let extent = axValue(attribute(of: element, kAXSizeAttribute)),
              AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(extent, .cgSize, &size)
        else { return nil }
        return ScreenFixture.Frame(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }

    private static func axValue(_ value: CFTypeRef?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
