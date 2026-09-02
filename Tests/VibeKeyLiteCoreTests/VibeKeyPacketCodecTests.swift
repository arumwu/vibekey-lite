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
            0x51, 0xA3, 0xCF, 0x7E, 0x19, 0x7B, 0x40, 0x32,
            0x99, 0x49, 0x8F, 0xC4, 0x6C, 0x40, 0xB5, 0x95,
            0x99, 0x49, 0x8F, 0xC4, 0x6C, 0x40, 0xB5
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
            [0xF5, 0x18, 0x84, 0x1F, 0xFE, 0x11, 0x41, 0x8F]
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

    func testShortcutReportHasExpectedShape() throws {
        let report = try VibeKeyPacketCodec.shortcutReport(index: 0, usbHIDUsage: 0x6B)

        XCTAssertEqual(report.count, 64)
        XCTAssertEqual(report.first, 0x55)
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
