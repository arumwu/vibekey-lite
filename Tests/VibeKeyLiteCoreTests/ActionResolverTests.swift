import XCTest
@testable import VibeKeyLiteCore

final class ActionResolverTests: XCTestCase {
    func testResolvesNavigationKeys() {
        XCTAssertEqual(ActionResolver.resolve(.space), .keyStroke(keyCode: 49, modifiers: []))
        XCTAssertEqual(ActionResolver.resolve(.leftArrow), .keyStroke(keyCode: 123, modifiers: []))
        XCTAssertEqual(ActionResolver.resolve(.rightArrow), .keyStroke(keyCode: 124, modifiers: []))
        XCTAssertEqual(ActionResolver.resolve(.downArrow), .keyStroke(keyCode: 125, modifiers: []))
        XCTAssertEqual(ActionResolver.resolve(.upArrow), .keyStroke(keyCode: 126, modifiers: []))
        XCTAssertEqual(ActionResolver.resolve(.returnKey), .keyStroke(keyCode: 36, modifiers: []))
        XCTAssertEqual(ActionResolver.resolve(.escape), .keyStroke(keyCode: 53, modifiers: []))
        XCTAssertEqual(ActionResolver.resolve(.tab), .keyStroke(keyCode: 48, modifiers: []))
        XCTAssertEqual(ActionResolver.resolve(.deleteBackward), .keyStroke(keyCode: 51, modifiers: []))
        XCTAssertEqual(ActionResolver.resolve(.deleteForward), .keyStroke(keyCode: 117, modifiers: []))
        XCTAssertEqual(ActionResolver.resolve(.home), .keyStroke(keyCode: 115, modifiers: []))
        XCTAssertEqual(ActionResolver.resolve(.end), .keyStroke(keyCode: 119, modifiers: []))
        XCTAssertEqual(ActionResolver.resolve(.pageUp), .keyStroke(keyCode: 116, modifiers: []))
        XCTAssertEqual(ActionResolver.resolve(.pageDown), .keyStroke(keyCode: 121, modifiers: []))
    }

    func testResolvesCommandShortcutsAndOption() {
        XCTAssertEqual(
            ActionResolver.resolve(.selectAll),
            .keyStroke(keyCode: 0, modifiers: .command)
        )
        XCTAssertEqual(
            ActionResolver.resolve(.appSwitcher),
            .keyStroke(keyCode: 48, modifiers: .command)
        )
        XCTAssertEqual(
            ActionResolver.resolve(.optionKey),
            .keyStroke(keyCode: 58, modifiers: [])
        )
        XCTAssertEqual(ActionResolver.resolve(.copy), .keyStroke(keyCode: 8, modifiers: .command))
        XCTAssertEqual(ActionResolver.resolve(.paste), .keyStroke(keyCode: 9, modifiers: .command))
        XCTAssertEqual(ActionResolver.resolve(.cut), .keyStroke(keyCode: 7, modifiers: .command))
        XCTAssertEqual(ActionResolver.resolve(.undo), .keyStroke(keyCode: 6, modifiers: .command))
        XCTAssertEqual(
            ActionResolver.resolve(.redo),
            .keyStroke(keyCode: 6, modifiers: [.command, .shift])
        )
        XCTAssertEqual(ActionResolver.resolve(.save), .keyStroke(keyCode: 1, modifiers: .command))
        XCTAssertEqual(ActionResolver.resolve(.spotlight), .keyStroke(keyCode: 49, modifiers: .command))
        XCTAssertEqual(
            ActionResolver.resolve(.screenshot),
            .keyStroke(keyCode: 23, modifiers: [.command, .shift])
        )
        XCTAssertEqual(
            ActionResolver.resolve(.missionControl),
            .keyStroke(keyCode: 126, modifiers: .control)
        )
    }

    func testResolvesMediaAndControlActions() {
        XCTAssertEqual(ActionResolver.resolve(.volumeUp), .media(.volumeUp))
        XCTAssertEqual(ActionResolver.resolve(.volumeDown), .media(.volumeDown))
        XCTAssertEqual(ActionResolver.resolve(.mute), .media(.mute))
        XCTAssertEqual(ActionResolver.resolve(.brightnessUp), .media(.brightnessUp))
        XCTAssertEqual(ActionResolver.resolve(.brightnessDown), .media(.brightnessDown))
        XCTAssertEqual(ActionResolver.resolve(.previousTrack), .media(.previousTrack))
        XCTAssertEqual(ActionResolver.resolve(.nextTrack), .media(.nextTrack))
        XCTAssertEqual(ActionResolver.resolve(.playPause), .media(.playPause))
        XCTAssertEqual(ActionResolver.resolve(.switchProfile), .switchProfile)
        XCTAssertEqual(ActionResolver.resolve(.none), .none)
    }

    func testEveryActionBelongsToOneVisibleCategory() {
        let categorized = KeyActionCategory.allCases.flatMap { category in
            KeyAction.allCases.filter { $0.category == category }
        }

        XCTAssertEqual(categorized.count, KeyAction.allCases.count)
        XCTAssertEqual(Set(categorized.map(\.rawValue)).count, KeyAction.allCases.count)
    }
}
