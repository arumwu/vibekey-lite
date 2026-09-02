import XCTest
@testable import VibeKeyLiteCore

final class VibeKeyPacketCodecTests: XCTestCase {
    func testGetterKnownVector() throws {
        var plaintext = [UInt8](repeating: 0, count: 64)
        plaintext[0] = 0x01
        plaintext[1] = 0x06
        plaintext[2] = 0x50
        plaintext[3] = 0x01

        let report = try VibeKeyPacketCodec.outputReport(encrypting: plaintext)
        let expectedPrefix: [UInt8] = [
            0x55,
            0x57, 0xDF, 0x12, 0xE6, 0x02, 0xD7, 0x9D, 0xFD,
            0x38, 0x90, 0xC4, 0x99, 0xA3, 0x60, 0xAA, 0xAD,
            0x38, 0x90, 0xC4, 0x99, 0xA3, 0x60, 0xAA
        ]

        XCTAssertEqual(report.count, 64)
        XCTAssertEqual(Array(report.prefix(24)), expectedPrefix)
    }

    func testHookCommandKnownCipherBlock() throws {
        var plaintext = [UInt8](repeating: 0, count: 64)
        plaintext.replaceSubrange(
            0..<8,
            with: [0x01, 0x0B, 0x89, 0x04, 0x01, 0x00, 0x00, 0x00]
        )

        let encrypted = try VibeKeyPacketCodec.encrypt(plaintext)

        XCTAssertEqual(
            Array(encrypted.prefix(8)),
            [0x2F, 0xFE, 0x1A, 0xAD, 0x13, 0x00, 0x5A, 0x55]
        )
    }

    func testShortcutPlaintextLayout() {
        let plaintext = VibeKeyPacketCodec.shortcutPlaintext(
            index: 4,
            usbHIDUsage: FunctionKey.f15.usbHIDUsage
        )

        XCTAssertEqual(plaintext.count, 64)
        XCTAssertEqual(Array(plaintext.prefix(9)), [
            0x01, 0x06, 0x50, 0x04, 0x04, 0x01, 0x01, 0x02, 0x6A
        ])
        XCTAssertTrue(plaintext.dropFirst(9).allSatisfy { $0 == 0 })
    }

    func testKnobPressF13ReportMatchesVendorRuntimeVector() throws {
        let report = try VibeKeyPacketCodec.shortcutReport(index: 3, usbHIDUsage: 0x68)

        XCTAssertEqual(report.count, 64)
        XCTAssertEqual(Array(report.prefix(17)), [
            0x55,
            0xC9, 0x29, 0xAA, 0xDC, 0xFF, 0x7C, 0xF9, 0x70,
            0x49, 0x44, 0x98, 0x0E, 0xC1, 0x4E, 0x7C, 0x51
        ])
    }

    func testRejectsWrongPlaintextLength() {
        XCTAssertThrowsError(try VibeKeyPacketCodec.encrypt([0])) { error in
            XCTAssertEqual(
                error as? VibeKeyPacketCodecError,
                .invalidPlaintextLength(actual: 1)
            )
        }
    }
}
