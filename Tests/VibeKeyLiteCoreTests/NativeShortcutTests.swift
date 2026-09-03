import XCTest
@testable import VibeKeyLiteCore

final class NativeShortcutTests: XCTestCase {
    func testRejectsUnknownPagesAndCombinedModifierBits() {
        XCTAssertThrowsError(
            try NativeShortcut(
                entries: [NativeShortcutEntry(pageAndSign: 0x7F, value: 1)],
                displayName: "unsafe"
            )
        )
        XCTAssertThrowsError(
            try NativeShortcut(
                entries: [NativeShortcutEntry(pageAndSign: 0x03, value: 0x03)],
                displayName: "combined modifier"
            )
        )
        XCTAssertThrowsError(
            try NativeShortcut(
                entries: [NativeShortcutEntry(pageAndSign: 0x02, value: 0)],
                displayName: "reserved key"
            )
        )
    }

    private let keyboardPage: UInt8 = 0x02
    private let modifierPage: UInt8 = 0x03

    func testShortcutRoundTripsThroughCodable() throws {
        let shortcut = try NativeShortcut(
            entries: [
                .init(pageAndSign: modifierPage, value: 0x08),
                .init(pageAndSign: keyboardPage, value: 0x04)
            ],
            displayName: "⌘A（全選）"
        )

        let encoded = try JSONEncoder().encode(shortcut)
        let decoded = try JSONDecoder().decode(NativeShortcut.self, from: encoded)

        XCTAssertEqual(decoded, shortcut)
        requireSendable(shortcut)
        requireSendable(shortcut.entries[0])
    }

    func testAllowsFourEntriesAndRejectsFive() throws {
        let fourEntries = (0..<4).map {
            NativeShortcutEntry(pageAndSign: keyboardPage, value: UInt8(0x04 + $0))
        }
        XCTAssertNoThrow(try NativeShortcut(entries: fourEntries, displayName: "四鍵"))

        let fiveEntries = (0..<5).map {
            NativeShortcutEntry(pageAndSign: keyboardPage, value: UInt8(0x04 + $0))
        }
        XCTAssertThrowsError(
            try NativeShortcut(entries: fiveEntries, displayName: "五鍵")
        ) { error in
            XCTAssertEqual(
                error as? NativeShortcutError,
                .tooManyEntries(maximum: 4, actual: 5)
            )
        }
    }

    func testDecoderAlsoRejectsMoreThanFourEntries() {
        let json = Data(
            """
            {
              "displayName": "invalid",
              "entries": [
                {"pageAndSign": 2, "value": 4},
                {"pageAndSign": 2, "value": 5},
                {"pageAndSign": 2, "value": 6},
                {"pageAndSign": 2, "value": 7},
                {"pageAndSign": 2, "value": 8}
              ]
            }
            """.utf8
        )

        XCTAssertThrowsError(try JSONDecoder().decode(NativeShortcut.self, from: json)) {
            XCTAssertEqual(
                $0 as? NativeShortcutError,
                .tooManyEntries(maximum: 4, actual: 5)
            )
        }
    }

    func testResolvesBasicAndNavigationKeysToUSBHIDUsages() throws {
        let expected: [(KeyAction, UInt8)] = [
            (.space, 0x2C),
            (.returnKey, 0x28),
            (.escape, 0x29),
            (.tab, 0x2B),
            (.leftArrow, 0x50),
            (.rightArrow, 0x4F),
            (.upArrow, 0x52),
            (.downArrow, 0x51),
            (.deleteBackward, 0x2A),
            (.deleteForward, 0x4C),
            (.home, 0x4A),
            (.end, 0x4D),
            (.pageUp, 0x4B),
            (.pageDown, 0x4E)
        ]

        for (action, usage) in expected {
            let shortcut = try resolvedShortcut(action)
            XCTAssertEqual(
                shortcut.entries,
                [.init(pageAndSign: keyboardPage, value: usage)],
                "Unexpected native mapping for \(action)"
            )
            XCTAssertEqual(shortcut.displayName, action.displayName)
        }
    }

    func testResolvesF1ThroughF12ToUSBHIDUsages() throws {
        let actions: [KeyAction] = [
            .f1, .f2, .f3, .f4, .f5, .f6,
            .f7, .f8, .f9, .f10, .f11, .f12
        ]

        for (offset, action) in actions.enumerated() {
            XCTAssertEqual(
                try resolvedShortcut(action).entries,
                [key(UInt8(0x3A + offset))],
                "\(action.displayName) mapping"
            )
        }
    }

