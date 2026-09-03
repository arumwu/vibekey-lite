import XCTest
@testable import VibeKeyLiteCore

final class VibeKeyDeviceNoticeTests: XCTestCase {
    func testParsesStandbyNoticeAndPreservesRawStatus() {
        XCTAssertEqual(
            VibeKeyDeviceNoticeParser.parse(plaintext: [0x0B, 0x0D, 0x00]),
            .standby(status: 0x00)
        )
        XCTAssertEqual(
            VibeKeyDeviceNoticeParser.parse(plaintext: [0x8B, 0x0D, 0x7F]),
            .standby(status: 0x7F)
        )
    }

    func testDeviceActiveUsesOnlyLowBit() {
        XCTAssertEqual(
            VibeKeyDeviceNoticeParser.parse(plaintext: [0x0B, 0x0B, 0xA4]),
            .deviceActive(isActive: false)
        )
        XCTAssertEqual(
            VibeKeyDeviceNoticeParser.parse(plaintext: [0xCB, 0x0B, 0xA5]),
            .deviceActive(isActive: true)
        )
    }

    func testParsesPayloadFreePowerOnNotice() {
        XCTAssertEqual(
            VibeKeyDeviceNoticeParser.parse(plaintext: [0x0B, 0xF0]),
            .powerOn
        )
    }

    func testParsesEncryptedReport() throws {
        var plaintext = [UInt8](repeating: 0, count: 64)
        plaintext.replaceSubrange(0..<3, with: [0x8B, 0x0D, 0x02])
        let report = try VibeKeyPacketCodec.encrypt(plaintext)

        XCTAssertEqual(
            VibeKeyDeviceNoticeParser.parse(
                reportID: UInt32(VibeKeyPacketCodec.reportID),
                report: report
            ),
            .standby(status: 0x02)
        )
    }

    func testAcceptsReportIDInsideBufferWhenCallbackReportsZero() throws {
        var plaintext = [UInt8](repeating: 0, count: 64)
        plaintext.replaceSubrange(0..<3, with: [0x0B, 0x0B, 0x03])
        let encrypted = try VibeKeyPacketCodec.encrypt(plaintext)
        let report = [VibeKeyPacketCodec.reportID] + encrypted.prefix(63)

        XCTAssertEqual(
            VibeKeyDeviceNoticeParser.parse(reportID: 0, report: Array(report)),
            .deviceActive(isActive: true)
        )
    }

    func testRejectsWrongGroupSubtypeTruncatedPayloadAndReportID() throws {
        XCTAssertNil(VibeKeyDeviceNoticeParser.parse(plaintext: [0x0A, 0x0D, 1]))
        XCTAssertNil(VibeKeyDeviceNoticeParser.parse(plaintext: [0x0B, 0x10, 1]))
        XCTAssertNil(VibeKeyDeviceNoticeParser.parse(plaintext: [0x0B, 0x0D]))
        XCTAssertNil(VibeKeyDeviceNoticeParser.parse(plaintext: [0x0B, 0x0B]))

        let encrypted = try VibeKeyPacketCodec.encrypt(
            [0x0B, 0xF0] + [UInt8](repeating: 0, count: 62)
        )
        XCTAssertNil(VibeKeyDeviceNoticeParser.parse(reportID: 0x54, report: encrypted))
    }
}
