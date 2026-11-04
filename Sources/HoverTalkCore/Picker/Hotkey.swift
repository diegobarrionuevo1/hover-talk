/// A global keyboard shortcut: a key and its modifier keys.
public struct Hotkey: Equatable, Sendable {
    public struct Modifiers: OptionSet, Equatable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// A Carbon virtual key code (`kVK_*` in HIToolbox `Events.h`).
    public let keyCode: UInt32
    public let modifiers: Modifiers
    /// The key's label in `displayString`, such as `R`.
    public let keyName: String

    public init(keyCode: UInt32, modifiers: Modifiers, keyName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyName = keyName
    }

    /// The modifier symbols in the order macOS menus use (⌃⌥⇧⌘), then the key, such as `⌃⌥R`.
    public var displayString: String {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + keyName
    }

    /// Starts the picker: Control-Option-R. 0x0F is `kVK_ANSI_R` in HIToolbox `Events.h`.
    public static let pickText = Hotkey(keyCode: 0x0F, modifiers: [.control, .option], keyName: "R")

    /// Reads the text selected in the frontmost app: Control-Option-S. 0x01 is `kVK_ANSI_S`.
    public static let readSelection = Hotkey(keyCode: 0x01, modifiers: [.control, .option], keyName: "S")

    /// Reads the whole window or page: Control-Option-A. 0x00 is `kVK_ANSI_A`.
    public static let readAll = Hotkey(keyCode: 0x00, modifiers: [.control, .option], keyName: "A")
}
