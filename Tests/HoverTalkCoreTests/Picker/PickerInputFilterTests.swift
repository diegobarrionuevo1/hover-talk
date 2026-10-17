import Testing
@testable import HoverTalkCore

@Suite("PickerInputFilter")
struct PickerInputFilterTests {
    private typealias Decision = PickerInputFilter.Decision

    @Test("A mouse down is consumed and does nothing yet; its mouse up is consumed and clicks")
    func clickOnMouseUp() {
        var filter = PickerInputFilter()

        #expect(filter.handle(.mouseDown) == Decision(consume: true, event: nil))
        #expect(filter.handle(.mouseUp) == Decision(consume: true, event: .click))
    }

    @Test("Drags between a consumed mouse down and its mouse up are consumed")
    func dragIsConsumed() {
        var filter = PickerInputFilter()
        _ = filter.handle(.mouseDown)

        #expect(filter.handle(.mouseDragged) == Decision(consume: true, event: nil))
        #expect(filter.handle(.mouseUp) == Decision(consume: true, event: .click))
    }

    @Test("A mouse up or drag whose mouse down came before capture passes through and does nothing")
    func unmatchedMouseEventsPass() {
        var filter = PickerInputFilter()

        #expect(filter.handle(.mouseDragged) == Decision(consume: false, event: nil))
        #expect(filter.handle(.mouseUp) == Decision(consume: false, event: nil))
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
        _ = filter.handle(.mouseDown)
        _ = filter.handle(.mouseUp)
        _ = filter.handle(.escapeDown)
        _ = filter.handle(.escapeUp)

        #expect(filter.handle(.mouseUp) == Decision(consume: false, event: nil))
        #expect(filter.handle(.escapeUp) == Decision(consume: false, event: nil))
    }
}
