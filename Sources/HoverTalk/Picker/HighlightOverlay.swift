import AppKit
import HoverTalkCore

/// A highlight over other apps: one transparent, borderless panel per screen, drawing rounded
/// rectangles. The picker outlines the block under the pointer, or a drag's selection, with it;
/// the reading highlighter marks the text being read.
///
/// The panels never take focus from the app being read: a borderless window cannot become key
/// (`NSWindow.canBecomeKey`), `.nonactivatingPanel` keeps this app inactive, and
/// `ignoresMouseEvents` lets every mouse event through to the windows below.
@MainActor
final class HighlightOverlay {
    enum Style: Equatable {
        /// The picker's block or selection: an accent outline over a light accent fill, padded
        /// on every side. Outline shapes are drawn merged into one, so the row rects of a
        /// selection, which overlap through their padding, get one outline around them all.
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

    /// Outlines `rects` (AX coordinates) on every screen they touch; `[]` clears the outline.
    func highlight(_ rects: [CGRect]) {
        draw(rects.map { Shape(rect: $0, style: .outline) })
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

    /// Every outline shape as one merged path first, then the other shapes in order. The two
    /// kinds never share an overlay: the picker and the reading highlighter each own one.
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let outlines = shapes.filter { $0.style == .outline }.map(Self.path(for:))
        if let first = outlines.first {
            Self.draw(outlines.dropFirst().reduce(first) { $0.union($1) }, style: .outline, in: context)
        }
        for shape in shapes where shape.style != .outline {
            Self.draw(Self.path(for: shape), style: shape.style, in: context)
        }
    }

    /// The shape's rounded rect, inset by half the line width so an outline stays inside the
    /// padded rect; the corner radius shrinks to fit a rect too small for it.
    private static func path(for shape: HighlightOverlay.Shape) -> CGPath {
        let style = shape.style
        let rect = shape.rect.insetBy(dx: style.lineWidth / 2, dy: style.lineWidth / 2)
        let radius = max(0, min(style.cornerRadius, rect.width / 2, rect.height / 2))
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private static func draw(_ path: CGPath, style: HighlightOverlay.Style, in context: CGContext) {
        context.addPath(path)
        context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(style.fillAlpha).cgColor)
        context.fillPath()
        guard style.lineWidth > 0 else { return }
        context.addPath(path)
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(style.lineWidth)
        context.strokePath()
    }
}
