import CoreGraphics

/// Where the floating controller appears on a screen.
public enum ControllerPlacement {
    /// Gap between the panel and the bottom of the screen's visible frame.
    public static let bottomMargin: CGFloat = 24

    /// Bottom-left origin, in the coordinates of `visibleFrame`, that centers a panel of
    /// `size` horizontally and puts it `bottomMargin` above the frame's bottom edge.
    /// `visibleFrame` is expected to be `NSScreen.visibleFrame`, which already excludes the
    /// Dock and the menu bar. Both coordinates are rounded down to whole points.
    public static func origin(for size: CGSize, in visibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: (visibleFrame.midX - size.width / 2).rounded(.down),
            y: (visibleFrame.minY + bottomMargin).rounded(.down)
        )
    }
}
