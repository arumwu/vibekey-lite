import XCTest
@testable import VibeKeyLiteCore

final class KnobPressStateMachineTests: XCTestCase {
    func testShortPressRunsConfiguredActionOnRelease() {
        var machine = KnobPressStateMachine(longPressThreshold: 0.65)

        XCTAssertEqual(machine.pressDown(at: 10), .scheduleLongPress(after: 0.65))
        XCTAssertEqual(machine.pressUp(at: 10.4), .performShortPress)
    }

    func testTimerSwitchesProfileOnceAndReleaseDoesNothing() {
        var machine = KnobPressStateMachine(longPressThreshold: 0.65)

        _ = machine.pressDown(at: 20)
        XCTAssertEqual(machine.longPressTimerFired(at: 20.65), .switchProfile)
        XCTAssertNil(machine.longPressTimerFired(at: 21))
        XCTAssertNil(machine.pressUp(at: 21.1))
    }

    func testLateReleaseStillCountsAsLongPressIfTimerWasDelayed() {
        var machine = KnobPressStateMachine(longPressThreshold: 0.65)

        _ = machine.pressDown(at: 30)
        XCTAssertEqual(machine.pressUp(at: 30.8), .switchProfile)
    }

    func testRepeatDownAndStrayUpAreIgnored() {
        var machine = KnobPressStateMachine()

        XCTAssertNil(machine.pressUp(at: 1))
        XCTAssertNotNil(machine.pressDown(at: 2))
        XCTAssertNil(machine.pressDown(at: 2.1))
    }
}
