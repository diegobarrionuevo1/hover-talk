import CoreGraphics
import Testing
@testable import HoverTalkCore

@Suite("PickerInputFilter")
struct PickerInputFilterTests {
    private typealias Decision = PickerInputFilter.Decision

    private let origin = CGPoint(x: 100, y: 200)

    private func offset(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + dx, y: origin.y + dy)
    }

    @Test("A mouse down is consumed and does nothing yet; its mouse up is consumed and clicks")
    func clickOnMouseUp() {
        var filter = PickerInputFilter()

        #expect(filter.handle(.mouseDown(origin)) == Decision(consume: true, event: nil))
        #expect(filter.handle(.mouseUp(origin)) == Decision(consume: true, event: .click))
    }

    @Test("Drags between a consumed mouse down and its mouse up are consumed")
    func dragIsConsumed() {
        var filter = PickerInputFilter()
        _ = filter.handle(.mouseDown(origin))

        #expect(filter.handle(.mouseDragged(offset(1, 0))) == Decision(consume: true, event: nil))
        #expect(filter.handle(.mouseUp(offset(1, 0))) == Decision(consume: true, event: .click))
    }

    @Test("A mouse up or drag whose mouse down came before capture passes through and does nothing")
    func unmatchedMouseEventsPass() {
        var filter = PickerInputFilter()

        #expect(filter.handle(.mouseDragged(offset(20, 0))) == Decision(consume: false, event: nil))
        #expect(filter.handle(.mouseUp(offset(20, 0))) == Decision(consume: false, event: nil))
    }

    @Test("Every Esc key down is consumed, key repeats included; the key up is consumed and cancels")
    func escapeOnKeyUp() {
        var filter = PickerInputFilter()

        #expect(filter.handle(.escapeDown) == Decision(consume: true, event: nil))
        #expect(filter.handle(.escapeDown) == Decision(consume: true, event: nil))
        #expect(filter.handle(.escapeUp) == Decision(consume: true, event: .escape))
    }

    @Test("An Esc key up whose key down came before capture passes through and does nothing")
    func unmatchedEscapeUpPasses() {
        var filter = PickerInputFilter()

        #expect(filter.handle(.escapeUp) == Decision(consume: false, event: nil))
    }

    @Test("Each mouse up and key up is matched once")
    func upsMatchOnce() {
        var filter = PickerInputFilter()
        _ = filter.handle(.mouseDown(origin))
        _ = filter.handle(.mouseUp(origin))
        _ = filter.handle(.escapeDown)
        _ = filter.handle(.escapeUp)

        #expect(filter.handle(.mouseUp(origin)) == Decision(consume: false, event: nil))
        #expect(filter.handle(.escapeUp) == Decision(consume: false, event: nil))
    }

    // MARK: Click or drag

    @Test("A press that moves 4 points or less before its release stays a click", arguments: [
        (4.0, 0.0), (0.0, -4.0), (3.0, 2.5), (-2.0, 2.0),
    ])
    func smallMoveIsClick(dx: Double, dy: Double) {
        var filter = PickerInputFilter()
        _ = filter.handle(.mouseDown(origin))

        #expect(filter.handle(.mouseDragged(offset(dx, dy))) == Decision(consume: true, event: nil))
        #expect(filter.handle(.mouseUp(offset(dx, dy))) == Decision(consume: true, event: .click))
    }

    @Test("A press that moves more than 4 points is a drag: each move reports it, and the release ends it instead of clicking", arguments: [
        (4.5, 0.0), (0.0, -4.5), (3.0, 3.0),
    ])
    func largeMoveIsDrag(dx: Double, dy: Double) {
        var filter = PickerInputFilter()
        _ = filter.handle(.mouseDown(origin))
        let moved = offset(dx, dy)

        #expect(filter.handle(.mouseDragged(moved)) == Decision(consume: true, event: nil, drag: .moved(from: origin, to: moved)))
        #expect(filter.handle(.mouseUp(moved)) == Decision(consume: true, event: nil, drag: .released(from: origin, to: moved)))
    }

    @Test("Once a drag, always a drag: moving back near the start keeps reporting the drag")
    func dragStaysDrag() {
        var filter = PickerInputFilter()
        _ = filter.handle(.mouseDown(origin))
        _ = filter.handle(.mouseDragged(offset(30, 10)))

        #expect(filter.handle(.mouseDragged(offset(1, 0))) == Decision(consume: true, event: nil, drag: .moved(from: origin, to: offset(1, 0))))
        #expect(filter.handle(.mouseUp(origin)) == Decision(consume: true, event: nil, drag: .released(from: origin, to: origin)))
    }

    @Test("A release more than 4 points from its press is a drag even without any drag event in between")
    func releaseFarAwayIsDrag() {
        var filter = PickerInputFilter()
        _ = filter.handle(.mouseDown(origin))

        #expect(filter.handle(.mouseUp(offset(0, 12))) == Decision(consume: true, event: nil, drag: .released(from: origin, to: offset(0, 12))))
    }

    @Test("After a drag, the next press starts over and can click")
    func nextPressStartsOver() {
        var filter = PickerInputFilter()
        _ = filter.handle(.mouseDown(origin))
        _ = filter.handle(.mouseDragged(offset(50, 0)))
        _ = filter.handle(.mouseUp(offset(50, 0)))

        let elsewhere = offset(200, 40)
        _ = filter.handle(.mouseDown(elsewhere))
        #expect(filter.handle(.mouseDragged(CGPoint(x: elsewhere.x + 2, y: elsewhere.y))) == Decision(consume: true, event: nil))
        #expect(filter.handle(.mouseUp(elsewhere)) == Decision(consume: true, event: .click))
    }
}
