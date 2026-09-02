import XCTest
@testable import VibeKeyLiteCore

final class HardwareConfiguratorTests: XCTestCase {
    func testKnownHIDDescriptor() {
        XCTAssertEqual(VibeKeyHIDDescriptor.vibeKey.vendorID, 0xFFF1)
        XCTAssertEqual(VibeKeyHIDDescriptor.vibeKey.productID, 0x00DD)
        XCTAssertEqual(VibeKeyHIDDescriptor.vibeKey.usagePage, 0xFFFC)
        XCTAssertEqual(VibeKeyHIDDescriptor.vibeKey.reportID, 0x55)
        XCTAssertEqual(VibeKeyHIDDescriptor.vibeKey.reportLength, 64)
    }

    func testDefaultLayoutMatchesPhysicalControls() {
        let layout = HardwareFunctionKeyLayout.vibeKeyDefault
        XCTAssertEqual(layout.knobPress, .f13)
        XCTAssertEqual(layout.knobLeft, .f14)
        XCTAssertEqual(layout.knobRight, .f15)
        XCTAssertEqual(layout.topButton, .f16)
        XCTAssertEqual(layout.middleButton, .f17)
        XCTAssertEqual(layout.bottomButton, .f18)
        XCTAssertEqual(
            layout.indexedFunctionKeys,
            [
                IndexedFunctionKey(index: 0, functionKey: .f16),
                IndexedFunctionKey(index: 1, functionKey: .f17),
                IndexedFunctionKey(index: 2, functionKey: .f18),
                IndexedFunctionKey(index: 3, functionKey: .f13),
                IndexedFunctionKey(index: 4, functionKey: .f15),
                IndexedFunctionKey(index: 5, functionKey: .f14)
            ]
        )
    }

    func testFunctionKeyUSBHIDUsages() {
        XCTAssertEqual(FunctionKey.f13.usbHIDUsage, 0x68)
        XCTAssertEqual(FunctionKey.f14.usbHIDUsage, 0x69)
        XCTAssertEqual(FunctionKey.f15.usbHIDUsage, 0x6A)
        XCTAssertEqual(FunctionKey.f16.usbHIDUsage, 0x6B)
        XCTAssertEqual(FunctionKey.f17.usbHIDUsage, 0x6C)
        XCTAssertEqual(FunctionKey.f18.usbHIDUsage, 0x6D)
    }

    func testProtocolCanBeReplacedWithRecordingMock() throws {
        final class RecordingConfigurator: HardwareConfigurator {
            var appliedLayouts: [HardwareFunctionKeyLayout] = []

            func apply(layout: HardwareFunctionKeyLayout) throws {
                appliedLayouts.append(layout)
            }
        }

        let mock = RecordingConfigurator()
        try mock.apply(layout: .vibeKeyDefault)

        XCTAssertEqual(mock.appliedLayouts, [.vibeKeyDefault])
    }
}
