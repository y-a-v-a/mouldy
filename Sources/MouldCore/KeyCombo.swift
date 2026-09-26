/// A global keyboard shortcut, described independently of Carbon so it can be tested and displayed.
public struct KeyCombo: Sendable, Equatable {
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        // Values match Carbon's cmdKey / shiftKey / optionKey / controlKey.
        public static let command = Modifiers(rawValue: 1 << 8)
        public static let shift = Modifiers(rawValue: 1 << 9)
        public static let option = Modifiers(rawValue: 1 << 11)
        public static let control = Modifiers(rawValue: 1 << 12)
    }

    public var keyCode: UInt32
    public var key: String
    public var modifiers: Modifiers

    public init(keyCode: UInt32, key: String, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.key = key
        self.modifiers = modifiers
    }

    /// ⌃⌥⌘M — "M" for mould. Unlikely to collide with anything.
    public static let clearMould = KeyCombo(keyCode: 0x2E /* kVK_ANSI_M */, key: "M", modifiers: [.control, .option, .command])

    /// Human readable, in Apple's canonical modifier order (⌃⌥⇧⌘).
    public var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + key.uppercased()
    }
}
