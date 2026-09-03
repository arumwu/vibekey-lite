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

    func testProtocolCanBeReplacedWithRecordingMock() throws {
        final class RecordingConfigurator: HardwareConfigurator {
            var appliedProfiles: [ProfileConfiguration] = []

            func apply(profile: ProfileConfiguration) throws {
                appliedProfiles.append(profile)
            }
        }

        let mock = RecordingConfigurator()
        let profile = AppConfiguration.default.profileA
        try mock.apply(profile: profile)

        XCTAssertEqual(mock.appliedProfiles, [profile])
    }

    func testNativeProfileUsesDeviceStorageOrder() {
        let bindings = AppConfiguration.default.profileA.indexedControlBindings

        XCTAssertEqual(bindings.map(\.index), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(
            bindings.map(\.control),
            [.topButton, .middleButton, .bottomButton, .knobPress, .knobRight, .knobLeft]
        )
        XCTAssertEqual(bindings[3].binding, .preset(.selectAll))
        XCTAssertFalse(bindings.contains { $0.control == .knobDoublePress })
    }
}
