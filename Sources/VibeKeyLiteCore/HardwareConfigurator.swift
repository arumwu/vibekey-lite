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

public struct IndexedControlBinding: Equatable, Sendable {
    public let index: UInt8
    public let control: InputControl
    public let binding: ControlBinding

    public init(index: UInt8, control: InputControl, binding: ControlBinding) {
        self.index = index
        self.control = control
        self.binding = binding
    }
}

public extension ProfileConfiguration {
    /// Device storage order: top, middle, bottom, knob press, clockwise, counter-clockwise.
    /// Double press is an online-only gesture and is intentionally not persisted here.
    var indexedControlBindings: [IndexedControlBinding] {
        [
            IndexedControlBinding(index: 0, control: .topButton, binding: self[.topButton]),
            IndexedControlBinding(index: 1, control: .middleButton, binding: self[.middleButton]),
            IndexedControlBinding(index: 2, control: .bottomButton, binding: self[.bottomButton]),
            IndexedControlBinding(index: 3, control: .knobPress, binding: self[.knobPress]),
            IndexedControlBinding(index: 4, control: .knobRight, binding: self[.knobRight]),
            IndexedControlBinding(index: 5, control: .knobLeft, binding: self[.knobLeft])
        ]
    }
}

/// Boundary between app/UI code and the native HID transport.
public protocol HardwareConfigurator {
    func apply(profile: ProfileConfiguration) throws
}

/// Useful for previews and tests that must not write to hardware.
public struct NoOpHardwareConfigurator: HardwareConfigurator {
    public init() {}

    public func apply(profile: ProfileConfiguration) throws {}
}
