import AppKit
import HoverTalkCore

/// A highlight over other apps: one transparent, borderless panel per screen, drawing rounded
/// rectangles. The picker outlines the block under the pointer with it; the reading highlighter
/// marks the text being read.
///
/// The panels never take focus from the app being read: a borderless window cannot become key
/// (`NSWindow.canBecomeKey`), `.nonactivatingPanel` keeps this app inactive, and
/// `ignoresMouseEvents` lets every mouse event through to the windows below.
@MainActor
final class HighlightOverlay {
    enum Style: Equatable {
        /// The picker's block: an accent outline over a light accent fill, padded on every side.
        case outline
        /// Text queued for reading: a faint accent fill without outline.
        case light
        /// The sentence being read: a thin accent outline over a stronger accent fill.
        case strong
    }

    struct Shape: Equatable {
        /// In AX coordinates.
        let rect: CGRect
        let style: Style
    }

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

    /// Outlines `rect` (AX coordinates) on every screen it touches; `nil` clears it.
    func highlight(_ rect: CGRect?) {
        draw(rect.map { [Shape(rect: $0, style: .outline)] } ?? [])
    }

    /// Draws `shapes` in order, replacing whatever was drawn; each on every screen it touches.
    func draw(_ shapes: [Shape]) {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        let cocoaShapes = shapes.map { shape in
            let padding = shape.style.padding
            let rect = ScreenCoordinates.cocoaRect(fromAX: shape.rect, primaryScreenHeight: primaryHeight)
                .insetBy(dx: -padding.width, dy: -padding.height)
            return Shape(rect: rect, style: shape.style)
        }
        for entry in panels {
            entry.view.shapes = cocoaShapes.compactMap { shape in
                guard shape.rect.intersects(entry.screenFrame) else { return nil }
                // The panel covers its screen exactly, so its content view's origin is the
                // screen frame's origin.
                return Shape(rect: shape.rect.offsetBy(dx: -entry.screenFrame.minX, dy: -entry.screenFrame.minY), style: shape.style)
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

private extension HighlightOverlay.Style {
    /// Space between the cells and the shape's edge. Reading shapes get no vertical padding,
    /// so the rects of adjacent rows meet without overlapping.
    var padding: CGSize {
        switch self {
        case .outline: CGSize(width: 4, height: 4)
        case .light, .strong: CGSize(width: 2, height: 0)
        }
    }

    var cornerRadius: CGFloat {
        self == .outline ? 6 : 3
    }

    /// Zero draws no outline.
    var lineWidth: CGFloat {
        switch self {
        case .outline: 2
        case .light: 0
        case .strong: 1.5
        }
    }

    var fillAlpha: CGFloat {
        switch self {
        case .outline: 0.12
        case .light: 0.10
        case .strong: 0.25
        }
    }
}

/// Draws the overlay's shapes in accent color.
private final class HighlightView: NSView {
    /// In this view's coordinates, drawn in order.
    var shapes: [HighlightOverlay.Shape] = [] {
        didSet {
            if shapes != oldValue { needsDisplay = true }
        }
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        for shape in shapes {
            let style = shape.style
            // Inset by half the line width so the outline stays inside the padded rect.
            let path = NSBezierPath(
                roundedRect: shape.rect.insetBy(dx: style.lineWidth / 2, dy: style.lineWidth / 2),
                xRadius: style.cornerRadius,
                yRadius: style.cornerRadius
            )
            NSColor.controlAccentColor.withAlphaComponent(style.fillAlpha).setFill()
            path.fill()
            if style.lineWidth > 0 {
                path.lineWidth = style.lineWidth
                NSColor.controlAccentColor.setStroke()
                path.stroke()
            }
        }
    }
}
