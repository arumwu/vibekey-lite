import XCTest
@testable import VibeKeyLiteCore

final class MacKeyCodeShortcutMapperTests: XCTestCase {
    func testMapsLeftOption() throws {
        let shortcut = try MacKeyCodeShortcutMapper.shortcut(
            for: [58],
            fallbackName: nil
        )

        XCTAssertEqual(
            shortcut.entries,
            [.init(pageAndSign: 0x03, value: 0x04)]
        )
        XCTAssertEqual(shortcut.displayName, "左 Option")
    }

    func testMapsRightOptionSeparately() throws {
        let shortcut = try MacKeyCodeShortcutMapper.shortcut(
            for: [61],
            fallbackName: nil
        )

        XCTAssertEqual(
            shortcut.entries,
            [.init(pageAndSign: 0x03, value: 0x40)]
        )
        XCTAssertEqual(shortcut.displayName, "右 Option")
    }

    func testMapsDelete() throws {
        let shortcut = try MacKeyCodeShortcutMapper.shortcut(
            for: [51],
            fallbackName: nil
        )

        XCTAssertEqual(
            shortcut.entries,
            [.init(pageAndSign: 0x02, value: 0x2A)]
        )
        XCTAssertEqual(shortcut.displayName, "Delete")
    }

    func testMapsForwardDelete() throws {
        let shortcut = try MacKeyCodeShortcutMapper.shortcut(
            for: [117],
            fallbackName: nil
        )

        XCTAssertEqual(
            shortcut.entries,
            [.init(pageAndSign: 0x02, value: 0x4C)]
        )
        XCTAssertEqual(shortcut.displayName, "Forward Delete")
    }

    func testRejectsFunctionKeyExplicitly() {
        XCTAssertThrowsError(
            try MacKeyCodeShortcutMapper.shortcut(for: [63], fallbackName: nil)
        ) { error in
            XCTAssertEqual(
                error as? MacKeyCodeShortcutError,
                .functionKeyUnsupported
            )
            XCTAssertEqual(
                error.localizedDescription,
                "AU05 韌體無法離線輸出 Fn。請在 Typeless 改用另一組快捷鍵。"
            )
        }
    }

    func testAllowsF18NowThatItIsNotReserved() throws {
        let shortcut = try MacKeyCodeShortcutMapper.shortcut(
            for: [79],
            fallbackName: nil
        )
        XCTAssertEqual(shortcut.entries, [.init(pageAndSign: 0x02, value: 0x6D)])
        XCTAssertEqual(shortcut.displayName, "F18")
        XCTAssertEqual(MacKeyCodeShortcutMapper.macKeyCode(forUSBHIDUsage: 0x6D), 79)
        XCTAssertEqual(MacKeyCodeShortcutMapper.macKeyCode(forModifierBit: 0x04), 58)
        XCTAssertEqual(MacKeyCodeShortcutMapper.macKeyCode(forModifierBit: 0x40), 61)
    }

    func testMapsF1ThroughF12InBothDirections() throws {
        let macKeyCodes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

        for (offset, keyCode) in macKeyCodes.enumerated() {
            let usage = UInt8(0x3A + offset)
            let shortcut = try MacKeyCodeShortcutMapper.shortcut(
                for: [keyCode],
                fallbackName: nil
            )
            XCTAssertEqual(shortcut.entries, [.init(pageAndSign: 0x02, value: usage)])
            XCTAssertEqual(shortcut.displayName, "F\(offset + 1)")
            XCTAssertEqual(MacKeyCodeShortcutMapper.macKeyCode(forUSBHIDUsage: usage), keyCode)
        }
    }

    func testRejectsF19AndF20ThatAU05DoesNotOutput() {
        for (keyCode, name) in [(UInt16(80), "F19"), (UInt16(90), "F20")] {
            XCTAssertThrowsError(
                try MacKeyCodeShortcutMapper.shortcut(for: [keyCode], fallbackName: nil)
            ) { error in
                XCTAssertEqual(
                    error as? MacKeyCodeShortcutError,
                    .deviceFunctionKeyUnsupported(name)
                )
                XCTAssertEqual(
                    error.localizedDescription,
                    "這台 AU05 無法輸出 \(name)。請選另一個按鍵。"
                )
            }
        }
    }

    func testAllowsFourKeysAndRejectsFive() throws {
        let fourKeyShortcut = try MacKeyCodeShortcutMapper.shortcut(
            for: [55, 56, 58, 0],
            fallbackName: "A"
        )

        XCTAssertEqual(fourKeyShortcut.entries.count, 4)
        XCTAssertEqual(fourKeyShortcut.displayName, "左 Command ＋ 左 Shift ＋ 左 Option ＋ A")

        XCTAssertThrowsError(
            try MacKeyCodeShortcutMapper.shortcut(
                for: [55, 56, 58, 59, 0],
                fallbackName: "A"
            )
        ) { error in
            XCTAssertEqual(error as? MacKeyCodeShortcutError, .tooManyKeys)
        }
    }
}
