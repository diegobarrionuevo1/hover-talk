import Testing
@testable import HoverTalkCore

@Suite("Hotkey")
struct HotkeyTests {
    @Test("The picker's default hotkey is Control-Option-R (Carbon key code 0x0F, kVK_ANSI_R)")
    func defaultPickerHotkey() {
        #expect(Hotkey.pickText.keyCode == 0x0F)
        #expect(Hotkey.pickText.modifiers == [.control, .option])
        #expect(Hotkey.pickText.displayString == "⌃⌥R")
    }

    @Test("Modifier symbols follow the macOS menu order ⌃⌥⇧⌘, whatever order they were given in")
    func modifierOrder() {
        let hotkey = Hotkey(keyCode: 0x00, modifiers: [.command, .shift, .option, .control], keyName: "A")

        #expect(hotkey.displayString == "⌃⌥⇧⌘A")
        #expect(Hotkey(keyCode: 0x00, modifiers: [.command], keyName: "A").displayString == "⌘A")
        #expect(Hotkey(keyCode: 0x00, modifiers: [], keyName: "A").displayString == "A")
    }

    @Test("Read selection is Control-Option-S and read all is Control-Option-A, and no two shortcuts clash")
    func otherHotkeys() {
        #expect(Hotkey.readSelection.keyCode == 0x01)
        #expect(Hotkey.readSelection.displayString == "⌃⌥S")
        #expect(Hotkey.readAll.keyCode == 0x00)
        #expect(Hotkey.readAll.displayString == "⌃⌥A")
        let all = [Hotkey.pickText, .readSelection, .readAll]
        #expect(Set(all.map(\.keyCode)).count == all.count)
    }
}
