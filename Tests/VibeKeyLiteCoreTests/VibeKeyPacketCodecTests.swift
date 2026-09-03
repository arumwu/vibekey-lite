import XCTest
@testable import VibeKeyLiteCore

final class VibeKeyPacketCodecTests: XCTestCase {
    func testSoftwareOnlineAndOfflineKnownVectors() throws {
        let online = try VibeKeyPacketCodec.softwareOnlineReport(true)
        let offline = try VibeKeyPacketCodec.softwareOnlineReport(false)

        XCTAssertEqual(Array(online.prefix(9)), [
            0x55, 0x27, 0x71, 0x7F, 0x2F, 0x18, 0x97, 0xB9, 0x1A
        ])
        XCTAssertEqual(Array(offline.prefix(9)), [
            0x55, 0xC7, 0x05, 0x73, 0xE3, 0x23, 0xD5, 0xC4, 0x32
        ])
    }

    func testHeartbeatKnownVector() throws {
        let report = try VibeKeyPacketCodec.heartbeatReport()
        XCTAssertEqual(Array(report.prefix(9)), [
            0x55, 0x24, 0x56, 0x9E, 0xF2, 0x28, 0xE1, 0x45, 0xA1
        ])
    }

    func testNativeShortcutPlaintextRejectsUnknownActionPage() {
        XCTAssertThrowsError(
            try VibeKeyPacketCodec.shortcutPlaintext(
                index: 0,
                entries: [NativeShortcutEntry(pageAndSign: 0x7F, value: 1)]
            )
        )
    }

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
            usbHIDUsage: 0x6A
        )

        XCTAssertEqual(plaintext.count, 64)
        XCTAssertEqual(Array(plaintext.prefix(9)), [
            0x01, 0x06, 0x50, 0x04, 0x04, 0x01, 0x01, 0x02, 0x6A
        ])
        XCTAssertTrue(plaintext.dropFirst(9).allSatisfy { $0 == 0 })
    }

    func testF1AndF12OfflineShortcutPlaintextUsesUSBHIDUsages() throws {
        for (action, usage) in [(KeyAction.f1, UInt8(0x3A)), (.f12, UInt8(0x45))] {
            guard case let .shortcut(shortcut) = PresetNativeShortcutResolver.resolve(action) else {
                return XCTFail("Expected offline shortcut for \(action)")
            }

            let plaintext = try VibeKeyPacketCodec.shortcutPlaintext(
                index: 3,
                shortcut: shortcut
            )
            XCTAssertEqual(Array(plaintext.prefix(9)), [
                0x01, 0x06, 0x50, 0x04, 0x03, 0x01, 0x01, 0x02, usage
            ])
        }
    }

    func testLegacySingleUsageAPIEqualsNativeShortcutEncoding() throws {
        let shortcut = try NativeShortcut(
            entries: [.init(pageAndSign: 0x02, value: 0x6A)],
            displayName: "F15"
        )

        XCTAssertEqual(
            VibeKeyPacketCodec.shortcutPlaintext(index: 4, usbHIDUsage: 0x6A),
            try VibeKeyPacketCodec.shortcutPlaintext(index: 4, shortcut: shortcut)
        )
        XCTAssertEqual(
            try VibeKeyPacketCodec.shortcutReport(index: 4, usbHIDUsage: 0x6A),
            try VibeKeyPacketCodec.shortcutReport(index: 4, shortcut: shortcut)
        )
    }

    func testNativeShortcutPlaintextLayoutSupportsChords() throws {
        let shortcut = try NativeShortcut(
            entries: [
                .init(pageAndSign: 0x03, value: 0x08),
                .init(pageAndSign: 0x03, value: 0x02),
                .init(pageAndSign: 0x02, value: 0x22)
            ],
            displayName: "⌘⇧5（截圖）"
        )

        let plaintext = try VibeKeyPacketCodec.shortcutPlaintext(
            index: 2,
            shortcut: shortcut
        )

        XCTAssertEqual(plaintext.count, 64)
        XCTAssertEqual(Array(plaintext.prefix(13)), [
            0x01, 0x06, 0x50, 0x04, 0x02, 0x01, 0x03,
            0x03, 0x08,
            0x03, 0x02,
            0x02, 0x22
        ])
        XCTAssertTrue(plaintext.dropFirst(13).allSatisfy { $0 == 0 })
    }

    func testNativeShortcutPlaintextAllowsFourEntries() throws {
        let entries = [
            NativeShortcutEntry(pageAndSign: 0x03, value: 0x01),
            NativeShortcutEntry(pageAndSign: 0x03, value: 0x02),
            NativeShortcutEntry(pageAndSign: 0x03, value: 0x04),
            NativeShortcutEntry(pageAndSign: 0x02, value: 0x04)
        ]

        let plaintext = try VibeKeyPacketCodec.shortcutPlaintext(index: 5, entries: entries)

        XCTAssertEqual(Array(plaintext.prefix(15)), [
            0x01, 0x06, 0x50, 0x04, 0x05, 0x01, 0x04,
            0x03, 0x01,
            0x03, 0x02,
            0x03, 0x04,
            0x02, 0x04
        ])
    }

    func testFixedFunctionPlaintextLayout() {
        let plaintext = VibeKeyPacketCodec.fixedFunctionPlaintext(
            index: 4,
            functionCode: 0x0C
        )

        XCTAssertEqual(Array(plaintext.prefix(10)), [
            0x01, 0x06, 0x10, 0x04, 0x00, 0x04, 0x0C, 0x00, 0x00, 0x00
        ])
        XCTAssertTrue(plaintext.dropFirst(10).allSatisfy { $0 == 0 })
    }

    func testScreenshotChordReportMatchesVendorRuntimeVector() throws {
        let shortcut = try NativeShortcut(
            entries: [
                .init(pageAndSign: 0x03, value: 0x08),
                .init(pageAndSign: 0x03, value: 0x02),
                .init(pageAndSign: 0x02, value: 0x22)
            ],
            displayName: "⌘⇧5（截圖）"
        )

        let report = try VibeKeyPacketCodec.shortcutReport(index: 2, shortcut: shortcut)

        XCTAssertEqual(report.count, 64)
        XCTAssertEqual(Array(report.prefix(25)), [
            0x55,
            0x6F, 0x85, 0x10, 0xFC, 0xB7, 0xC2, 0x21, 0x3C,
            0x91, 0x19, 0xD0, 0xAF, 0x55, 0xDA, 0xFF, 0x04,
            0x38, 0x90, 0xC4, 0x99, 0xA3, 0x60, 0xAA, 0xAD
        ])
    }

    func testNativeShortcutPlaintextRejectsMoreThanFourEntries() {
        let entries = (0..<5).map {
            NativeShortcutEntry(pageAndSign: 0x02, value: UInt8($0))
        }

        XCTAssertThrowsError(
            try VibeKeyPacketCodec.shortcutPlaintext(index: 0, entries: entries)
        ) { error in
            XCTAssertEqual(
                error as? VibeKeyPacketCodecError,
                .tooManyShortcutEntries(maximum: 4, actual: 5)
            )
        }
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
