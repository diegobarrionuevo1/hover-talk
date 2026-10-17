import CoreGraphics

/// A cell of a terminal grid.
public struct CellPosition: Equatable, Sendable {
    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}

/// Maps between a terminal's cells and screen points. `frame` is the text area's frame in AX
/// coordinates (top-left origin of the primary screen); it may lie on any screen, so its origin
/// is never assumed to be zero. Every cell gets an equal share of the frame.
public struct TerminalGeometry: Equatable, Sendable {
    public let frame: CGRect
    public let rows: Int
    public let columns: Int

    public init(frame: CGRect, rows: Int, columns: Int) {
        self.frame = frame
        self.rows = rows
        self.columns = columns
    }

    /// Zero when the grid has no rows or no columns.
    public var cellSize: CGSize {
        guard rows > 0, columns > 0 else { return .zero }
        return CGSize(width: frame.width / CGFloat(columns), height: frame.height / CGFloat(rows))
    }

    /// The cell under `point` (AX coordinates), or `nil` outside the frame. The frame's
    /// right and bottom edges are outside.
    public func cell(at point: CGPoint) -> CellPosition? {
        guard rows > 0, columns > 0, frame.contains(point) else { return nil }
        let size = cellSize
        let row = Int(((point.y - frame.minY) / size.height).rounded(.down))
        let column = Int(((point.x - frame.minX) / size.width).rounded(.down))
        // Defensive clamp: division may round a point just inside the far edge up to `rows` or `columns`.
        return CellPosition(row: min(row, rows - 1), column: min(column, columns - 1))
    }

    /// The rect covering a block of cells, in the same coordinates as `frame`.
    public func rect(rows: ClosedRange<Int>, columns: ClosedRange<Int>) -> CGRect {
        let size = cellSize
        return CGRect(
            x: frame.minX + CGFloat(columns.lowerBound) * size.width,
            y: frame.minY + CGFloat(rows.lowerBound) * size.height,
            width: CGFloat(columns.count) * size.width,
            height: CGFloat(rows.count) * size.height
        )
    }
}

/// Accessibility uses global coordinates with the origin at the primary screen's top-left
/// corner and y growing down; Cocoa (`NSEvent.mouseLocation`) puts it at the bottom-left with
/// y growing up.
public enum AXCoordinates {
    /// `primaryScreenHeight` must be the height of the primary screen (`NSScreen.screens.first`,
    /// whose frame origin is (0, 0)), whichever screen the point is on.
    public static func fromCocoa(_ point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }
}
