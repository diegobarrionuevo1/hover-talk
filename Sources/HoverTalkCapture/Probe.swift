import AppKit
import ApplicationServices
import HoverTalkCore

/// Runs the picker's reading pipeline (`ScreenBlockCache`, then `TextCleaner` and
/// `SentenceSplitter`) on the element under the mouse and describes only its structure.
///
/// Privacy: no screen text is ever printed, only roles, geometry, pane layout, profile names
/// and counts.
enum Probe {
    /// Prints the report and returns the exit status: 0 probed (with or without a block),
    /// 1 when the element under the mouse cannot be read.
    @MainActor
    static func run() -> Int32 {
        guard AXIsProcessTrusted() else {
            printError("This process is not trusted for Accessibility. Grant it to the terminal app in System Settings > Privacy & Security > Accessibility.")
            return 1
        }
        guard let primaryHeight = NSScreen.screens.first?.frame.height else {
            printError("No screen.")
            return 1
        }
        let point = AXCoordinates.fromCocoa(NSEvent.mouseLocation, primaryScreenHeight: primaryHeight)
        print("point (AX): \(describe(point))")

        var hit: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit)
        guard result == .success, let element = hit else {
            printError("No element under the mouse (AXError \(result.rawValue)).")
            return 1
        }
        let role = attribute(of: element, kAXRoleAttribute) as? String
        print("role: \(role ?? "none")")
        guard let frame = frame(of: element) else {
            print("frame: none")
            return 1
        }
        print("frame: \(describe(frame))")
        guard role == kAXTextAreaRole, let value = attribute(of: element, kAXValueAttribute) as? String else {
            print("not an AXTextArea with a string value: no block")
            return 0
        }

        let axLines = value.components(separatedBy: "\n")
        let widths = Dictionary(grouping: axLines.map(cellCount), by: { $0 }).mapValues(\.count)
        print("AX lines: \(axLines.count); widths in cells: "
            + widths.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", "))

        var cache = ScreenBlockCache()
        let screen = cache.screen(value: value, frame: frame)
        print("grid: \(screen.grid.rowCount) rows × \(screen.grid.columns) columns")
        print("panes:")
        for (index, pane) in screen.panes.enumerated() {
            let profile = pane.profileName.map { ", \($0)" } ?? ""
            print("  \(index): rows \(describe(pane.pane.rows)), columns \(describe(pane.pane.columns)), \(pane.kind)\(profile)")
        }
        let cell = screen.geometry.cell(at: point)
        if let cell {
            print("cell under mouse: row \(cell.row), column \(cell.column)")
        }
        let paneIndex = cell.flatMap { cell in screen.panes.firstIndex { $0.pane.contains(cell) } }
        print("pane under mouse: \(paneIndex.map { "\($0) (\(screen.panes[$0].profileName ?? "not read"))" } ?? "none")")

        guard let block = cache.block(at: point, value: value, frame: frame) else {
            print("block: none")
            return 0
        }
        let spoken = TextCleaner().clean(block.text)
        print("block: rows \(describe(block.rows)), columns \(describe(block.columns)), rect \(describe(block.rect))")
        print("block text: \(block.text.count) characters; cleaned: \(spoken.count) characters, \(SentenceSplitter().split(spoken).count) sentences")
        return 0
    }

    private static func cellCount(_ line: String) -> Int {
        line.reduce(0) { $0 + TerminalGrid.cellWidth(of: $1) }
    }

    private static func describe(_ range: ClosedRange<Int>) -> String {
        "\(range.lowerBound)...\(range.upperBound)"
    }

    private static func describe(_ point: CGPoint) -> String {
        "(\(format(point.x)), \(format(point.y)))"
    }

    private static func describe(_ rect: CGRect) -> String {
        "(\(format(rect.minX)), \(format(rect.minY)), \(format(rect.width)) × \(format(rect.height)))"
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private static func attribute(of element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = attribute(of: element, kAXPositionAttribute),
              let extent = attribute(of: element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(extent) == AXValueGetTypeID(),
              AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(extent as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }
}
