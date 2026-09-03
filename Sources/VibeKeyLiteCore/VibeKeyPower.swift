import Foundation

public enum VibeKeyPowerQuery: CaseIterable, Equatable, Sendable {
    case battery
    case standbyStatus
    case standbyTime
    case sleepTime

    var commandGroup: UInt8 {
        switch self {
        case .battery, .standbyStatus, .standbyTime, .sleepTime:
            0x01
        }
    }

    var commandID: UInt8 {
        switch self {
        case .battery: 0x02
        case .standbyStatus: 0x0D
        case .standbyTime: 0x2C
        case .sleepTime: 0x42
        }
    }
}

public struct VibeKeyBatteryStatus: Equatable, Sendable {
    public let percent: UInt16
    public let voltageMillivolts: UInt16
    public let isCharging: Bool
    public let isFullyCharged: Bool
    public let lowBatteryLevel: UInt8
    public let isPoweredOff: Bool

    public init(
        percent: UInt16,
        voltageMillivolts: UInt16,
        isCharging: Bool,
        isFullyCharged: Bool,
        lowBatteryLevel: UInt8,
        isPoweredOff: Bool
    ) {
        self.percent = percent
        self.voltageMillivolts = voltageMillivolts
        self.isCharging = isCharging
        self.isFullyCharged = isFullyCharged
        self.lowBatteryLevel = lowBatteryLevel
        self.isPoweredOff = isPoweredOff
    }
}

public enum VibeKeyPowerResponse: Equatable, Sendable {
    case battery(VibeKeyBatteryStatus)
    case standbyStatus(isStandby: Bool)
    case standbyTime(seconds: UInt32)
    case sleepTime(seconds: UInt32)
}

/// Runtime-only values read from the AU05. This is deliberately separate from
/// AppConfiguration so a stale battery reading is never persisted to disk.
public struct VibeKeyPowerSnapshot: Equatable, Sendable {
    public var battery: VibeKeyBatteryStatus?
    public var isStandby: Bool?
    public var standbyTimeSeconds: UInt32?
    public var sleepTimeSeconds: UInt32?

    public init(
        battery: VibeKeyBatteryStatus? = nil,
        isStandby: Bool? = nil,
        standbyTimeSeconds: UInt32? = nil,
        sleepTimeSeconds: UInt32? = nil
    ) {
        self.battery = battery
        self.isStandby = isStandby
        self.standbyTimeSeconds = standbyTimeSeconds
        self.sleepTimeSeconds = sleepTimeSeconds
    }

    public mutating func apply(_ response: VibeKeyPowerResponse) {
        switch response {
        case let .battery(status):
            battery = status
        case let .standbyStatus(isStandby):
            self.isStandby = isStandby
        case let .standbyTime(seconds):
            standbyTimeSeconds = seconds
        case let .sleepTime(seconds):
            sleepTimeSeconds = seconds
        }
    }
}

public enum VibeKeyPowerResponseParser {
    public static func parse(reportID: UInt32, report: [UInt8]) -> VibeKeyPowerResponse? {
        let carriesReportID = reportID == UInt32(VibeKeyPacketCodec.reportID)
            || (reportID == 0 && report.first == VibeKeyPacketCodec.reportID)
        guard carriesReportID,
              let plaintext = try? VibeKeyPacketCodec.decryptInputReport(report) else {
            return nil
        }
        return parse(plaintext: plaintext)
    }

    public static func parse(plaintext: [UInt8]) -> VibeKeyPowerResponse? {
        guard plaintext.count >= 5,
              (plaintext[0] & 0x1F) == 0x01,
              plaintext[1] == 0x01,
              (plaintext[3] & 0x11) == 0x11 else {
            return nil
        }

        switch plaintext[2] {
        case 0x02:
            guard plaintext.count >= 12 else { return nil }
            let percent = readLittleEndianUInt16(plaintext, offset: 6)
            guard percent <= 100 else { return nil }
            let flags = plaintext[11]
            return .battery(VibeKeyBatteryStatus(
                percent: percent,
                voltageMillivolts: readLittleEndianUInt16(plaintext, offset: 4),
                isCharging: plaintext[10] != 0,
                isFullyCharged: (flags & 0x08) != 0,
                lowBatteryLevel: flags & 0x03,
                isPoweredOff: (flags & 0x04) != 0
            ))

        case 0x0D:
            guard plaintext[4] <= 1 else { return nil }
            return .standbyStatus(isStandby: plaintext[4] == 1)

        case 0x2C:
            guard plaintext.count >= 8 else { return nil }
            return .standbyTime(seconds: readLittleEndianUInt32(plaintext, offset: 4))

        case 0x42:
            guard plaintext.count >= 8 else { return nil }
            return .sleepTime(seconds: readLittleEndianUInt32(plaintext, offset: 4))

        default:
            return nil
        }
    }

    private static func readLittleEndianUInt16(_ bytes: [UInt8], offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readLittleEndianUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}
