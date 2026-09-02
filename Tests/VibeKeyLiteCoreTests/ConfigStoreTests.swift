import Foundation
import XCTest
@testable import VibeKeyLiteCore

final class ConfigStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testLoadOrCreateWritesReadableDefaults() throws {
        let configURL = temporaryDirectory.appendingPathComponent("config.json")
        let store = ConfigStore(configURL: configURL)

        let configuration = try store.loadOrCreate()

        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
        XCTAssertEqual(configuration.activeProfile, .a)
        XCTAssertEqual(configuration[.a][.knobLeft], .downArrow)
        XCTAssertEqual(configuration[.a][.knobPress], .none)
        XCTAssertEqual(configuration[.b][.knobRight], .volumeUp)

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL))
        let dictionary = try XCTUnwrap(json as? [String: Any])
        XCTAssertNotNil(dictionary["profileA"] as? [String: Any])
        XCTAssertNotNil(dictionary["profileB"] as? [String: Any])
    }

    func testDefaultProfilesMatchAIAndSystemLayout() {
        let configuration = AppConfiguration.default

        XCTAssertEqual(configuration[.a][.knobLeft], .downArrow)
        XCTAssertEqual(configuration[.a][.knobRight], .upArrow)
        XCTAssertEqual(configuration[.a][.topButton], .optionKey)
        XCTAssertEqual(configuration[.a][.middleButton], .returnKey)
        XCTAssertEqual(configuration[.a][.bottomButton], .tab)

        XCTAssertEqual(configuration[.b][.knobLeft], .volumeDown)
        XCTAssertEqual(configuration[.b][.knobPress], .none)
        XCTAssertEqual(configuration[.b][.knobRight], .volumeUp)
        XCTAssertEqual(configuration[.b][.topButton], .playPause)
        XCTAssertEqual(configuration[.b][.middleButton], .mute)
        XCTAssertEqual(configuration[.b][.bottomButton], .appSwitcher)
        XCTAssertEqual(ProfileID.a.displayName, "AI")
        XCTAssertEqual(ProfileID.b.displayName, "系統")
    }

    func testRoundTripsCustomizedProfiles() throws {
        let configURL = temporaryDirectory.appendingPathComponent("nested/config.json")
        let store = ConfigStore(configURL: configURL)
        var expected = AppConfiguration.default
        expected.activeProfile = .b
        var profileB = expected[.b]
        profileB[.middleButton] = .selectAll
        expected[.b] = profileB

        try store.save(expected)
        let actual = try store.loadOrCreate()

        XCTAssertEqual(actual, expected)
    }

    func testMissingMappingDecodesAsNone() throws {
        let json = """
        {
          "activeProfile": "a",
          "profileA": { "knobLeft": "leftArrow" },
          "profileB": {}
        }
        """
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: Data(json.utf8))

        XCTAssertEqual(decoded[.a][.knobLeft], .leftArrow)
        XCTAssertEqual(decoded[.a][.knobRight], .none)
        XCTAssertEqual(decoded[.b][.topButton], .none)
    }

    func testInvalidJSONIsNotOverwritten() throws {
        let configURL = temporaryDirectory.appendingPathComponent("config.json")
        let invalidData = Data("not-json".utf8)
        try invalidData.write(to: configURL)
        let store = ConfigStore(configURL: configURL)

        XCTAssertThrowsError(try store.loadOrCreate())
        XCTAssertEqual(try Data(contentsOf: configURL), invalidData)
    }
}
