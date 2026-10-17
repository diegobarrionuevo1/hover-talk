import CoreGraphics
import Testing
@testable import HoverTalkCore

@Suite("ScreenCoordinates")
struct ScreenCoordinatesTests {
    /// The primary screen's height in the captures of 2026-10-16 (1470 × 956 points).
    private let primaryHeight: CGFloat = 956

    @Test("An AX rect (top-left origin) on the primary screen converts to Cocoa (bottom-left origin)")
    func primaryScreen() {
        let ax = CGRect(x: 100, y: 56, width: 200, height: 40)

        #expect(ScreenCoordinates.cocoaRect(fromAX: ax, primaryScreenHeight: primaryHeight)
            == CGRect(x: 100, y: 860, width: 200, height: 40))
    }

    @Test("A rect on a secondary screen at x = 1470 keeps its x and converts y with the primary screen's height")
    func secondaryScreenToTheRight() {
        let ax = CGRect(x: 1520, y: 102, width: 50, height: 40)

        #expect(ScreenCoordinates.cocoaRect(fromAX: ax, primaryScreenHeight: primaryHeight)
            == CGRect(x: 1520, y: 814, width: 50, height: 40))
    }

    @Test("A rect below the primary screen gets a negative Cocoa y")
    func screenBelowPrimary() {
        let ax = CGRect(x: 1600, y: 996, width: 100, height: 40)

        #expect(ScreenCoordinates.cocoaRect(fromAX: ax, primaryScreenHeight: primaryHeight)
            == CGRect(x: 1600, y: -80, width: 100, height: 40))
    }

    @Test("The inverse of AXCoordinates.fromCocoa: the Cocoa rect's top-left converts back to the AX origin")
    func inverseOfFromCocoa() {
        let ax = CGRect(x: 1470, y: 62, width: 1920, height: 928)
        let cocoa = ScreenCoordinates.cocoaRect(fromAX: ax, primaryScreenHeight: primaryHeight)

        #expect(AXCoordinates.fromCocoa(CGPoint(x: cocoa.minX, y: cocoa.maxY), primaryScreenHeight: primaryHeight) == ax.origin)
    }
}
