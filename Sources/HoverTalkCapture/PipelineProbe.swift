import AppKit
import ApplicationServices
import HoverTalkCore

/// Runs a whole terminal pick through the app's Core pipeline without the mouse: on the
/// focused `AXTextArea` of an app (such as Ghostty), it points at the first readable paragraph
/// of each program pane, then reports the hover outline, the click's reading document, its
/// paragraph ends, its highlight spans, and whether the reading anchor is found again on a
/// second read of the screen one second later.
///
/// Privacy: prints only counts, row ranges and offsets; never screen text.
enum PipelineProbe {
    @MainActor
    static func run(bundleID: String) -> Int32 {
        guard AXIsProcessTrusted() else {
            fail("This process is not trusted for Accessibility.")
            return 1
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            fail("No running app with bundle id \(bundleID).")
            return 1
        }
        guard let first = read(app.processIdentifier) else {
            fail("The app's focused element is not an AXTextArea with a frame.")
            return 1
        }
        var cache = ScreenBlockCache()
        let screen = cache.screen(value: first.value, frame: first.frame)
        print("grid: \(screen.grid.rowCount) rows × \(screen.grid.columns) columns; panes: \(screen.panes.count)")

        for (index, pane) in screen.panes.enumerated() where pane.kind == .program {
            print("pane \(index): rows \(pane.pane.rows), columns \(pane.pane.columns), \(pane.profileName ?? "-")")
            guard let (point, hover) = firstBlock(in: pane, of: screen) else {
                print("  no readable paragraph")
                continue
            }
            print("  hover: rows \(hover.rows), outline rects \(hover.rects.count), paragraphs \(hover.paragraphRows.count), anchor \(hover.anchor != nil)")
            var state = PickerState()
            _ = state.handle(.hotkey)
            _ = state.handle(.hoverChanged(HoverTarget(hover)))
            guard case let .readBlock(document, anchor) = state.handle(.click).last else {
                print("  click: no readBlock effect")
                continue
            }
            print("  document: \(document.sentences.count) sentences, paragraph ends \(document.anchors.paragraphEnds), spans \(document.spans.count), sentence 0 spans \(document.sentenceSpans.first?.count ?? 0), word spans at 0: \(document.wordSpans(sentence: 0, utf16Offset: 0).count)")
            print("  anchor on the same screen: row offset \(anchor.rowOffset(in: screen).map(String.init) ?? "lost")")
            Thread.sleep(forTimeInterval: 1)
            if let second = read(app.processIdentifier) {
                let again = cache.screen(value: second.value, frame: second.frame)
                print("  second read 1 s later: value changed \(second.value != first.value), anchor row offset \(anchor.rowOffset(in: again).map(String.init) ?? "lost")")
            }
            _ = point
        }
        return 0
    }

    /// The first point from the top of `pane` that has a block, and that block in continuous mode.
    private static func firstBlock(in pane: ParsedPane, of screen: ParsedScreen) -> (CGPoint, TerminalTextBlock)? {
        for row in pane.pane.rows {
            for column in stride(from: pane.pane.columns.lowerBound + 2, through: pane.pane.columns.upperBound, by: 4) {
                let rect = screen.geometry.rect(rows: row...row, columns: column...column)
                let point = CGPoint(x: rect.midX, y: rect.midY)
                if let block = screen.block(at: point, mode: .continuous), block.text.count > 40 {
                    return (point, block)
                }
            }
        }
        return nil
    }

    private static func read(_ pid: pid_t) -> (value: String, frame: CGRect)? {
        let app = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement
        var role: CFTypeRef?
        var value: CFTypeRef?
        var position: CFTypeRef?
        var size: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size)
        guard role as? String == kAXTextAreaRole, let text = value as? String, let position, let size else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return (text, CGRect(origin: origin, size: extent))
    }

    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
