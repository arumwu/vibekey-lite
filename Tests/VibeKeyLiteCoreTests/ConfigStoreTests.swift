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
        XCTAssertNil(configuration.offlineProfile)
        XCTAssertEqual(configuration[.a][.knobLeft], .preset(.downArrow))
        XCTAssertEqual(configuration[.a][.knobPress], .preset(.selectAll))
        XCTAssertEqual(configuration[.a][.knobDoublePress], .preset(.switchProfile))
        XCTAssertEqual(configuration[.b][.knobRight], .preset(.volumeUp))

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL))
        let dictionary = try XCTUnwrap(json as? [String: Any])
        XCTAssertNotNil(dictionary["profileA"] as? [String: Any])
        XCTAssertNotNil(dictionary["profileB"] as? [String: Any])
    }

    func testDefaultProfilesMatchAIAndSystemLayout() {
        let configuration = AppConfiguration.default

        XCTAssertEqual(configuration[.a][.knobLeft], .preset(.downArrow))
        XCTAssertEqual(configuration[.a][.knobPress], .preset(.selectAll))
        XCTAssertEqual(configuration[.a][.knobDoublePress], .preset(.switchProfile))
        XCTAssertEqual(configuration[.a][.knobRight], .preset(.upArrow))
        XCTAssertEqual(configuration[.a][.topButton], .preset(.optionKey))
        XCTAssertEqual(configuration[.a][.middleButton], .preset(.returnKey))
        XCTAssertEqual(configuration[.a][.bottomButton], .preset(.tab))
        XCTAssertTrue(configuration.needsHardwareSync)
        XCTAssertNil(configuration.offlineProfile)

        XCTAssertEqual(configuration[.b][.knobLeft], .preset(.volumeDown))
        XCTAssertEqual(configuration[.b][.knobPress], .preset(.appSwitcher))
        XCTAssertEqual(configuration[.b][.knobDoublePress], .preset(.switchProfile))
        XCTAssertEqual(configuration[.b][.knobRight], .preset(.volumeUp))
        XCTAssertEqual(configuration[.b][.topButton], .preset(.playPause))
        XCTAssertEqual(configuration[.b][.middleButton], .preset(.mute))
        XCTAssertEqual(configuration[.b][.bottomButton], .preset(.appSwitcher))
        XCTAssertEqual(ProfileID.a.displayName, "AI")
        XCTAssertEqual(ProfileID.b.displayName, "系統")
    }

    func testRestoresLegacyReservedKnobInBothProfiles() {
        var configuration = AppConfiguration.default
        configuration.profileA[.knobPress] = .preset(.switchProfile)
        configuration.profileB[.knobPress] = .preset(.switchProfile)
        configuration.offlineProfile = .b

        XCTAssertTrue(configuration.restoreLegacyReservedKnobMappings())
        XCTAssertEqual(configuration.profileA[.knobPress], .preset(.selectAll))
        XCTAssertEqual(configuration.profileB[.knobPress], .preset(.appSwitcher))
        XCTAssertNil(configuration.offlineProfile)
        XCTAssertFalse(configuration.restoreLegacyReservedKnobMappings())
    }

    func testRoundTripsCustomizedProfiles() throws {
        let configURL = temporaryDirectory.appendingPathComponent("nested/config.json")
        let store = ConfigStore(configURL: configURL)
        var expected = AppConfiguration.default
        expected.activeProfile = .b
        var profileA = expected[.a]
        var profileB = expected[.b]
        profileA[.topButton] = .preset(.f1)
        profileB[.middleButton] = .preset(.f12)
        expected[.a] = profileA
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

        XCTAssertEqual(decoded[.a][.knobLeft], .preset(.leftArrow))
        XCTAssertEqual(decoded[.a][.knobRight], .preset(.none))
        XCTAssertEqual(decoded[.a][.knobDoublePress], .preset(.switchProfile))
        XCTAssertEqual(decoded[.b][.topButton], .preset(.none))
        XCTAssertTrue(decoded.needsHardwareSync)
    }

    func testCompletedNativeProfileSyncRoundTrips() throws {
        let configURL = temporaryDirectory.appendingPathComponent("config.json")
        let store = ConfigStore(configURL: configURL)
        var expected = AppConfiguration.default
        expected.needsHardwareSync = false
        expected.offlineProfile = .a

        try store.save(expected)

        XCTAssertFalse(try store.loadOrCreate().needsHardwareSync)
        XCTAssertEqual(try store.loadOrCreate().offlineProfile, .a)
    }

    func testMissingOfflineProfileForcesHardwareSync() throws {
        let json = """
        {
          "activeProfile": "b",
          "profileA": {},
          "profileB": {},
          "needsHardwareSync": false
        }
        """

        let decoded = try JSONDecoder().decode(
            AppConfiguration.self,
            from: Data(json.utf8)
        )

        XCTAssertNil(decoded.offlineProfile)
        XCTAssertTrue(decoded.needsHardwareSync)
    }

    func testRoundTripsRecordedNativeShortcut() throws {
        let shortcut = try NativeShortcut(
            entries: [.init(pageAndSign: 0x03, value: 0x04)],
            displayName: "左 Option"
        )
        var expected = AppConfiguration.default
        var profileA = expected[.a]
        profileA[.topButton] = .shortcut(shortcut)
        expected[.a] = profileA

        let encoded = try JSONEncoder().encode(expected)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: encoded)

        XCTAssertEqual(decoded, expected)
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
