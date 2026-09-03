import Foundation

public enum MacKeyCodeShortcutError: Error, Equatable, Sendable {
    case functionKeyUnsupported
    case deviceFunctionKeyUnsupported(String)
    case unsupportedKey(UInt16)
    case tooManyKeys
}

extension MacKeyCodeShortcutError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .functionKeyUnsupported:
            "AU05 韌體無法離線輸出 Fn。請在 Typeless 改用另一組快捷鍵。"
        case let .deviceFunctionKeyUnsupported(name):
            "這台 AU05 無法輸出 \(name)。請選另一個按鍵。"
        case let .unsupportedKey(keyCode):
            "AU05 不支援這個按鍵（macOS keyCode \(keyCode)）。"
        case .tooManyKeys:
            "AU05 一組快捷鍵最多可包含 4 個按鍵。"
        }
    }
}

public enum MacKeyCodeShortcutMapper {
    private static let modifierUsages: [UInt16: UInt8] = [
        59: 0xE0, // Left Control
        56: 0xE1, // Left Shift
        58: 0xE2, // Left Option
        55: 0xE3, // Left Command
        62: 0xE4, // Right Control
        60: 0xE5, // Right Shift
        61: 0xE6, // Right Option
        54: 0xE7  // Right Command
    ]

    private static let ordinaryUsages: [UInt16: UInt8] = [
        0: 0x04, 1: 0x16, 2: 0x07, 3: 0x09, 4: 0x0B, 5: 0x0A,
        6: 0x1D, 7: 0x1B, 8: 0x06, 9: 0x19, 10: 0x64, 11: 0x05,
        12: 0x14, 13: 0x1A, 14: 0x08, 15: 0x15, 16: 0x1C, 17: 0x17,
        18: 0x1E, 19: 0x1F, 20: 0x20, 21: 0x21, 22: 0x23, 23: 0x22,
        24: 0x2E, 25: 0x26, 26: 0x24, 27: 0x2D, 28: 0x25, 29: 0x27,
        30: 0x30, 31: 0x12, 32: 0x18, 33: 0x2F, 34: 0x0C, 35: 0x13,
        36: 0x28, 37: 0x0F, 38: 0x0D, 39: 0x34, 40: 0x0E, 41: 0x33,
        42: 0x31, 43: 0x36, 44: 0x38, 45: 0x11, 46: 0x10, 47: 0x37,
        48: 0x2B, 49: 0x2C, 50: 0x35, 51: 0x2A, 53: 0x29, 57: 0x39,
        64: 0x6C, 65: 0x63, 67: 0x55, 69: 0x57, 71: 0x53, 75: 0x54,
        76: 0x58, 78: 0x56, 79: 0x6D, 80: 0x6E, 81: 0x67, 82: 0x62,
        83: 0x59, 84: 0x5A, 85: 0x5B, 86: 0x5C, 87: 0x5D, 88: 0x5E,
        89: 0x5F, 90: 0x6F, 91: 0x60, 92: 0x61, 96: 0x3E, 97: 0x3F,
        98: 0x40, 99: 0x3C, 100: 0x41, 101: 0x42, 103: 0x44, 105: 0x68,
        106: 0x6B, 107: 0x69, 109: 0x43, 111: 0x45, 113: 0x6A,
        114: 0x49, 115: 0x4A, 116: 0x4B, 117: 0x4C, 118: 0x3D,
        119: 0x4D, 120: 0x3B, 121: 0x4E, 122: 0x3A, 123: 0x50,
        124: 0x4F, 125: 0x51, 126: 0x52
    ]

    private static let macKeyCodesByOrdinaryUsage: [UInt8: UInt16] =
        Dictionary(uniqueKeysWithValues: ordinaryUsages.map { ($0.value, $0.key) })

    private static let macKeyCodesByModifierBit: [UInt8: UInt16] =
        Dictionary(uniqueKeysWithValues: modifierUsages.map { entry in
            let bit = UInt8(1 << (entry.value - 0xE0))
            return (bit, entry.key)
        })

    private static let keyNames: [UInt16: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
        54: "右 Command", 55: "左 Command", 56: "左 Shift", 57: "Caps Lock",
        58: "左 Option", 59: "左 Control", 60: "右 Shift", 61: "右 Option",
        62: "右 Control", 63: "Fn", 64: "F17", 71: "Clear", 75: "Keypad ÷",
        76: "Keypad Enter", 79: "F18", 80: "F19", 90: "F20", 96: "F5",
        97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12",
        113: "F15", 114: "Help", 115: "Home", 116: "Page Up",
        117: "Forward Delete", 118: "F4", 119: "End", 120: "F2",
        121: "Page Down", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    public static func isModifier(_ keyCode: UInt16) -> Bool {
        modifierUsages[keyCode] != nil || keyCode == 63
    }

    public static func macKeyCode(forUSBHIDUsage usage: UInt8) -> UInt16? {
        macKeyCodesByOrdinaryUsage[usage]
    }

    public static func macKeyCode(forModifierBit bit: UInt8) -> UInt16? {
        macKeyCodesByModifierBit[bit]
    }

    public static func shortcut(
        for keyCodes: [UInt16],
        fallbackName: String?
    ) throws -> NativeShortcut {
        guard keyCodes.count <= NativeShortcut.maximumEntryCount else {
            throw MacKeyCodeShortcutError.tooManyKeys
        }

        if let keyCode = keyCodes.first(where: { $0 == 80 || $0 == 90 }) {
            let name = keyCode == 80 ? "F19" : "F20"
            throw MacKeyCodeShortcutError.deviceFunctionKeyUnsupported(name)
        }

        var entries: [NativeShortcutEntry] = []

        for keyCode in keyCodes {
            if keyCode == 63 {
                throw MacKeyCodeShortcutError.functionKeyUnsupported
            }

            if let usage = modifierUsages[keyCode] {
                let bit = UInt8(1 << (usage - 0xE0))
                entries.append(NativeShortcutEntry(pageAndSign: 0x03, value: bit))
            } else if let usage = ordinaryUsages[keyCode] {
                entries.append(NativeShortcutEntry(pageAndSign: 0x02, value: usage))
            } else {
                throw MacKeyCodeShortcutError.unsupportedKey(keyCode)
            }
        }

        let names = keyCodes.enumerated().map { index, keyCode in
            if let name = keyNames[keyCode] {
                return name
            }
            if index == keyCodes.count - 1,
               let fallbackName,
               !fallbackName.isEmpty {
                return fallbackName
            }
            return "Key \(keyCode)"
        }

        return try NativeShortcut(
            entries: entries,
            displayName: names.joined(separator: " ＋ ")
        )
    }

    public static func displayName(for keyCodes: [UInt16]) -> String {
        keyCodes.map { keyNames[$0] ?? "Key \($0)" }.joined(separator: " ＋ ")
    }
}
