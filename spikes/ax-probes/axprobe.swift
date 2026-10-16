import Cocoa
import ApplicationServices

// Probe: what text does macOS Accessibility expose for the app under the mouse?
func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}

func describe(_ el: AXUIElement, _ label: String) {
    let role = attr(el, kAXRoleAttribute) as? String ?? "?"
    let value = attr(el, kAXValueAttribute) as? String
    let sel = attr(el, kAXSelectedTextAttribute) as? String
    print("[\(label)] role=\(role) valueLen=\(value?.count ?? -1) selectedLen=\(sel?.count ?? -1)")
    if let v = value { print("  value head: \(v.prefix(200).replacingOccurrences(of: "\n", with: "⏎"))") }
    if let s = sel, !s.isEmpty { print("  selected: \(s.prefix(200).replacingOccurrences(of: "\n", with: "⏎"))") }
}

print("trusted=\(AXIsProcessTrusted())")
let sys = AXUIElementCreateSystemWide()
let front = NSWorkspace.shared.frontmostApplication
print("frontmost=\(front?.localizedName ?? "?")")

// Element under the mouse (AX uses top-left origin).
let m = NSEvent.mouseLocation
let h = NSScreen.screens.first?.frame.height ?? 0
var hit: AXUIElement?
if AXUIElementCopyElementAtPosition(sys, Float(m.x), Float(h - m.y), &hit) == .success, let el = hit {
    describe(el, "under-mouse")
    // Try to get the line under the mouse for text areas.
    var pt = CGPoint(x: m.x, y: h - m.y)
    if let axPt = AXValueCreate(.cgPoint, &pt) {
        var idx: AnyObject?
        if AXUIElementCopyParameterizedAttributeValue(el, kAXRangeForPositionParameterizedAttribute as CFString, axPt, &idx) == .success {
            print("  rangeForPosition supported: \(idx!)")
        } else { print("  rangeForPosition NOT supported") }
    }
} else { print("[under-mouse] no element") }

if let pid = front?.processIdentifier {
    let app = AXUIElementCreateApplication(pid)
    if let f = attr(app, kAXFocusedUIElementAttribute) { describe(f as! AXUIElement, "focused") }
    else { print("[focused] none") }
}
