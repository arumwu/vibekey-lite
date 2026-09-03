import Foundation

public struct NativeShortcutEntry: Codable, Equatable, Sendable {
    public let pageAndSign: UInt8
    public let value: UInt8

    public init(pageAndSign: UInt8, value: UInt8) {
        self.pageAndSign = pageAndSign
        self.value = value
    }
}

public enum NativeShortcutError: Error, Equatable {
    case tooManyEntries(maximum: Int, actual: Int)
    case invalidEntry(index: Int, pageAndSign: UInt8, value: UInt8)
}

extension NativeShortcutError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .tooManyEntries(maximum, actual):
            "裝置原生快捷鍵最多只能有 \(maximum) 個按鍵，目前是 \(actual) 個。"
        case let .invalidEntry(index, pageAndSign, value):
            String(
                format: "第 %d 個硬體按鍵資料不安全（page 0x%02X、value 0x%02X）。",
                index + 1,
                pageAndSign,
                value
            )
        }
    }
}

public struct NativeShortcut: Codable, Equatable, Sendable {
    public static let maximumEntryCount = 4

    public let entries: [NativeShortcutEntry]
    public let displayName: String

    public init(entries: [NativeShortcutEntry], displayName: String) throws {
        guard entries.count <= Self.maximumEntryCount else {
            throw NativeShortcutError.tooManyEntries(
                maximum: Self.maximumEntryCount,
                actual: entries.count
            )
        }

        for (index, entry) in entries.enumerated() {
            let isKeyboardKey = entry.pageAndSign == 0x02
                && (0x04...0x73).contains(entry.value)
            let isSingleModifier = entry.pageAndSign == 0x03
                && entry.value != 0
                && (entry.value & (entry.value &- 1)) == 0

            guard isKeyboardKey || isSingleModifier else {
                throw NativeShortcutError.invalidEntry(
                    index: index,
                    pageAndSign: entry.pageAndSign,
                    value: entry.value
                )
            }
        }

        self.entries = entries
        self.displayName = displayName
    }

    private enum CodingKeys: String, CodingKey {
        case entries
        case displayName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decode([NativeShortcutEntry].self, forKey: .entries)
        let displayName = try container.decode(String.self, forKey: .displayName)
        try self.init(entries: entries, displayName: displayName)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
        try container.encode(displayName, forKey: .displayName)
    }
}

public enum NativeHardwareAction: Equatable, Sendable {
    case none
    case shortcut(NativeShortcut)
    case fixedFunction(UInt8)
    case unsupported
}

public enum PresetNativeShortcutResolver {
    private static let keyboardPage: UInt8 = 0x02
    private static let modifierPage: UInt8 = 0x03

    private static let leftControl = NativeShortcutEntry(pageAndSign: modifierPage, value: 0x01)
    private static let leftShift = NativeShortcutEntry(pageAndSign: modifierPage, value: 0x02)
    private static let leftOption = NativeShortcutEntry(pageAndSign: modifierPage, value: 0x04)
    private static let leftCommand = NativeShortcutEntry(pageAndSign: modifierPage, value: 0x08)
    private static let rightOption = NativeShortcutEntry(pageAndSign: modifierPage, value: 0x40)

    public static func resolve(_ action: KeyAction) -> NativeHardwareAction {
        switch action {
        case .none:
            .none
        case .space:
            shortcut(action, key(0x2C))
        case .returnKey:
            shortcut(action, key(0x28))
        case .escape:
            shortcut(action, key(0x29))
        case .tab:
            shortcut(action, key(0x2B))
        case .optionKey:
            shortcut(action, leftOption)
        case .rightOptionKey:
            shortcut(action, rightOption)
        case .leftArrow:
            shortcut(action, key(0x50))
        case .rightArrow:
            shortcut(action, key(0x4F))
        case .upArrow:
            shortcut(action, key(0x52))
        case .downArrow:
            shortcut(action, key(0x51))
        case .deleteBackward:
            shortcut(action, key(0x2A))
        case .deleteForward:
            shortcut(action, key(0x4C))
        case .home:
            shortcut(action, key(0x4A))
        case .end:
            shortcut(action, key(0x4D))
        case .pageUp:
            shortcut(action, key(0x4B))
        case .pageDown:
            shortcut(action, key(0x4E))
        case .f1:
            shortcut(action, key(0x3A))
        case .f2:
            shortcut(action, key(0x3B))
        case .f3:
            shortcut(action, key(0x3C))
        case .f4:
            shortcut(action, key(0x3D))
        case .f5:
            shortcut(action, key(0x3E))
        case .f6:
            shortcut(action, key(0x3F))
        case .f7:
            shortcut(action, key(0x40))
        case .f8:
            shortcut(action, key(0x41))
        case .f9:
            shortcut(action, key(0x42))
        case .f10:
            shortcut(action, key(0x43))
        case .f11:
            shortcut(action, key(0x44))
        case .f12:
            shortcut(action, key(0x45))
        case .selectAll:
            shortcut(action, leftCommand, key(0x04))
        case .copy:
            shortcut(action, leftCommand, key(0x06))
        case .paste:
            shortcut(action, leftCommand, key(0x19))
        case .cut:
            shortcut(action, leftCommand, key(0x1B))
        case .undo:
            shortcut(action, leftCommand, key(0x1D))
        case .redo:
            shortcut(action, leftCommand, leftShift, key(0x1D))
        case .save:
            shortcut(action, leftCommand, key(0x16))
        case .appSwitcher:
            shortcut(action, leftCommand, key(0x2B))
        case .spotlight:
            shortcut(action, leftCommand, key(0x2C))
        case .screenshot:
            shortcut(action, leftCommand, leftShift, key(0x22))
        case .missionControl:
            shortcut(action, leftControl, key(0x52))
        case .switchProfile, .brightnessUp, .brightnessDown:
            .unsupported
        case .playPause:
            .fixedFunction(0x07)
        case .nextTrack:
            .fixedFunction(0x08)
        case .previousTrack:
            .fixedFunction(0x09)
        case .mute:
            .fixedFunction(0x0B)
        case .volumeUp:
            .fixedFunction(0x0C)
        case .volumeDown:
            .fixedFunction(0x0D)
        }
    }

    private static func key(_ usbHIDUsage: UInt8) -> NativeShortcutEntry {
        NativeShortcutEntry(pageAndSign: keyboardPage, value: usbHIDUsage)
    }

    private static func shortcut(
        _ action: KeyAction,
        _ entries: NativeShortcutEntry...
    ) -> NativeHardwareAction {
        // Every built-in preset above is statically limited to at most three entries.
        let nativeShortcut = try! NativeShortcut(
            entries: entries,
            displayName: action.displayName
        )
        return .shortcut(nativeShortcut)
    }
}
