import Foundation

/// Modifier keys of a global shortcut. The raw values are Carbon's modifier masks (`cmdKey`,
/// `shiftKey`, `optionKey`, `controlKey`), so the app passes them to `RegisterEventHotKey` unchanged.
public struct HotKeyModifiers: OptionSet, Equatable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let command = HotKeyModifiers(rawValue: 0x0100)
    public static let shift = HotKeyModifiers(rawValue: 0x0200)
    public static let option = HotKeyModifiers(rawValue: 0x0800)
    public static let control = HotKeyModifiers(rawValue: 0x1000)
    public static let all: HotKeyModifiers = [.command, .shift, .option, .control]
}

/// A global shortcut: one physical key, named by its macOS virtual key code, plus modifiers.
public struct HotKeyCombination: Equatable {
    public let keyCode: UInt32
    public let modifiers: HotKeyModifiers

    /// Command, Shift, Caps Lock, Option, Control and their right-hand twins, plus Fn.
    private static let modifierKeyCodes: ClosedRange<UInt32> = 0x36...0x3F

    /// Fails unless ⌘, ⌃ or ⌥ is held — a key with Shift alone, or with nothing, would take over
    /// ordinary typing in every app.
    public init?(keyCode: UInt32, modifiers: HotKeyModifiers) {
        guard keyCode <= 0x7F,
              !Self.modifierKeyCodes.contains(keyCode),
              HotKeyModifiers.all.isSuperset(of: modifiers),
              !modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Modifiers in the order macOS menus show them (⌃⌥⇧⌘), then the key.
    public func displayString(keyLabel: String) -> String {
        let symbols: [(HotKeyModifiers, String)] = [
            (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
        ]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + keyLabel
    }

    public var dictionaryRepresentation: [String: Int] {
        ["keyCode": Int(keyCode), "modifiers": Int(modifiers.rawValue)]
    }

    /// Reads the stored form back; anything that is not exactly a valid combination is nil.
    public init?(dictionaryRepresentation stored: [String: Any]) {
        guard let keyCode = Self.storedInteger(stored["keyCode"]),
              let modifiers = Self.storedInteger(stored["modifiers"]),
              let key = UInt32(exactly: keyCode),
              let mask = UInt32(exactly: modifiers) else { return nil }
        self.init(keyCode: key, modifiers: HotKeyModifiers(rawValue: mask))
    }

    private static func storedInteger(_ value: Any?) -> Int? {
        // A string such as "8" is not an integer here; NSNumber covers what UserDefaults hands back.
        guard let number = value as? NSNumber, !(value is String),
              Double(number.intValue) == number.doubleValue else { return nil }
        return number.intValue
    }
}
