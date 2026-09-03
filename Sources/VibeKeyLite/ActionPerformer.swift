import AppKit
import CoreGraphics
import VibeKeyLiteCore

enum ActionPerformerError: LocalizedError {
    case unsupportedAction(String)
    case unsupportedShortcutEntry(NativeShortcutEntry)
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case let .unsupportedAction(name):
            "無法送出「\(name)」。"
        case let .unsupportedShortcutEntry(entry):
            String(
                format: "無法送出快捷鍵資料（page 0x%02X、value 0x%02X）。",
                entry.pageAndSign,
                entry.value
            )
        case .eventCreationFailed:
            "macOS 無法建立鍵盤事件。"
        }
    }
}

final class ActionPerformer {
    private struct Stroke {
        let keyCode: UInt16
        let modifierFlag: CGEventFlags?
    }

    private var pressed: [InputControl: [Stroke]] = [:]

    func validate(profile: ProfileConfiguration) throws {
        for control in InputControl.allCases {
            _ = try resolve(profile[control])
        }
    }

    func press(_ binding: ControlBinding, for control: InputControl) throws {
        guard pressed[control] == nil else { return }

        switch try resolve(binding) {
        case .none, .switchProfile:
            return
        case let .media(keyType):
            postMediaKey(keyType)
        case let .shortcut(strokes):
            var flags = CGEventSource.flagsState(.combinedSessionState)
            for stroke in strokes {
                if let modifierFlag = stroke.modifierFlag {
                    flags.insert(modifierFlag)
                }
                try postKey(stroke.keyCode, isDown: true, flags: flags)
            }
            pressed[control] = strokes
        }
    }

    func release(for control: InputControl) {
        guard let strokes = pressed.removeValue(forKey: control) else { return }
        var flags = CGEventSource.flagsState(.combinedSessionState)

        for stroke in strokes.reversed() {
            if let modifierFlag = stroke.modifierFlag {
                flags.remove(modifierFlag)
            }
            try? postKey(stroke.keyCode, isDown: false, flags: flags)
        }
    }

    func tap(_ binding: ControlBinding, for control: InputControl) throws {
        try press(binding, for: control)
        release(for: control)
    }

    func releaseAll() {
        for control in Array(pressed.keys) {
            release(for: control)
        }
    }

    private enum ResolvedBinding {
        case none
        case shortcut([Stroke])
        case media(Int32)
        case switchProfile
    }

    private func resolve(_ binding: ControlBinding) throws -> ResolvedBinding {
        let nativeAction: NativeHardwareAction
        switch binding {
        case let .preset(action):
            if action == .switchProfile { return .switchProfile }
            nativeAction = PresetNativeShortcutResolver.resolve(action)
        case let .shortcut(shortcut):
            nativeAction = .shortcut(shortcut)
        }

        switch nativeAction {
        case .none:
            return .none
        case let .shortcut(shortcut):
            return .shortcut(try shortcut.entries.map(resolve))
        case let .fixedFunction(code):
            guard let keyType = mediaKeyType(for: code) else {
                throw ActionPerformerError.unsupportedAction(binding.displayName)
            }
            return .media(keyType)
        case .unsupported:
            throw ActionPerformerError.unsupportedAction(binding.displayName)
        }
    }

    private func resolve(_ entry: NativeShortcutEntry) throws -> Stroke {
        switch entry.pageAndSign {
        case 0x02:
            guard let keyCode = MacKeyCodeShortcutMapper.macKeyCode(
                forUSBHIDUsage: entry.value
            ) else {
                throw ActionPerformerError.unsupportedShortcutEntry(entry)
            }
            return Stroke(keyCode: keyCode, modifierFlag: nil)
        case 0x03:
            guard let keyCode = MacKeyCodeShortcutMapper.macKeyCode(
                forModifierBit: entry.value
            ), let flag = modifierFlag(for: entry.value) else {
                throw ActionPerformerError.unsupportedShortcutEntry(entry)
            }
            return Stroke(keyCode: keyCode, modifierFlag: flag)
        default:
            throw ActionPerformerError.unsupportedShortcutEntry(entry)
        }
    }

    private func modifierFlag(for bit: UInt8) -> CGEventFlags? {
        switch bit {
        case 0x01, 0x10: .maskControl
        case 0x02, 0x20: .maskShift
        case 0x04, 0x40: .maskAlternate
        case 0x08, 0x80: .maskCommand
        default: nil
        }
    }

    private func postKey(
        _ keyCode: UInt16,
        isDown: Bool,
        flags: CGEventFlags
    ) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(keyCode),
            keyDown: isDown
        ) else {
            throw ActionPerformerError.eventCreationFailed
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func mediaKeyType(for functionCode: UInt8) -> Int32? {
        switch functionCode {
        case 0x07: 16 // play / pause
        case 0x08: 17 // next
        case 0x09: 18 // previous
        case 0x0B: 7  // mute
        case 0x0C: 0  // volume up
        case 0x0D: 1  // volume down
        default: nil
        }
    }

    private func postMediaKey(_ keyType: Int32) {
        postSystemDefinedMediaEvent(keyType: keyType, keyState: 0xA)
        postSystemDefinedMediaEvent(keyType: keyType, keyState: 0xB)
    }

    private func postSystemDefinedMediaEvent(keyType: Int32, keyState: Int32) {
        let data1 = Int((keyType << 16) | (keyState << 8))
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }
}
