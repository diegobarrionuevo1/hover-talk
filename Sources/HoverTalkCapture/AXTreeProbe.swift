import AppKit
import ApplicationServices

/// Prints the accessibility tree of one running app's frontmost window as structure only, to
/// learn where an app keeps its readable text and which attributes reach it.
///
/// Privacy: no text from the app is ever printed: no values, titles, descriptions, help
/// strings or URLs. Only roles, subroles, child counts, the character count of a string
/// `AXValue`, frames, the bundle identifier and attribute names.
///
/// It never brings the app to the front, clicks or types. `--enable-web-ax` only sets
/// `AXManualAccessibility` and `AXEnhancedUserInterface` on the app element, the switches that
/// ask Chromium and Electron apps to build their web accessibility tree. They are not reset.
enum AXTreeProbe {
    static let defaultDepth = 14
    private static let maxLines = 200
    /// Bounds the walk so a huge web tree cannot keep the probe running for minutes.
    private static let maxNodes = 20_000
    private static let webAXAttributes = ["AXManualAccessibility", "AXEnhancedUserInterface"]
    /// Read in one round trip per node, in this order (see `Walker.visit`).
    private static let nodeAttributes = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXChildrenAttribute,
        kAXValueAttribute, kAXPositionAttribute, kAXSizeAttribute,
    ]

    /// Prints the report and returns the exit status: 0 probed, 1 when the app or its window
    /// cannot be read.
    @MainActor
    static func run(bundleID: String, depth: Int, enableWebAX: Bool) -> Int32 {
        guard AXIsProcessTrusted() else {
            printError("This process is not trusted for Accessibility. Grant it to the terminal app in System Settings > Privacy & Security > Accessibility.")
            return 1
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            printError("No running app with bundle id \(bundleID).")
            return 1
        }
        print("app: \(bundleID), pid \(app.processIdentifier)")
        // The global timeout: an app that does not answer must not hang the walk.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 3)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        if enableWebAX {
            for name in webAXAttributes {
                let result = AXUIElementSetAttributeValue(appElement, name as CFString, kCFBooleanTrue)
                print("set \(name) = true: AXError \(result.rawValue)")
            }
            Thread.sleep(forTimeInterval: 1)
        }

        let focused = element(attribute(of: appElement, kAXFocusedWindowAttribute))
        let windows = (attribute(of: appElement, kAXWindowsAttribute) as? [AnyObject])?.compactMap { element($0) } ?? []
        guard let window = focused ?? windows.first else {
            printError("\(bundleID) has neither an AXFocusedWindow nor AXWindows.")
            return 1
        }
        print("window: \(focused != nil ? "AXFocusedWindow" : "first of AXWindows"), \(windows.count) AXWindows")

        let walker = Walker(depthLimit: depth)
        let root = walker.visit(window, depth: 0)
        var lines: [(text: String, nodes: Int)] = []
        render([root], into: &lines)
        print("tree (depth limit \(depth); identical-shape sibling runs collapsed, the first one expanded):")
        for line in lines.prefix(maxLines) {
            print(line.text)
        }
        let hidden = lines.dropFirst(maxLines).reduce(0) { $0 + $1.nodes }
        if hidden > 0 {
            print("… \(hidden) more nodes")
        }

        print("nodes: \(walker.visited) visited; \(walker.cutAtDepthLimit) at the depth limit have unvisited children")
        if walker.stoppedEarly {
            print("stopped after \(maxNodes) nodes")
        }
        print("text (string AXValue with characters, or AXStaticText), by depth and role:")
        for key in walker.text.keys.sorted(by: { ($0.depth, $0.role) < ($1.depth, $1.role) }) {
            let tally = walker.text[key]!
            print("  depth \(key.depth) \(key.role): \(tally.nodes) nodes, \(tally.characters) characters")
        }
        print("attributes by role (first element seen):")
        for role in walker.roles {
            let names = walker.attributeNames[role]!
            print("  \(role)")
            print("    attributes: \(list(names.plain))")
            print("    parameterized: \(list(names.parameterized))")
        }
        return 0
    }

    private struct Node {
        let role: String
        let subrole: String?
        let childCount: Int
        let valueChars: Int?
        let frame: CGRect?
        let depth: Int
        var children: [Node] = []

        func hasSameShape(as other: Node) -> Bool {
            role == other.role && subrole == other.subrole && childCount == other.childCount
        }
    }

    private struct TextKey: Hashable {
        let depth: Int
        let role: String
    }

    private struct TextTally {
        var nodes = 0
        var characters = 0
    }

    /// Walks the tree once, keeping only structure and counts.
    private final class Walker {
        let depthLimit: Int
        private(set) var visited = 0
        private(set) var stoppedEarly = false
        private(set) var cutAtDepthLimit = 0
        private(set) var roles: [String] = []
        private(set) var attributeNames: [String: (plain: [String], parameterized: [String])] = [:]
        private(set) var text: [TextKey: TextTally] = [:]

        init(depthLimit: Int) {
            self.depthLimit = depthLimit
        }

        func visit(_ element: AXUIElement, depth: Int) -> Node {
            visited += 1
            let values = AXTreeProbe.values(of: element)
            let role = values[0] as? String ?? "(no role)"
            let children = (values[2] as? [AnyObject])?.compactMap { AXTreeProbe.element($0) } ?? []
            // Only the count leaves this function; the string itself is dropped here.
            let valueChars = (values[3] as? String)?.count
            var node = Node(
                role: role,
                subrole: values[1] as? String,
                childCount: children.count,
                valueChars: valueChars,
                frame: AXTreeProbe.frame(position: values[4], size: values[5]),
                depth: depth
            )

            if attributeNames[role] == nil {
                roles.append(role)
                attributeNames[role] = (AXTreeProbe.attributeNames(of: element), AXTreeProbe.parameterizedAttributeNames(of: element))
            }
            if (valueChars ?? 0) > 0 || role == kAXStaticTextRole {
                text[TextKey(depth: depth, role: role), default: TextTally()].nodes += 1
                text[TextKey(depth: depth, role: role), default: TextTally()].characters += valueChars ?? 0
            }

            guard depth < depthLimit else {
                if !children.isEmpty { cutAtDepthLimit += 1 }
                return node
            }
            for child in children {
                guard visited < AXTreeProbe.maxNodes else {
                    stoppedEarly = true
                    break
                }
                node.children.append(visit(child, depth: depth + 1))
            }
            return node
        }
    }

    /// One line per node; a run of siblings with the same shape becomes one line with `×N`, and
    /// only the first of the run is expanded.
    private static func render(_ siblings: [Node], into lines: inout [(text: String, nodes: Int)]) {
        var index = 0
        while index < siblings.count {
            let node = siblings[index]
            var run = 1
            while index + run < siblings.count, siblings[index + run].hasSameShape(as: node) {
                run += 1
            }
            lines.append((line(for: node, repeated: run), run))
            render(node.children, into: &lines)
            index += run
        }
    }

    private static func line(for node: Node, repeated: Int) -> String {
        var text = String(repeating: "  ", count: node.depth) + node.role
        if let subrole = node.subrole {
            text += " (\(subrole))"
        }
        text += " children=\(node.childCount)"
        if let valueChars = node.valueChars {
            text += " valueChars=\(valueChars)"
        }
        text += " " + (node.frame.map(describe) ?? "frame=none")
        if repeated > 1 {
            text += " ×\(repeated)"
        }
        return text
    }

    /// `nodeAttributes` in one round trip, falling back to one call each. Missing attributes
    /// are `nil`.
    private static func values(of element: AXUIElement) -> [CFTypeRef?] {
        var batch: CFArray?
        if AXUIElementCopyMultipleAttributeValues(element, nodeAttributes as CFArray, [], &batch) == .success,
           let items = batch as? [AnyObject], items.count == nodeAttributes.count {
            return items.map { isError($0) ? nil : $0 }
        }
        return nodeAttributes.map { attribute(of: element, $0) }
    }

    /// A batch read reports a missing attribute as an `AXValue` holding its `AXError`.
    private static func isError(_ value: AnyObject) -> Bool {
        CFGetTypeID(value) == AXValueGetTypeID() && AXValueGetType(value as! AXValue) == .axError
    }

    private static func attributeNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    private static func parameterizedAttributeNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyParameterizedAttributeNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    private static func list(_ names: [String]) -> String {
        names.isEmpty ? "(none)" : names.joined(separator: ", ")
    }

    private static func attribute(of element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func frame(position: CFTypeRef?, size: CFTypeRef?) -> CGRect? {
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID(),
              AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent)
        else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    private static func describe(_ rect: CGRect) -> String {
        "(\(format(rect.minX)), \(format(rect.minY)), \(format(rect.width)) × \(format(rect.height)))"
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.0f", Double(value))
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
