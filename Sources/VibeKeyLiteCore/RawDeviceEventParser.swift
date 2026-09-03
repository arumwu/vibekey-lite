import Foundation

public enum RawDeviceEventParser {
    public static func parse(reportID: UInt32, report: [UInt8]) -> DeviceEvent? {
        let carriesReportID = reportID == UInt32(VibeKeyPacketCodec.reportID)
            || (reportID == 0 && report.first == VibeKeyPacketCodec.reportID)
        guard carriesReportID,
              let plaintext = try? VibeKeyPacketCodec.decryptInputReport(report),
              plaintext.count >= 5,
              (plaintext[0] & 0x1F) == 0x0B,
              plaintext[1] == 0x10 else {
            return nil
        }

        let control: InputControl
        switch plaintext[4] {
        case 0: control = .topButton
        case 1: control = .middleButton
        case 2: control = .bottomButton
        case 3: control = .knobPress
        // Rotation notices represent one detent and do not use key status.
        case 4: return .key(control: .knobRight, phase: .down)
        case 5: return .key(control: .knobLeft, phase: .down)
        default: return nil
        }

        guard plaintext[3] <= 1 else { return nil }
        return .key(control: control, phase: plaintext[3] == 1 ? .down : .up)
    }
}
