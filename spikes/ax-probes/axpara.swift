import Cocoa
// Prototype: paragraph under the mouse in a terminal that exposes its screen as one AXTextArea.
func attr(_ el: AXUIElement, _ n: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(el, n as CFString, &v) == .success ? v : nil }
let app = AXUIElementCreateApplication(NSWorkspace.shared.frontmostApplication!.processIdentifier)
let el = attr(app, kAXFocusedUIElementAttribute) as! AXUIElement
let lines = (attr(el, kAXValueAttribute) as! String).components(separatedBy: "\n")
var pos = CGPoint.zero, size = CGSize.zero
AXValueGetValue(attr(el, kAXPositionAttribute) as! AXValue, .cgPoint, &pos)
AXValueGetValue(attr(el, kAXSizeAttribute) as! AXValue, .cgSize, &size)
let screenH = NSScreen.screens.first!.frame.height
let mouseY = screenH - NSEvent.mouseLocation.y
let row = Int((mouseY - pos.y) / (size.height / CGFloat(lines.count)))
// Strip TUI chrome: left gutter bar and right sidebar column.
func clean(_ l: String) -> String {
    var s = l
    if let r = s.range(of: "│", options: .backwards) { s = String(s[..<r.lowerBound]) }
    return s.replacingOccurrences(of: "┃", with: "").trimmingCharacters(in: .whitespaces)
}
guard row >= 0, row < lines.count else { print("mouse outside terminal (row \(row))"); exit(0) }
var a = row, b = row
while a > 0, !clean(lines[a-1]).isEmpty { a -= 1 }
while b < lines.count-1, !clean(lines[b+1]).isEmpty { b += 1 }
print("mouse row=\(row) paragraph rows \(a)...\(b)")
print((a...b).map { clean(lines[$0]) }.joined(separator: " "))
