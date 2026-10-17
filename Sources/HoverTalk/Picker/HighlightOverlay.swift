import AppKit
import HoverTalkCore

/// The picker's highlight: one transparent, borderless panel per screen, drawing a rounded
/// rectangle around the block under the pointer.
///
/// The panels never take focus from the app being read: a borderless window cannot become key
/// (`NSWindow.canBecomeKey`), `.nonactivatingPanel` keeps this app inactive, and
/// `ignoresMouseEvents` lets every mouse event through to the windows below.
@MainActor
final class HighlightOverlay {
    /// Space between the block's cells and the highlight's edge.
    private static let padding: CGFloat = 4

    private struct ScreenPanel {
        let screenFrame: CGRect
        let panel: NSPanel
        let view: HighlightView
    }

    private var panels: [ScreenPanel] = []

    /// Shows an empty overlay on every screen, rebuilt each time so that screens added,
    /// removed or rearranged since the last time are covered.
    func show() {
        hide()
        panels = NSScreen.screens.map { Self.makePanel(covering: $0.frame) }
        for entry in panels {
            // orderFrontRegardless shows a window even while its app is inactive (NSWindow docs).
            entry.panel.orderFrontRegardless()
        }
    }

    func hide() {
        for entry in panels {
            entry.panel.orderOut(nil)
        }
        panels = []
    }

    /// Highlights `rect` (AX coordinates) on every screen it touches; `nil` clears it.
    func highlight(_ rect: CGRect?) {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        let cocoaRect = rect.map {
            ScreenCoordinates.cocoaRect(fromAX: $0, primaryScreenHeight: primaryHeight)
                .insetBy(dx: -Self.padding, dy: -Self.padding)
        }
        for entry in panels {
            entry.view.highlightRect = cocoaRect.flatMap { rect in
                guard rect.intersects(entry.screenFrame) else { return nil }
                // The panel covers its screen exactly, so its content view's origin is the
                // screen frame's origin.
                return rect.offsetBy(dx: -entry.screenFrame.minX, dy: -entry.screenFrame.minY)
            }
        }
    }

    private static func makePanel(covering screenFrame: CGRect) -> ScreenPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Above normal and floating windows (the controller panel is `.floating`).
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.setAccessibilityElement(false)

        let view = HighlightView()
        panel.contentView = view
        panel.setFrame(screenFrame, display: false)
        return ScreenPanel(screenFrame: screenFrame, panel: panel, view: view)
    }
}

/// Draws the highlight: an accent-colored rounded outline over a light fill of the same color.
private final class HighlightView: NSView {
    private static let cornerRadius: CGFloat = 6
    private static let lineWidth: CGFloat = 2

    /// In this view's coordinates; `nil` draws nothing.
    var highlightRect: CGRect? {
        didSet {
            if highlightRect != oldValue { needsDisplay = true }
        }
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let highlightRect else { return }
        // Inset by half the line width so the outline stays inside the padded rect.
        let path = NSBezierPath(
            roundedRect: highlightRect.insetBy(dx: Self.lineWidth / 2, dy: Self.lineWidth / 2),
            xRadius: Self.cornerRadius,
            yRadius: Self.cornerRadius
        )
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        path.fill()
        path.lineWidth = Self.lineWidth
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}
