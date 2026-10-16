import Cocoa
func attr(_ el: AXUIElement, _ n: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(el, n as CFString, &v) == .success ? v : nil }
let app = AXUIElementCreateApplication(NSWorkspace.shared.frontmostApplication!.processIdentifier)
let el = attr(app, kAXFocusedUIElementAttribute) as! AXUIElement
let v = attr(el, kAXValueAttribute) as! String
let lines = v.components(separatedBy: "\n")
var names: CFArray?; AXUIElementCopyParameterizedAttributeNames(el, &names)
print("lines=\(lines.count) maxWidth=\(lines.map{$0.count}.max()!)")
print("paramAttrs=\(names as? [String] ?? [])")
var pos = CGPoint.zero, size = CGSize.zero
AXValueGetValue(attr(el, kAXPositionAttribute) as! AXValue, .cgPoint, &pos)
AXValueGetValue(attr(el, kAXSizeAttribute) as! AXValue, .cgSize, &size)
print("frame=\(pos) \(size)")
for (i,l) in lines.enumerated() where i % 12 == 5 { print(String(format:"%3d|", i) + l.prefix(110)) }
