import Foundation

public enum KnobPressDecision: Equatable, Sendable {
    case scheduleLongPress(after: TimeInterval)
    case performShortPress
    case switchProfile
}

public struct KnobPressStateMachine: Equatable, Sendable {
    public let longPressThreshold: TimeInterval

    private var pressedAt: TimeInterval?
    private var longPressTriggered = false

    public init(longPressThreshold: TimeInterval = 0.65) {
        self.longPressThreshold = longPressThreshold
    }

    public mutating func pressDown(at timestamp: TimeInterval) -> KnobPressDecision? {
        guard pressedAt == nil else { return nil }

        pressedAt = timestamp
        longPressTriggered = false
        return .scheduleLongPress(after: longPressThreshold)
    }

    public mutating func longPressTimerFired(at timestamp: TimeInterval) -> KnobPressDecision? {
        guard let pressedAt,
              !longPressTriggered,
              reachedThreshold(timestamp - pressedAt) else {
            return nil
        }

        longPressTriggered = true
        return .switchProfile
    }

    public mutating func pressUp(at timestamp: TimeInterval) -> KnobPressDecision? {
        guard let pressedAt else { return nil }

        let wasLongPress = longPressTriggered
        let elapsed = max(0, timestamp - pressedAt)
        reset()

        if wasLongPress {
            return nil
        }

        // If the main run loop delayed the timer, a late release still counts as long press.
        return reachedThreshold(elapsed) ? .switchProfile : .performShortPress
    }

    public mutating func reset() {
        pressedAt = nil
        longPressTriggered = false
    }

    private func reachedThreshold(_ elapsed: TimeInterval) -> Bool {
        // Decimal timestamps such as 20.65 are not exact binary floating-point values.
        elapsed + 1e-9 >= longPressThreshold
    }
}
