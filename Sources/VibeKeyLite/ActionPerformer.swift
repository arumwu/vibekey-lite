import AppKit
import CoreGraphics
import VibeKeyLiteCore

final class ActionPerformer {
    func perform(_ action: ResolvedAction) {
        switch action {
        case .none, .switchProfile:
            return
        case let .keyStroke(keyCode, modifiers):
            postKeyStroke(keyCode: keyCode, modifiers: modifiers)
        case let .media(mediaAction):
            postMediaKey(mediaAction)
        }
    }

    private func postKeyStroke(keyCode: UInt16, modifiers: KeyModifiers) {
        let source = CGEventSource(stateID: .hidSystemState)
        let flags = cgEventFlags(for: modifiers)

        guard let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(keyCode),
            keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(keyCode),
            keyDown: false
        ) else {
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func cgEventFlags(for modifiers: KeyModifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) {
            flags.insert(.maskCommand)
        }
        if modifiers.contains(.shift) {
            flags.insert(.maskShift)
        }
        if modifiers.contains(.control) {
            flags.insert(.maskControl)
        }
        if modifiers.contains(.option) {
            flags.insert(.maskAlternate)
        }
        return flags
    }

    private func postMediaKey(_ action: MediaAction) {
        let keyType: Int32
        switch action {
        case .volumeUp: keyType = 0
        case .volumeDown: keyType = 1
        case .mute: keyType = 7
        case .brightnessUp: keyType = 2
        case .brightnessDown: keyType = 3
        case .previousTrack: keyType = 18
        case .nextTrack: keyType = 17
        case .playPause: keyType = 16
        }

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
