import XCTest
@testable import VibeKeyLiteCore

final class RawDeviceEventParserTests: XCTestCase {
    func testParsesButtonDownAndUpWithSequenceBits() throws {
        XCTAssertEqual(
            try parse(header: 0x8B, status: 1, physicalIndex: 3),
            .key(control: .knobPress, phase: .down)
        )
        XCTAssertEqual(
            try parse(header: 0xCB, status: 0, physicalIndex: 0),
            .key(control: .topButton, phase: .up)
        )
    }

    func testRotationIsOneDetentRegardlessOfStatusByte() throws {
        XCTAssertEqual(
            try parse(header: 0x0B, status: 0x7F, physicalIndex: 4),
            .key(control: .knobRight, phase: .down)
        )
        XCTAssertEqual(
            try parse(header: 0x2B, status: 0, physicalIndex: 5),
            .key(control: .knobLeft, phase: .down)
        )
    }

    func testAcceptsReportIDInsideBufferWhenCallbackReportsZero() throws {
        var plaintext = [UInt8](repeating: 0, count: 64)
        plaintext.replaceSubrange(0..<5, with: [0x8B, 0x10, 0x6E, 1, 1])
        let encrypted = try VibeKeyPacketCodec.encrypt(plaintext)
        let report = [VibeKeyPacketCodec.reportID] + encrypted.prefix(63)

        XCTAssertEqual(
            RawDeviceEventParser.parse(reportID: 0, report: Array(report)),
            .key(control: .middleButton, phase: .down)
        )
    }

    func testRejectsWrongCommandAndUnknownPhysicalIndex() throws {
        XCTAssertNil(try parse(header: 0x8A, status: 1, physicalIndex: 3))
        XCTAssertNil(try parse(header: 0x8B, status: 1, physicalIndex: 6))
    }

    private func parse(
        header: UInt8,
        status: UInt8,
        physicalIndex: UInt8
    ) throws -> DeviceEvent? {
        var plaintext = [UInt8](repeating: 0, count: 64)
        plaintext.replaceSubrange(
            0..<5,
            with: [header, 0x10, 0x6E, status, physicalIndex]
        )
        let report = try VibeKeyPacketCodec.encrypt(plaintext)
        return RawDeviceEventParser.parse(
            reportID: UInt32(VibeKeyPacketCodec.reportID),
            report: report
        )
    }
}
