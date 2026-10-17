import CoreGraphics
import Testing
@testable import HoverTalkCore

@Suite("TerminalGeometry")
struct TerminalGeometryTests {
    /// A frame on a secondary screen to the right of the primary one, as in the vsplit capture.
    let geometry = TerminalGeometry(frame: CGRect(x: 1470, y: 62, width: 800, height: 400), rows: 20, columns: 80)

    @Test("The cell size divides the frame evenly by rows and columns")
    func cellSize() {
        #expect(geometry.cellSize == CGSize(width: 10, height: 20))
    }

    @Test("A point inside the frame maps to its row and column, relative to the frame origin")
    func cellInsideFrame() {
        #expect(geometry.cell(at: CGPoint(x: 1470, y: 62)) == CellPosition(row: 0, column: 0))
        #expect(geometry.cell(at: CGPoint(x: 1495, y: 107)) == CellPosition(row: 2, column: 2))
        #expect(geometry.cell(at: CGPoint(x: 2269.9, y: 461.9)) == CellPosition(row: 19, column: 79))
    }

    @Test("A point outside the frame, or on its far edges, has no cell")
    func cellOutsideFrame() {
        #expect(geometry.cell(at: CGPoint(x: 1469.9, y: 100)) == nil)
        #expect(geometry.cell(at: CGPoint(x: 1500, y: 61.9)) == nil)
        #expect(geometry.cell(at: CGPoint(x: 2270, y: 100)) == nil)
        #expect(geometry.cell(at: CGPoint(x: 1500, y: 462)) == nil)
    }

    @Test("A grid with no rows or no columns has no cells")
    func emptyGrid() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        #expect(TerminalGeometry(frame: frame, rows: 0, columns: 10).cell(at: CGPoint(x: 5, y: 5)) == nil)
        #expect(TerminalGeometry(frame: frame, rows: 10, columns: 0).cell(at: CGPoint(x: 5, y: 5)) == nil)
    }

    @Test("A cell range maps back to a rect in the frame's coordinates")
    func rectForCells() {
        #expect(geometry.rect(rows: 2...3, columns: 5...9) == CGRect(x: 1520, y: 102, width: 50, height: 40))
        #expect(geometry.rect(rows: 0...19, columns: 0...79) == geometry.frame)
    }

    @Test("A Cocoa point (bottom-left origin) converts to AX (top-left origin) with the primary screen height")
    func cocoaToAX() {
        #expect(AXCoordinates.fromCocoa(CGPoint(x: 100, y: 900), primaryScreenHeight: 956) == CGPoint(x: 100, y: 56))
        #expect(AXCoordinates.fromCocoa(CGPoint(x: 1600, y: -40), primaryScreenHeight: 956) == CGPoint(x: 1600, y: 996))
    }
}
