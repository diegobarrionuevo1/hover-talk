import ApplicationServices
import CoreGraphics
import Foundation
import HoverTalkCore

/// Reads the accessibility tree around a point into an `AXNode` snapshot for `AXBlockReader`:
/// web pages in browsers, Electron apps such as Claude and ChatGPT, and native apps.
///
/// Probe facts (2026-10-21, `HoverTalkCapture axtree`, structure only):
/// - Chromium and Electron build their web tree only after an assistive app asks, and
///   asynchronously: Claude's desktop app accepted `AXManualAccessibility` and showed its
///   conversation (about 960 nodes) a few seconds later; Chrome refused both switches
///   (AXError -25205 and -25208) yet exposed its page shortly after being queried.
/// - Claude's conversation lives in an `AXWebArea` nested inside another `AXWebArea`, so the
///   reading area is the nearest web area above the pointed element.
/// - A full snapshot took about 80 ms for 960 nodes (Claude) and 20 ms for 410 (Chrome).
enum AccessibleAXSource {
    struct Snapshot: Sendable {
        /// The reading area: the nearest `AXWebArea` above the pointed element, else the nearest
        /// `AXScrollArea`, else its window.
        let root: AXNode
        let pid: pid_t
        /// Identifies the area element between snapshots (`CFHash`), for caching.
        let areaHash: Int
    }

    enum Failure: Error, Equatable {
        case notTrusted
        case noElement
        /// The element under the point belongs to this app (such as an overlay).
        case ownElement
    }

    /// Bounds the walk so a huge page cannot stall the picker.
    static let maxNodes = 6_000
    private static let maxDepth = 150
    private static let areaRoles = ["AXWebArea", "AXScrollArea"]
    private static let inputRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"]
    private static let textRoles: Set<String> = ["AXStaticText"]
    /// Read in one round trip per node, in this order (see `node(_:depth:budget:)`).
    private static let attributeNames: [String] = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXValueAttribute, kAXPositionAttribute,
        kAXSizeAttribute, kAXChildrenAttribute, "AXDOMClassList", "AXEditableAncestor",
    ]

    /// The element under `point` and its reading area, without reading the area's content.
    static func area(at point: CGPoint) throws(Failure) -> (element: AXUIElement, pid: pid_t, hash: Int) {
        guard AXIsProcessTrusted() else { throw .notTrusted }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              let hit
        else { throw .noElement }
        var pid: pid_t = 0
        guard AXUIElementGetPid(hit, &pid) == .success else { throw .noElement }
        guard pid != ProcessInfo.processInfo.processIdentifier else { throw .ownElement }

        var scrollArea: AXUIElement?
        var window: AXUIElement?
        var current: AXUIElement? = hit
        var steps = 0
        while let element = current, steps < maxDepth {
            let role = string(element, kAXRoleAttribute)
            if role == "AXWebArea" { return (element, pid, Int(CFHash(element))) }
            if role == "AXScrollArea", scrollArea == nil { scrollArea = element }
            if role == "AXWindow" { window = element; break }
            current = parent(of: element)
            steps += 1
        }
        let area = scrollArea ?? window ?? hit
        return (area, pid, Int(CFHash(area)))
    }

    /// Reads the area as a snapshot (see `area(at:)`).
    static func snapshot(of area: (element: AXUIElement, pid: pid_t, hash: Int)) -> Snapshot {
        var budget = maxNodes
        let root = node(area.element, depth: 0, budget: &budget) ?? AXNode(role: "AXGroup")
        return Snapshot(root: root, pid: area.pid, areaHash: area.hash)
    }

    // MARK: - Web accessibility switches

    /// Asks a Chromium or Electron app to build its web accessibility tree; the caller does it
    /// once per process: `AXManualAccessibility` (Electron) first, then `AXEnhancedUserInterface`
    /// (Chromium) only when the first is refused, since the second is known to slow window
    /// animations in some apps. Native apps refuse both, which is harmless. Never reset.
    /// Returns the AXError raw values.
    @discardableResult
    static func requestWebAccessibility(pid: pid_t) -> [Int32] {
        let app = AXUIElementCreateApplication(pid)
        let manual = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard manual != .success else { return [manual.rawValue] }
        let enhanced = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        return [manual.rawValue, enhanced.rawValue]
    }

    // MARK: - Reading nodes

    private static func node(_ element: AXUIElement, depth: Int, budget: inout Int) -> AXNode? {
        guard budget > 0 else { return nil }
        budget -= 1
        var values: CFArray?
        AXUIElementCopyMultipleAttributeValues(element, attributeNames as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &values)
        let list = (values as? [AnyObject]) ?? []
        func value(_ index: Int) -> AnyObject? {
            guard index < list.count, !isError(list[index]) else { return nil }
            return list[index]
        }
        let role = value(0) as? String ?? "AXUnknown"
        let subrole = value(1) as? String
        let isInput = inputRoles.contains(role)
        let isEditable = isInput && (value(7) != nil || isSettable(element, kAXValueAttribute))
        let text = (textRoles.contains(role) || isInput) ? value(2) as? String : nil
        let classes = value(6) as? [String] ?? []
        var children: [AXNode] = []
        if depth < maxDepth, let elements = value(5) as? [AXUIElement] {
            for child in elements {
                guard let node = node(child, depth: depth + 1, budget: &budget) else { break }
                children.append(node)
            }
        }
        return AXNode(
            role: role, subrole: subrole, text: text, frame: frame(position: value(3), size: value(4)),
            isEditable: isEditable, isCode: AXCodeHint.isCode(domClasses: classes), children: children
        )
    }

    private static func isError(_ value: AnyObject) -> Bool {
        CFGetTypeID(value) == AXValueGetTypeID() && AXValueGetType(value as! AXValue) == .axError
    }

    private static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }

    private static func frame(position: AnyObject?, size: AnyObject?) -> CGRect {
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID(),
              AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent)
        else { return .zero }
        return CGRect(origin: origin, size: extent)
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value as? String : nil
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }
}
