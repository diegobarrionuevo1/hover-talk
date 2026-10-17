import CoreGraphics

/// Converts rects between AX global coordinates (origin at the primary screen's top-left
/// corner, y down) and Cocoa global coordinates (origin at its bottom-left corner, y up).
/// The inverse of `AXCoordinates.fromCocoa` for rects.
public enum ScreenCoordinates {
    /// `primaryScreenHeight` must be the primary screen's height (`NSScreen.screens.first`),
    /// whichever screen the rect is on; x is the same in both systems.
    public static func cocoaRect(fromAX rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
