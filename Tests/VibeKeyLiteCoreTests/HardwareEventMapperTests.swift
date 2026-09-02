import XCTest
@testable import VibeKeyLiteCore

final class HardwareEventMapperTests: XCTestCase {
    func testMapsUSBHIDF13ThroughF18() {
        XCTAssertEqual(HardwareEventMapper.event(forUSBHIDUsage: 0x68, phase: .down), .key(control: .knobPress, phase: .down))
        XCTAssertEqual(HardwareEventMapper.event(forUSBHIDUsage: 0x69, phase: .down), .key(control: .knobLeft, phase: .down))
        XCTAssertEqual(HardwareEventMapper.event(forUSBHIDUsage: 0x6A, phase: .down), .key(control: .knobRight, phase: .down))
        XCTAssertEqual(HardwareEventMapper.event(forUSBHIDUsage: 0x6B, phase: .down), .key(control: .topButton, phase: .down))
        XCTAssertEqual(HardwareEventMapper.event(forUSBHIDUsage: 0x6C, phase: .down), .key(control: .middleButton, phase: .down))
        XCTAssertEqual(HardwareEventMapper.event(forUSBHIDUsage: 0x6D, phase: .down), .key(control: .bottomButton, phase: .down))
    }

    func testMapsPositiveValueToDownAndZeroToUp() {
        XCTAssertEqual(
            HardwareEventMapper.event(reportID: 3, usagePage: 0x07, usage: 0x68, integerValue: 1),
            .key(control: .knobPress, phase: .down)
        )
        XCTAssertEqual(
            HardwareEventMapper.event(reportID: 3, usagePage: 0x07, usage: 0x68, integerValue: 0),
            .key(control: .knobPress, phase: .up)
        )
        XCTAssertEqual(
            HardwareEventMapper.event(reportID: 3, usagePage: 0x07, usage: 0x6B, integerValue: 2),
            .key(control: .topButton, phase: .down)
        )
    }

    func testIgnoresOtherDevicesElementsAndInvalidValues() {
        XCTAssertNil(HardwareEventMapper.event(reportID: 2, usagePage: 0x07, usage: 0x68, integerValue: 1))
        XCTAssertNil(HardwareEventMapper.event(reportID: 3, usagePage: 0x0C, usage: 0x68, integerValue: 1))
        XCTAssertNil(HardwareEventMapper.event(reportID: 3, usagePage: 0x07, usage: 0x67, integerValue: 1))
        XCTAssertNil(HardwareEventMapper.event(reportID: 3, usagePage: 0x07, usage: 0x6E, integerValue: 1))
        XCTAssertNil(HardwareEventMapper.event(reportID: 3, usagePage: 0x07, usage: 0x68, integerValue: -1))
    }

    func testDeduplicatesRepeatedEdgesAndResetDropsStalePress() {
        var tracker = HIDKeyEdgeTracker()

        XCTAssertEqual(tracker.transition(usage: 0x68, integerValue: 1), .down)
        XCTAssertNil(tracker.transition(usage: 0x68, integerValue: 2))
        XCTAssertEqual(tracker.transition(usage: 0x68, integerValue: 0), .up)
        XCTAssertNil(tracker.transition(usage: 0x68, integerValue: 0))

        XCTAssertEqual(tracker.transition(usage: 0x69, integerValue: 1), .down)
        tracker.reset()
        XCTAssertNil(tracker.transition(usage: 0x69, integerValue: 0))
        XCTAssertEqual(tracker.transition(usage: 0x69, integerValue: 1), .down)
    }
}
