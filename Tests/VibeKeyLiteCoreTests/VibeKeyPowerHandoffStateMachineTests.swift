import XCTest
@testable import VibeKeyLiteCore

final class VibeKeyPowerHandoffStateMachineTests: XCTestCase {
    func testOnlineStartSchedulesIdleHandoffDeadline() {
        var machine = VibeKeyPowerHandoffStateMachine(idleInterval: 300)

        XCTAssertEqual(
            machine.onlineStarted(at: 10),
            [.scheduleStandbyHandoff(deadline: 310)]
        )
        XCTAssertEqual(machine.mode, .online)
        XCTAssertEqual(machine.handoffDeadline, 310)
        XCTAssertNil(machine.suspensionReason)
    }

    func testDeviceInputReplacesDeadlineAndStaleTimerCannotHandoff() {
        var machine = VibeKeyPowerHandoffStateMachine(idleInterval: 300)
        _ = machine.onlineStarted(at: 10)

        XCTAssertEqual(
            machine.deviceInput(at: 100),
            [.scheduleStandbyHandoff(deadline: 400)]
        )
        XCTAssertEqual(machine.standbyHandoffDeadlineReached(at: 310), [])
        XCTAssertEqual(machine.mode, .online)
        XCTAssertEqual(machine.handoffDeadline, 400)
    }

    func testReadBackStandbyDelayReplacesTheCurrentDeadline() {
        var machine = VibeKeyPowerHandoffStateMachine(idleInterval: 300)
        _ = machine.onlineStarted(at: 10)

        XCTAssertEqual(
            machine.updateIdleInterval(600, at: 20),
            [.scheduleStandbyHandoff(deadline: 620)]
        )
        XCTAssertEqual(machine.idleInterval, 600)
        XCTAssertEqual(machine.handoffDeadline, 620)

        XCTAssertEqual(
            machine.updateIdleInterval(0, at: 30),
            [.cancelStandbyHandoff]
        )
        XCTAssertNil(machine.handoffDeadline)
    }

    func testReadingTheSameStandbyDelayDoesNotPostponeHandoff() {
        var machine = VibeKeyPowerHandoffStateMachine(idleInterval: 300)
        _ = machine.onlineStarted(at: 10)

        XCTAssertEqual(machine.updateIdleInterval(300, at: 200), [])
        XCTAssertEqual(machine.handoffDeadline, 310)
        XCTAssertEqual(
            machine.standbyHandoffDeadlineReached(at: 310),
            [.handoffForStandby]
        )
    }

    func testCurrentDeadlineHandsOffOnlyOnce() {
        var machine = VibeKeyPowerHandoffStateMachine(idleInterval: 300)
        _ = machine.onlineStarted(at: 10)

        XCTAssertEqual(
            machine.standbyHandoffDeadlineReached(at: 310),
            [.handoffForStandby]
        )
        XCTAssertEqual(machine.mode, .handedOffForStandby)
        XCTAssertNil(machine.handoffDeadline)
        XCTAssertEqual(machine.standbyHandoffDeadlineReached(at: 311), [])
    }

    func testPositiveWakeNoticesRequestOneResume() {
        for notice in [
            VibeKeyDeviceNotice.powerOn,
            .deviceActive(isActive: true),
            .standby(status: 0)
        ] {
            var machine = handedOffMachine()
            XCTAssertEqual(machine.noticeReceived(notice), [.resumeOnline])
            XCTAssertEqual(machine.mode, .resumePending)
            XCTAssertEqual(machine.noticeReceived(notice), [])
            XCTAssertEqual(machine.wakeInputReceived(), [])
        }
    }

    func testInactiveNoticesKeepStandardHIDWakeFallback() {
        for notice in [
            VibeKeyDeviceNotice.deviceActive(isActive: false),
            .standby(status: 1)
        ] {
            var machine = handedOffMachine()
            XCTAssertEqual(machine.noticeReceived(notice), [])
            XCTAssertEqual(machine.mode, .handedOffForStandby)
            XCTAssertEqual(machine.wakeInputReceived(), [.resumeOnline])
        }
    }

    func testStandardHIDWakeInputRequestsOneResume() {
        var machine = handedOffMachine()

        XCTAssertEqual(machine.wakeInputReceived(), [.resumeOnline])
        XCTAssertEqual(machine.mode, .resumePending)
        XCTAssertEqual(machine.wakeInputReceived(), [])
    }

    func testManualNativeCancelsDeadlineAndSuppressesAutomaticResume() {
        var machine = VibeKeyPowerHandoffStateMachine(idleInterval: 300)
        _ = machine.onlineStarted(at: 10)

        XCTAssertEqual(
            machine.suspendAutomaticResume(reason: .manualNative),
            [.cancelStandbyHandoff]
        )
        XCTAssertEqual(machine.mode, .inactive)
        XCTAssertEqual(machine.suspensionReason, .manualNative)
        XCTAssertNil(machine.handoffDeadline)
        XCTAssertEqual(machine.noticeReceived(.powerOn), [])
        XCTAssertEqual(machine.wakeInputReceived(), [])
        XCTAssertEqual(machine.standbyHandoffDeadlineReached(at: 999), [])
    }

    func testLostPrerequisiteSuppressesResumeAfterHandoff() {
        var machine = handedOffMachine()

        XCTAssertEqual(
            machine.suspendAutomaticResume(reason: .onlinePrerequisiteLost),
            []
        )
        XCTAssertEqual(machine.mode, .inactive)
        XCTAssertEqual(machine.suspensionReason, .onlinePrerequisiteLost)
        XCTAssertEqual(machine.noticeReceived(.deviceActive(isActive: true)), [])
        XCTAssertEqual(machine.wakeInputReceived(), [])
    }

    func testExplicitSuccessfulOnlineStartClearsSuspension() {
        var machine = VibeKeyPowerHandoffStateMachine(idleInterval: 300)
        _ = machine.suspendAutomaticResume(reason: .manualNative)

        XCTAssertEqual(
            machine.onlineStarted(at: 50),
            [.scheduleStandbyHandoff(deadline: 350)]
        )
        XCTAssertEqual(machine.mode, .online)
        XCTAssertNil(machine.suspensionReason)
    }

    func testNonpositiveOrInvalidIntervalDoesNotSchedule() {
        for interval in [0, -1, .infinity, .nan] {
            var machine = VibeKeyPowerHandoffStateMachine(idleInterval: interval)
            XCTAssertEqual(machine.onlineStarted(at: 10), [])
            XCTAssertNil(machine.handoffDeadline)
            XCTAssertEqual(machine.mode, .online)
        }

        var machine = VibeKeyPowerHandoffStateMachine(idleInterval: 300)
        XCTAssertEqual(machine.onlineStarted(at: .nan), [])
        XCTAssertNil(machine.handoffDeadline)
    }

    private func handedOffMachine() -> VibeKeyPowerHandoffStateMachine {
        var machine = VibeKeyPowerHandoffStateMachine(idleInterval: 300)
        _ = machine.onlineStarted(at: 10)
        _ = machine.standbyHandoffDeadlineReached(at: 310)
        return machine
    }
}
