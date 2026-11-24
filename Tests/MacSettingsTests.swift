import XCTest
@testable import GaryCore

final class MacSettingsTests: XCTestCase {
    func testJournalKeepsTheFirstOriginal() {
        var journal = OriginalsJournal()
        let key = OriginalsJournal.preferenceKey(domain: MacDomains.screenCapture, key: "location")
        XCTAssertTrue(journal.recordIfNeeded(key, current: .absent))
        XCTAssertFalse(journal.recordIfNeeded(key, current: .value("string:/Users/nick/Screenshots")))
        XCTAssertEqual(journal.entries[key], .absent)
    }

    func testJournalRoundTripsThroughPlist() throws {
        var journal = OriginalsJournal()
        journal.recordIfNeeded("defaults|com.apple.finder|AppleShowAllFiles", current: .value("bool:0"))
        journal.recordIfNeeded("scheme|http", current: .value("/Applications/Safari.app"))
        journal.recordIfNeeded("defaults|com.apple.screencapture|type", current: .absent)
        let restored = try OriginalsJournal(plist: journal.plistData())
        XCTAssertEqual(restored, journal)
    }

    func testJournalSaveUsesPrivatePermissionsAndRemovesFileWhenEmpty() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gary-mac-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("originals.plist")
        var journal = OriginalsJournal()
        journal.recordIfNeeded("scheme|http", current: .value("/Applications/Safari.app"))
        try journal.save(to: url)
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o600)
        XCTAssertEqual(OriginalsJournal.load(from: url), journal)
        try OriginalsJournal().save(to: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testPreferenceCodingRoundTrips() {
        XCTAssertNil(PreferenceCoding.decode(PreferenceCoding.encode(nil)))
        XCTAssertEqual(PreferenceCoding.decode(PreferenceCoding.encode(true)) as? Bool, true)
        XCTAssertEqual(PreferenceCoding.decode(PreferenceCoding.encode(false)) as? Bool, false)
        XCTAssertEqual(PreferenceCoding.decode(PreferenceCoding.encode("~/Shots")) as? String, "~/Shots")
    }

    func testBoolValueReadsDefaultsSpellings() {
        XCTAssertTrue(MacSettingsCatalog.boolValue("YES", default: false))
        XCTAssertFalse(MacSettingsCatalog.boolValue("false", default: true))
        XCTAssertTrue(MacSettingsCatalog.boolValue(NSNumber(value: 1), default: false))
        XCTAssertTrue(MacSettingsCatalog.boolValue(nil, default: true))
        XCTAssertFalse(MacSettingsCatalog.boolValue("maybe", default: false))
    }

    func testScreenshotFormatReadsMacSpellings() {
        XCTAssertEqual(ScreenshotFormat(preference: nil), .png)
        XCTAssertEqual(ScreenshotFormat(preference: "JPEG"), .jpg)
        XCTAssertEqual(ScreenshotFormat(preference: "heic"), .heic)
        XCTAssertEqual(ScreenshotFormat(preference: "gif-not-supported"), .png)
    }

    func testScreenshotLocationExpandsAndShortensHome() {
        let home = URL(fileURLWithPath: "/Users/nick", isDirectory: true)
        XCTAssertEqual(ScreenshotLocation.resolve(nil, home: home).path, "/Users/nick/Desktop")
        XCTAssertEqual(ScreenshotLocation.resolve("~/Screenshots", home: home).path, "/Users/nick/Screenshots")
        XCTAssertEqual(ScreenshotLocation.resolve("/Volumes/Shots", home: home).path, "/Volumes/Shots")
        XCTAssertEqual(ScreenshotLocation.display(URL(fileURLWithPath: "/Users/nick/Screenshots"), home: home), "~/Screenshots")
        XCTAssertEqual(ScreenshotLocation.display(URL(fileURLWithPath: "/Users/nicky/x"), home: home), "/Users/nicky/x")
    }

    func testCatalogHasUniqueIDs() {
        let exts = FileTypeCatalog.allExtensions
        XCTAssertEqual(exts.count, Set(exts).count)
        XCTAssertTrue(exts.contains("md"))
        let toggles = MacSettingsCatalog.screenshotToggles + MacSettingsCatalog.finderToggles
        XCTAssertEqual(toggles.count, Set(toggles.map(\.id)).count)
        XCTAssertEqual(toggles.count, Set(toggles.map { "\($0.domain)|\($0.key)" }).count)
    }
}
