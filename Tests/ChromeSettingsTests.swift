import XCTest
@testable import GaryCore

final class ChromeSettingsTests: XCTestCase {
    private let prefs = #"{"browser":{"window_placement":{"left":10}},"download":{"prompt_for_download":false},"profile":{"name":"Nick"}}"#

    func testSettingTheFolderKeepsEveryOtherKey() throws {
        let updated = try ChromeSettings.settingDownloadDirectory("/Users/nick/Downloads/Chrome", in: Data(prefs.utf8))
        XCTAssertEqual(try ChromeSettings.downloadDirectory(preferences: updated), "/Users/nick/Downloads/Chrome")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: updated) as? [String: Any])
        XCTAssertEqual((root["download"] as? [String: Any])?["prompt_for_download"] as? Bool, false)
        XCTAssertEqual((root["profile"] as? [String: Any])?["name"] as? String, "Nick")
        XCTAssertNotNil((root["browser"] as? [String: Any])?["window_placement"])
    }

    func testClearingTheFolderReturnsToChromeDefault() throws {
        let set = try ChromeSettings.settingDownloadDirectory("/tmp/x", in: Data(prefs.utf8))
        let cleared = try ChromeSettings.settingDownloadDirectory(nil, in: set)
        XCTAssertNil(try ChromeSettings.downloadDirectory(preferences: cleared))
    }

    func testRejectsFilesThatAreNotAJSONObject() {
        XCTAssertThrowsError(try ChromeSettings.settingDownloadDirectory("/tmp", in: Data("[1,2]".utf8)))
        XCTAssertThrowsError(try ChromeSettings.downloadDirectory(preferences: Data("not json".utf8)))
    }

    func testProfileNamesComeFromLocalState() {
        let state = #"{"profile":{"info_cache":{"Default":{"name":"Personal"},"Profile 1":{"name":"Qubit"}}}}"#
        XCTAssertEqual(ChromeSettings.profileNames(localState: Data(state.utf8)), ["Default": "Personal", "Profile 1": "Qubit"])
        XCTAssertEqual(ChromeSettings.profileNames(localState: nil), [:])
    }

    func testProfilesListsDefaultFirstAndSkipsOtherFolders() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gary-chrome-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        for folder in ["Profile 2", "Default", "Crashpad", "Profile 10"] {
            let sub = dir.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            if folder != "Crashpad" { try Data("{}".utf8).write(to: sub.appendingPathComponent("Preferences")) }
        }
        XCTAssertEqual(ChromeSettings.profiles(in: dir).map(\.id), ["Default", "Profile 2", "Profile 10"])
    }

    func testTeamIdentifierParsing() {
        let out = "Executable=/x\nIdentifier=com.google.Chrome\nTeamIdentifier=EQHXZ8M8AV\n"
        XCTAssertEqual(ChromeSettings.teamIdentifier(fromCodesignOutput: out), ChromeSettings.googleTeamID)
        XCTAssertNil(ChromeSettings.teamIdentifier(fromCodesignOutput: "TeamIdentifier=not set"))
        XCTAssertNil(ChromeSettings.teamIdentifier(fromCodesignOutput: "Identifier=x"))
    }

    func testDeveloperFolderDefaultsToTildeDeveloper() {
        let home = URL(fileURLWithPath: "/Users/nick", isDirectory: true)
        XCTAssertEqual(DeveloperFolder.resolve("", home: home).path, "/Users/nick/Developer")
        XCTAssertEqual(DeveloperFolder.resolve("~/code", home: home).path, "/Users/nick/code")
    }
}
