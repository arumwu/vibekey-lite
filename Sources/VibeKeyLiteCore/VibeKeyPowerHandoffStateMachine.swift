import Foundation

public enum VibeKeyPowerHandoffDecision: Equatable, Sendable {
    /// Replace any previously scheduled handoff with this monotonic deadline.
    case scheduleStandbyHandoff(deadline: TimeInterval)
    case cancelStandbyHandoff
    case handoffForStandby
    case resumeOnline
}

public enum VibeKeyPowerHandoffMode: Equatable, Sendable {
    case inactive
    case online
    case handedOffForStandby
    case resumePending
}

public enum VibeKeyPowerHandoffSuspensionReason: Equatable, Sendable {
    case manualNative
    case onlinePrerequisiteLost
}

/// Pure policy for yielding online mode after inactivity and resuming it after
/// the device wakes. The caller owns timers and HID transport side effects.
public struct VibeKeyPowerHandoffStateMachine: Equatable, Sendable {
    public private(set) var idleInterval: TimeInterval

    public private(set) var mode: VibeKeyPowerHandoffMode = .inactive
    public private(set) var handoffDeadline: TimeInterval?
    public private(set) var suspensionReason: VibeKeyPowerHandoffSuspensionReason?

    public init(idleInterval: TimeInterval) {
        self.idleInterval = idleInterval.isFinite && idleInterval > 0
            ? idleInterval
            : 0
    }

    /// Call only after online mode has started successfully. This also clears a
    /// previous manual/prerequisite suspension because the caller explicitly
    /// confirmed that online operation is allowed again.
    public mutating func onlineStarted(at timestamp: TimeInterval) -> [VibeKeyPowerHandoffDecision] {
        mode = .online
        suspensionReason = nil
        return scheduleDeadline(after: timestamp)
    }

    /// Applies the device's saved standby delay without persisting anything.
    /// If online, the new value replaces the current inactivity deadline.
    public mutating func updateIdleInterval(
        _ interval: TimeInterval,
        at timestamp: TimeInterval
    ) -> [VibeKeyPowerHandoffDecision] {
        let normalizedInterval = interval.isFinite && interval > 0 ? interval : 0
        // Re-reading an unchanged device setting is not physical activity and
        // must not postpone the existing inactivity deadline.
        guard normalizedInterval != idleInterval else { return [] }
        idleInterval = normalizedInterval
        guard mode == .online else { return [] }
        if idleInterval == 0 {
            let hadScheduledHandoff = handoffDeadline != nil
            handoffDeadline = nil
            return hadScheduledHandoff ? [.cancelStandbyHandoff] : []
        }
        return scheduleDeadline(after: timestamp)
    }

    /// Physical input while online restarts the inactivity window.
    public mutating func deviceInput(at timestamp: TimeInterval) -> [VibeKeyPowerHandoffDecision] {
        guard mode == .online else { return [] }
        return scheduleDeadline(after: timestamp)
    }

    /// Stale timer callbacks are harmless: only the current deadline can cause
    /// the automatic handoff.
    public mutating func standbyHandoffDeadlineReached(
        at timestamp: TimeInterval
    ) -> [VibeKeyPowerHandoffDecision] {
        guard mode == .online,
              let handoffDeadline,
              timestamp + 1e-9 >= handoffDeadline else {
            return []
        }

        self.handoffDeadline = nil
        mode = .handedOffForStandby
        return [.handoffForStandby]
    }

    /// Device notices update runtime status only. Resuming on `powerOn` or
    /// `deviceActive` could suppress the key-up half of the first native
    /// shortcut, so the standard-HID release is the sole device wake signal.
    public mutating func noticeReceived(
        _ notice: VibeKeyDeviceNotice
    ) -> [VibeKeyPowerHandoffDecision] {
        []
    }

    /// The standard-HID path calls this only after the first native shortcut
    /// has returned to a neutral report, so its release cannot be swallowed.
    public mutating func wakeInputReceived() -> [VibeKeyPowerHandoffDecision] {
        guard mode == .handedOffForStandby else { return [] }
        return beginResume()
    }

    /// Manual native mode and lost online prerequisites are authoritative.
    /// Device notices and standard-HID input remain ignored until the caller
    /// explicitly reports a later successful `onlineStarted` transition.
    public mutating func suspendAutomaticResume(
        reason: VibeKeyPowerHandoffSuspensionReason
    ) -> [VibeKeyPowerHandoffDecision] {
        let hadScheduledHandoff = handoffDeadline != nil
        handoffDeadline = nil
        mode = .inactive
        suspensionReason = reason
        return hadScheduledHandoff ? [.cancelStandbyHandoff] : []
    }

    private mutating func scheduleDeadline(
        after timestamp: TimeInterval
    ) -> [VibeKeyPowerHandoffDecision] {
        guard idleInterval > 0, timestamp.isFinite else {
            handoffDeadline = nil
            return []
        }

        let deadline = timestamp + idleInterval
        guard deadline.isFinite else {
            handoffDeadline = nil
            return []
        }

        handoffDeadline = deadline
        return [.scheduleStandbyHandoff(deadline: deadline)]
    }

    private mutating func beginResume() -> [VibeKeyPowerHandoffDecision] {
        mode = .resumePending
        return [.resumeOnline]
    }
}
