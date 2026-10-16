import CoreGraphics
import Testing
@testable import HoverTalkCore

@Suite("ControllerPlacement")
struct ControllerPlacementTests {
    @Test("The panel is centered horizontally and sits the margin above the visible frame's bottom")
    func bottomCenter() {
        let visibleFrame = CGRect(x: 0, y: 80, width: 1470, height: 776)
        let origin = ControllerPlacement.origin(for: CGSize(width: 400, height: 44), in: visibleFrame)

        #expect(ControllerPlacement.bottomMargin == 24)
        #expect(origin == CGPoint(x: 535, y: 104))
    }

    @Test("A screen to the left of the main screen has a negative origin, which is kept")
    func secondaryScreen() {
        let visibleFrame = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        let origin = ControllerPlacement.origin(for: CGSize(width: 400, height: 44), in: visibleFrame)

        #expect(origin == CGPoint(x: -1160, y: 24))
    }

    @Test("The origin is rounded down to whole points")
    func wholePoints() {
        let visibleFrame = CGRect(x: 0, y: 0.5, width: 1001, height: 800)
        let origin = ControllerPlacement.origin(for: CGSize(width: 400, height: 44), in: visibleFrame)

        #expect(origin == CGPoint(x: 300, y: 24))
    }
}
