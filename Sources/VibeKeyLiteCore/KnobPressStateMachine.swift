import Foundation

public enum KnobPressDecision: Equatable, Sendable {
    case scheduleLongPress(after: TimeInterval)
    case scheduleSinglePress(after: TimeInterval)
    case cancelPendingSinglePress
    case performSinglePress
    case performDoublePress
    case longPressRecognized
    case switchProfile
}

/// Distinguishes one click, two clicks, and a 0.65-second hold without ever
/// firing the single-click action before the double-click window has closed.
public struct KnobPressStateMachine: Equatable, Sendable {
    public let longPressThreshold: TimeInterval
    public let doublePressInterval: TimeInterval

    private var pressedAt: TimeInterval?
    private var firstReleasedAt: TimeInterval?
    private var isSecondPress = false
    private var longPressWasRecognized = false

    public init(
        longPressThreshold: TimeInterval = 0.65,
        doublePressInterval: TimeInterval = 0.28
    ) {
        self.longPressThreshold = longPressThreshold
        self.doublePressInterval = doublePressInterval
    }

    public mutating func pressDown(at timestamp: TimeInterval) -> [KnobPressDecision] {
        guard pressedAt == nil else { return [] }

        var decisions: [KnobPressDecision] = []
        if let firstReleasedAt,
           timestamp - firstReleasedAt <= doublePressInterval + 1e-9 {
            isSecondPress = true
            decisions.append(.cancelPendingSinglePress)
        } else {
            if firstReleasedAt != nil {
                decisions.append(.cancelPendingSinglePress)
                decisions.append(.performSinglePress)
            }
            self.firstReleasedAt = nil
            isSecondPress = false
        }

        pressedAt = timestamp
        longPressWasRecognized = false
        decisions.append(.scheduleLongPress(after: longPressThreshold))
        return decisions
    }

    public mutating func pressUp(at timestamp: TimeInterval) -> [KnobPressDecision] {
        guard let pressedAt else { return [] }

        let elapsed = max(0, timestamp - pressedAt)
        self.pressedAt = nil

        if longPressWasRecognized || reachedLongPressThreshold(elapsed) {
            clearClickCycle()
            return [.cancelPendingSinglePress, .switchProfile]
        }

        if isSecondPress {
            clearClickCycle()
            return [.cancelPendingSinglePress, .performDoublePress]
        }

        firstReleasedAt = timestamp
        return [.scheduleSinglePress(after: doublePressInterval)]
    }

    public mutating func singlePressTimerFired() -> KnobPressDecision? {
        guard pressedAt == nil, firstReleasedAt != nil else { return nil }
        clearClickCycle()
        return .performSinglePress
    }

    public mutating func longPressTimerFired() -> [KnobPressDecision] {
        guard pressedAt != nil, !longPressWasRecognized else { return [] }
        longPressWasRecognized = true
        firstReleasedAt = nil
        return [.cancelPendingSinglePress, .longPressRecognized]
    }

    public mutating func reset() {
        pressedAt = nil
        clearClickCycle()
    }

    private mutating func clearClickCycle() {
        firstReleasedAt = nil
        isSecondPress = false
        longPressWasRecognized = false
    }

    private func reachedLongPressThreshold(_ elapsed: TimeInterval) -> Bool {
        elapsed + 1e-9 >= longPressThreshold
    }
}
