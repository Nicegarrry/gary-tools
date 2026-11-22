import XCTest
@testable import GaryCore

final class NativeAppSwitchesTests: XCTestCase {
    private func entry(_ id: String, allowed: Bool = true, helper: String? = nil) -> [Any] {
        [["bundle": ["_0": id]], ["isAllowed": allowed,
            "menuItemLocations": [["bundle": ["_0": helper ?? id]]],
            "location": ["path": "/Apps/Example.app"], "unknownFutureField": ["preserve": 42]]]
    }
    private func allowed(_ switches: NativeAppSwitches, index: Int = 1) -> Bool? {
        (switches.entries[index] as? [String: Any])?["isAllowed"] as? Bool
    }

    func testHideThenRevealRestoresOnlyOurSwitches() throws {
        let source = entry("example.app")
        var switches = try NativeAppSwitches(entries: source)
        var journal: [String: Bool] = [:]
        switches.apply(allowing: [], ownID: "local.nicegary.GaryTools", originals: &journal)
        XCTAssertEqual(allowed(switches), false)
        XCTAssertEqual(journal, ["example.app": true])
        switches = try NativeAppSwitches(entries: switches.entries)
        switches.apply(allowing: nil, ownID: "local.nicegary.GaryTools", originals: &journal)
        XCTAssertEqual(allowed(switches), true)
        XCTAssertTrue(journal.isEmpty)
        XCTAssertTrue(NSArray(array: source).isEqual(to: switches.entries))
    }

    func testAppleItemsOwnBundleAndLiveActivityRecordsAreUntouched() throws {
        let live: [Any] = [["liveActivity": ["_0": "activity.example"]], ["isAllowed": true, "payload": "keep"]]
        let original = entry("com.apple.controlcenter") + entry("local.nicegary.GaryTools") + live
        var switches = try NativeAppSwitches(entries: original)
        var journal: [String: Bool] = [:]
        switches.apply(allowing: [], ownID: "local.nicegary.GaryTools", originals: &journal)
        XCTAssertTrue(NSArray(array: original).isEqual(to: switches.entries))
        XCTAssertTrue(journal.isEmpty)
    }

    func testAlreadyDisabledAppsAreNotEnabledOnReveal() throws {
        var switches = try NativeAppSwitches(entries: entry("example.disabled", allowed: false))
        var journal: [String: Bool] = [:]
        switches.apply(allowing: [], ownID: "self", originals: &journal)
        switches = try NativeAppSwitches(entries: switches.entries)
        switches.apply(allowing: nil, ownID: "self", originals: &journal)
        XCTAssertEqual(allowed(switches), false)
        XCTAssertTrue(journal.isEmpty)
    }

    func testPinningHelperRestoresItsGroupDuringReplacement() throws {
        var switches = try NativeAppSwitches(entries: entry("example.parent", helper: "example.helper"))
        var journal: [String: Bool] = [:]
        switches.apply(allowing: [], ownID: "self", originals: &journal)
        switches = try NativeAppSwitches(entries: switches.entries)
        switches.apply(allowing: ["example.helper"], ownID: "self", originals: &journal)
        XCTAssertEqual(allowed(switches), true)
        XCTAssertTrue(journal.isEmpty)
    }

    func testCrashRecoveryFromDurableOriginals() throws {
        var switches = try NativeAppSwitches(entries: entry("example.crashed", allowed: false))
        var journal = ["example.crashed": true]
        switches.apply(allowing: nil, ownID: "self", originals: &journal)
        XCTAssertEqual(allowed(switches), true)
        XCTAssertTrue(journal.isEmpty)
    }

    func testUnknownFieldsAndNonBooleanFlagsSurvive() throws {
        let odd: [Any] = [["bundle": ["_0": "example.unknown"]], ["isAllowed": 17, "unknown": "keep"]]
        var switches = try NativeAppSwitches(entries: entry("example.app") + odd)
        var journal: [String: Bool] = [:]
        switches.apply(allowing: [], ownID: "self", originals: &journal)
        let changed = switches.entries[1] as! [String: Any]
        XCTAssertEqual((changed["unknownFutureField"] as? [String: Int])?["preserve"], 42)
        XCTAssertTrue(NSDictionary(dictionary: switches.entries[3] as! [String: Any]).isEqual(to: odd[1] as! [String: Any]))
    }

    func testRejectsDuplicateOrTruncatedRegistrationList() throws {
        XCTAssertThrowsError(try NativeAppSwitches(entries: entry("duplicate") + entry("duplicate")))
        XCTAssertThrowsError(try NativeAppSwitches(entries: [["bundle": ["_0": "truncated"]]]))
    }
}
