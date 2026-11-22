import XCTest
@testable import GaryTools

@MainActor
final class ApplicationRegistrationTests: XCTestCase {
    private func fixture() throws -> (URL, String) {
        let id = "local.garytools.test." + UUID().uuidString.lowercased()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(id + ".app")
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id,
            "CFBundleName": "Fixture", "CFBundlePackageType": "APPL"], format: .xml, options: 0)
        try plist.write(to: url.appendingPathComponent("Contents/Info.plist"))
        return (url, id)
    }

    func testRegistersActualLocalBundlePathBeforeCaching() async throws {
        let (url, id) = try fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        var calls = 0
        var resolved: URL?
        let registration = ApplicationRegistration(registerURL: { actual in
            calls += 1
            resolved = actual
            return 0
        }, resolveURL: { _ in resolved })
        XCTAssertTrue(registration.register(url, bundleID: id))
        XCTAssertTrue(registration.register(url, bundleID: id))
        XCTAssertEqual(calls, 1)
    }

    func testRejectsIdentityMismatchWithoutRegisteringOtherApp() async throws {
        let (url, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let registration = ApplicationRegistration(registerURL: { _ in
            XCTFail("Mismatched bundle must not be registered")
            return 0
        }, resolveURL: { _ in nil })
        XCTAssertFalse(registration.register(url, bundleID: "not.the.actual.id"))
    }
}
