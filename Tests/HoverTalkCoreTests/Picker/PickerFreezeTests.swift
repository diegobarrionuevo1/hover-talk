import CoreGraphics
import Testing
@testable import HoverTalkCore

@Suite("Picker freeze for system shortcuts")
struct PickerFreezeTests {
    let block = HoverTarget(rect: CGRect(x: 0, y: 0, width: 10, height: 10), text: "Hello.")

    private func pickingOverBlock() -> PickerState {
        var state = PickerState()
        _ = state.handle(.hotkey)
        _ = state.handle(.hoverChanged(block))
        return state
    }

    @Test("A system shortcut stops capture but keeps the outline on screen")
    func freezeKeepsOutline() {
        var state = pickingOverBlock()
        #expect(state.handle(.systemShortcut) == [.stopCapture])
        #expect(state.phase == .frozen)
    }

    @Test("While frozen, clicks, hovers and selections do nothing")
    func frozenIgnoresInput() {
        var state = pickingOverBlock()
        _ = state.handle(.systemShortcut)
        #expect(state.handle(.click) == [])
        #expect(state.handle(.hoverChanged(nil)) == [])
        #expect(state.handle(.selectionEnded(block)) == [])
        #expect(state.phase == .frozen)
    }

    @Test("The hotkey or a cancel hides the frozen outline without stopping capture again")
    func unfreeze() {
        var state = pickingOverBlock()
        _ = state.handle(.systemShortcut)
        #expect(state.handle(.hotkey) == [.hideOverlay])
        #expect(state.phase == .idle)
        state = pickingOverBlock()
        _ = state.handle(.systemShortcut)
        #expect(state.handle(.cancel) == [.hideOverlay])
    }

    @Test("A system shortcut while idle does nothing")
    func idleShortcut() {
        var state = PickerState()
        #expect(state.handle(.systemShortcut) == [])
        #expect(state.phase == .idle)
    }
}

@Suite("System shortcut detection")
struct SystemShortcutTests {
    @Test("Command-Shift chords such as the screenshot shortcuts pass through")
    func screenshotChords() {
        #expect(PickerInputFilter.isSystemShortcut(command: true, shift: true))
        #expect(!PickerInputFilter.isSystemShortcut(command: true, shift: false))
        #expect(!PickerInputFilter.isSystemShortcut(command: false, shift: true))
    }
}
