import Foundation
import CoreGraphics

/// A recorded hotkey: a lone modifier (left/right aware), a regular key, or key + modifiers.
struct HotkeySpec: Codable, Equatable {
    var keyCode: Int
    /// Generic modifier flags (CGEventFlags: shift/control/option/command) required for a key combo.
    var mods: UInt64 = 0
    var modifierOnly: Bool

    static let `default` = HotkeySpec(keyCode: 61, mods: 0, modifierOnly: true)

    static let maskShift = CGEventFlags.maskShift.rawValue
    static let maskControl = CGEventFlags.maskControl.rawValue
    static let maskAlt = CGEventFlags.maskAlternate.rawValue
    static let maskCommand = CGEventFlags.maskCommand.rawValue
    static let maskFn = CGEventFlags.maskSecondaryFn.rawValue
    static let comboMask = maskShift | maskControl | maskAlt | maskCommand

    /// keyCode -> (device-dependent flag, glyph, name) of modifier keys.
    static let modifierKeys: [Int: (device: UInt64, glyph: String, name: String)] = [
        54: (0x10, "⌘", "Right Command"), 55: (0x08, "⌘", "Left Command"),
        56: (0x02, "⇧", "Left Shift"), 60: (0x04, "⇧", "Right Shift"),
        58: (0x20, "⌥", "Left Option"), 61: (0x40, "⌥", "Right Option"),
        59: (0x01, "⌃", "Left Control"), 62: (0x2000, "⌃", "Right Control"),
        63: (0x800000, "fn", "Fn"),
    ]
    static let capsLock = 57

    static let keyNames: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
        14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
        39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc", 57: "Caps Lock", 71: "Clear", 76: "Enter",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13", 106: "F16", 107: "F14",
        109: "F10", 111: "F12", 113: "F15", 114: "Help", 115: "Home", 116: "Page Up", 117: "Fwd Delete", 118: "F4",
        119: "End", 120: "F2", 121: "Page Down", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
        64: "F17", 79: "F18", 80: "F19", 90: "F20",
        82: "Num 0", 83: "Num 1", 84: "Num 2", 85: "Num 3", 86: "Num 4", 87: "Num 5", 88: "Num 6", 89: "Num 7",
        91: "Num 8", 92: "Num 9", 65: "Num .", 67: "Num *", 69: "Num +", 75: "Num /", 78: "Num -", 81: "Num =",
    ]

    var isCapsLock: Bool { !modifierOnly && keyCode == HotkeySpec.capsLock }

    var displayName: String {
        if modifierOnly { return HotkeySpec.modifierKeys[keyCode]?.name ?? "Key \(keyCode)" }
        var s = ""
        if mods & HotkeySpec.maskControl != 0 { s += "⌃" }
        if mods & HotkeySpec.maskAlt != 0 { s += "⌥" }
        if mods & HotkeySpec.maskShift != 0 { s += "⇧" }
        if mods & HotkeySpec.maskCommand != 0 { s += "⌘" }
        return s + (HotkeySpec.keyNames[keyCode] ?? "Key \(keyCode)")
    }
}