    func testF1ThroughF12StayVisibleInTheFunctionKeyMenu() {
        let actions: [KeyAction] = [
            .f1, .f2, .f3, .f4, .f5, .f6,
            .f7, .f8, .f9, .f10, .f11, .f12
        ]

        XCTAssertEqual(
            KeyAction.allCases.filter { $0.category == .functionKeys },
            actions
        )
        XCTAssertEqual(actions.map(\.displayName), (1...12).map { "F\($0)" })
        XCTAssertEqual(KeyActionCategory.functionKeys.rawValue, "F1–F12")
    }

    func testLeftOptionUsesVendorModifierPageAndBit() throws {
        XCTAssertEqual(
            try resolvedShortcut(.optionKey).entries,
            [.init(pageAndSign: 0x03, value: 0x04)]
        )
    }

    func testRightOptionUsesVendorModifierPageAndBit() throws {
        XCTAssertEqual(
            try resolvedShortcut(.rightOptionKey).entries,
            [.init(pageAndSign: 0x03, value: 0x40)]
        )
    }

    func testResolvesEditingAndSystemChords() throws {
        let command = NativeShortcutEntry(pageAndSign: modifierPage, value: 0x08)
        let shift = NativeShortcutEntry(pageAndSign: modifierPage, value: 0x02)
        let control = NativeShortcutEntry(pageAndSign: modifierPage, value: 0x01)

        let expected: [(KeyAction, [NativeShortcutEntry])] = [
            (.selectAll, [command, key(0x04)]),
            (.copy, [command, key(0x06)]),
            (.paste, [command, key(0x19)]),
            (.cut, [command, key(0x1B)]),
            (.undo, [command, key(0x1D)]),
            (.redo, [command, shift, key(0x1D)]),
            (.save, [command, key(0x16)]),
            (.appSwitcher, [command, key(0x2B)]),
            (.spotlight, [command, key(0x2C)]),
            (.screenshot, [command, shift, key(0x22)]),
            (.missionControl, [control, key(0x52)])
        ]

        for (action, entries) in expected {
            XCTAssertEqual(
                try resolvedShortcut(action).entries,
                entries,
                "Unexpected native chord for \(action)"
            )
        }
    }

    func testResolvesKnownMediaActionsToFixedFunctionCodes() {
        XCTAssertEqual(PresetNativeShortcutResolver.resolve(.playPause), .fixedFunction(0x07))
        XCTAssertEqual(PresetNativeShortcutResolver.resolve(.nextTrack), .fixedFunction(0x08))
        XCTAssertEqual(PresetNativeShortcutResolver.resolve(.previousTrack), .fixedFunction(0x09))
        XCTAssertEqual(PresetNativeShortcutResolver.resolve(.mute), .fixedFunction(0x0B))
        XCTAssertEqual(PresetNativeShortcutResolver.resolve(.volumeUp), .fixedFunction(0x0C))
        XCTAssertEqual(PresetNativeShortcutResolver.resolve(.volumeDown), .fixedFunction(0x0D))
    }

    func testNoneAndUnsupportedActionsRemainDistinct() {
        XCTAssertEqual(PresetNativeShortcutResolver.resolve(.none), .none)
        XCTAssertEqual(PresetNativeShortcutResolver.resolve(.switchProfile), .unsupported)
        XCTAssertEqual(PresetNativeShortcutResolver.resolve(.brightnessUp), .unsupported)
        XCTAssertEqual(PresetNativeShortcutResolver.resolve(.brightnessDown), .unsupported)
    }

    private func key(_ usage: UInt8) -> NativeShortcutEntry {
        NativeShortcutEntry(pageAndSign: keyboardPage, value: usage)
    }

    private func resolvedShortcut(
        _ action: KeyAction,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> NativeShortcut {
        guard case let .shortcut(shortcut) = PresetNativeShortcutResolver.resolve(action) else {
            XCTFail("Expected a native shortcut for \(action)", file: file, line: line)
            throw TestError.notAShortcut
        }
        return shortcut
    }

    private func requireSendable<T: Sendable>(_ value: T) {}

    private enum TestError: Error {
        case notAShortcut
    }
}
