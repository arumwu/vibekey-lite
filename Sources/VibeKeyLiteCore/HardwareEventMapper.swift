import Foundation

public enum KeyPhase: Equatable, Sendable {
    case down
    case up
}

public enum DeviceEvent: Equatable, Sendable {
    case key(control: InputControl, phase: KeyPhase)
}

public enum HardwareEventMapper {
    public static let keyboardReportID: UInt32 = 0x03
    public static let keyboardUsagePage: UInt32 = 0x07
    public static let acceptedUsages: ClosedRange<UInt32> = 0x68...0x6D

    public static func event(
        reportID: UInt32,
        usagePage: UInt32,
        usage: UInt32,
        integerValue: Int
    ) -> DeviceEvent? {
        guard reportID == keyboardReportID,
              usagePage == keyboardUsagePage,
              acceptedUsages.contains(usage),
              integerValue >= 0 else {
            return nil
        }

        let phase: KeyPhase = integerValue > 0 ? .down : .up
        return event(forUSBHIDUsage: usage, phase: phase)
    }

    public static func event(
        forUSBHIDUsage usage: UInt32,
        phase: KeyPhase
    ) -> DeviceEvent? {
        let control: InputControl
        switch usage {
        case 0x68: control = .knobPress   // F13
        case 0x69: control = .knobLeft    // F14
        case 0x6A: control = .knobRight   // F15
        case 0x6B: control = .topButton   // F16
        case 0x6C: control = .middleButton // F17
        case 0x6D: control = .bottomButton // F18
        default: return nil
        }

        return .key(control: control, phase: phase)
    }
}

/// Turns HID values into unique key edges. Array elements can repeat the same
/// value while a control is held, so the app must not run an action twice.
public struct HIDKeyEdgeTracker: Equatable, Sendable {
    private var pressedUsages: Set<UInt32> = []

    public init() {}

    public mutating func transition(
        usage: UInt32,
        integerValue: Int
    ) -> KeyPhase? {
        guard integerValue >= 0 else { return nil }

        if integerValue > 0 {
            guard pressedUsages.insert(usage).inserted else { return nil }
            return .down
        }

        guard pressedUsages.remove(usage) != nil else { return nil }
        return .up
    }

    public mutating func reset() {
        pressedUsages.removeAll(keepingCapacity: true)
    }
}
