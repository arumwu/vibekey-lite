import XCTest
@testable import VibeKeyLiteCore

final class KnobPressStateMachineTests: XCTestCase {
    func testSinglePressWaitsUntilDoubleClickWindowCloses() {
        var machine = KnobPressStateMachine(
            longPressThreshold: 0.65,
            doublePressInterval: 0.28
        )

        XCTAssertEqual(machine.pressDown(at: 10), [.scheduleLongPress(after: 0.65)])
        XCTAssertEqual(machine.pressUp(at: 10.1), [.scheduleSinglePress(after: 0.28)])
        XCTAssertEqual(machine.singlePressTimerFired(), .performSinglePress)
        XCTAssertNil(machine.singlePressTimerFired())
    }

    func testDoublePressCancelsSingleAndPerformsDoubleOnly() {
        var machine = KnobPressStateMachine()

        _ = machine.pressDown(at: 20)
        _ = machine.pressUp(at: 20.08)
        XCTAssertEqual(machine.pressDown(at: 20.20), [
            .cancelPendingSinglePress,
            .scheduleLongPress(after: 0.65)
        ])
        XCTAssertNil(machine.singlePressTimerFired())
        XCTAssertEqual(machine.pressUp(at: 20.27), [
            .cancelPendingSinglePress,
            .performDoublePress
        ])
    }

    func testLongPressWaitsForReleaseThenSwitches() {
        var machine = KnobPressStateMachine()

        _ = machine.pressDown(at: 30)
        XCTAssertEqual(machine.longPressTimerFired(), [
            .cancelPendingSinglePress,
            .longPressRecognized
        ])
        XCTAssertEqual(machine.longPressTimerFired(), [])
        XCTAssertEqual(machine.pressUp(at: 31), [
            .cancelPendingSinglePress,
            .switchProfile
        ])
    }

    func testLateReleaseStillCountsAsLongPress() {
        var machine = KnobPressStateMachine()
        _ = machine.pressDown(at: 40)
        XCTAssertEqual(machine.pressUp(at: 40.8), [
            .cancelPendingSinglePress,
            .switchProfile
        ])
    }

    func testPressAfterExpiredWindowFlushesFirstSingle() {
        var machine = KnobPressStateMachine(doublePressInterval: 0.28)
        _ = machine.pressDown(at: 50)
        _ = machine.pressUp(at: 50.1)

        XCTAssertEqual(machine.pressDown(at: 50.5), [
            .cancelPendingSinglePress,
            .performSinglePress,
            .scheduleLongPress(after: 0.65)
        ])
    }

    func testShortFirstPressThenLongSecondPressOnlySwitchesOnRelease() {
        var machine = KnobPressStateMachine()
        _ = machine.pressDown(at: 60)
        _ = machine.pressUp(at: 60.08)
        XCTAssertEqual(machine.pressDown(at: 60.20), [
            .cancelPendingSinglePress,
            .scheduleLongPress(after: 0.65)
        ])
        XCTAssertEqual(machine.longPressTimerFired(), [
            .cancelPendingSinglePress,
            .longPressRecognized
        ])
        XCTAssertEqual(machine.pressUp(at: 61), [
            .cancelPendingSinglePress,
            .switchProfile
        ])
    }

    func testRepeatDownStrayUpAndResetAreSafe() {
        var machine = KnobPressStateMachine()
        XCTAssertEqual(machine.pressUp(at: 1), [])
        XCTAssertFalse(machine.pressDown(at: 2).isEmpty)
        XCTAssertEqual(machine.pressDown(at: 2.1), [])
        machine.reset()
        XCTAssertNil(machine.singlePressTimerFired())
        XCTAssertEqual(machine.pressUp(at: 3), [])
    }
}
