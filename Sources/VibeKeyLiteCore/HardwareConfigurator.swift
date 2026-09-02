import Foundation

public struct VibeKeyHIDDescriptor: Equatable, Sendable {
    public let vendorID: UInt16
    public let productID: UInt16
    public let usagePage: UInt16
    public let reportID: UInt8
    public let reportLength: Int

    public init(
        vendorID: UInt16,
        productID: UInt16,
        usagePage: UInt16,
        reportID: UInt8,
        reportLength: Int
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.usagePage = usagePage
        self.reportID = reportID
        self.reportLength = reportLength
    }

    public static let vibeKey = VibeKeyHIDDescriptor(
        vendorID: 0xFFF1,
        productID: 0x00DD,
        usagePage: 0xFFFC,
        reportID: 0x55,
        reportLength: 64
    )
}

public enum FunctionKey: Int, Codable, Equatable, Sendable {
    case f13 = 13
    case f14 = 14
    case f15 = 15
    case f16 = 16
    case f17 = 17
    case f18 = 18

    public var usbHIDUsage: UInt8 {
        // USB HID Usage Tables: Keyboard F13 starts at 0x68.
        UInt8(rawValue + 0x5B)
    }
}

public struct IndexedFunctionKey: Equatable, Sendable {
    public let index: UInt8
    public let functionKey: FunctionKey

    public init(index: UInt8, functionKey: FunctionKey) {
        self.index = index
        self.functionKey = functionKey
    }
}

public struct HardwareFunctionKeyLayout: Codable, Equatable, Sendable {
    public var knobPress: FunctionKey
    public var knobLeft: FunctionKey
    public var knobRight: FunctionKey
    public var topButton: FunctionKey
    public var middleButton: FunctionKey
    public var bottomButton: FunctionKey

    public init(
        knobPress: FunctionKey,
        knobLeft: FunctionKey,
        knobRight: FunctionKey,
        topButton: FunctionKey,
        middleButton: FunctionKey,
        bottomButton: FunctionKey
    ) {
        self.knobPress = knobPress
        self.knobLeft = knobLeft
        self.knobRight = knobRight
        self.topButton = topButton
        self.middleButton = middleButton
        self.bottomButton = bottomButton
    }

    public static let vibeKeyDefault = HardwareFunctionKeyLayout(
        knobPress: .f13,
        knobLeft: .f14,
        knobRight: .f15,
        topButton: .f16,
        middleButton: .f17,
        bottomButton: .f18
    )

    /// Device storage order: top, middle, bottom, knob press, clockwise, counter-clockwise.
    public var indexedFunctionKeys: [IndexedFunctionKey] {
        [
            IndexedFunctionKey(index: 0, functionKey: topButton),
            IndexedFunctionKey(index: 1, functionKey: middleButton),
            IndexedFunctionKey(index: 2, functionKey: bottomButton),
            IndexedFunctionKey(index: 3, functionKey: knobPress),
            IndexedFunctionKey(index: 4, functionKey: knobRight),
            IndexedFunctionKey(index: 5, functionKey: knobLeft)
        ]
    }
}

/// Boundary between app/UI code and the native HID transport.
public protocol HardwareConfigurator {
    func apply(layout: HardwareFunctionKeyLayout) throws
}

/// Useful for previews and tests that must not write to hardware.
public struct NoOpHardwareConfigurator: HardwareConfigurator {
    public init() {}

    public func apply(layout: HardwareFunctionKeyLayout) throws {}
}
