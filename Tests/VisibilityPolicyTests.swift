import XCTest
@testable import GaryCore

final class VisibilityPolicyTests: XCTestCase {
    func testDefaultHidesThirdPartyAppsButKeepsSystemAndOwnBundle() {
        let apps = [AppIdentity(owner: "example.chat", bundleIDs: []),
                    AppIdentity(owner: "com.apple.controlcenter", bundleIDs: [])]
        XCTAssertEqual(VisibilityPolicy().allowlist(apps: apps, ownBundleID: "local.nicegary.GaryTools"),
                       ["local.nicegary.GaryTools", "com.apple.controlcenter"])
    }

    func testPinningIncludesHelpersAndUnpinningRemovesThem() {
        let apps = [AppIdentity(owner: "example.sync", bundleIDs: ["example.sync.helper"])]
        var policy = VisibilityPolicy()
        policy.setPinned("example.sync", true)
        XCTAssertEqual(policy.allowlist(apps: apps, ownBundleID: "local.nicegary.GaryTools"),
                       ["local.nicegary.GaryTools", "example.sync", "example.sync.helper"])
        policy.setPinned("example.sync", false)
        XCTAssertEqual(policy.allowlist(apps: apps, ownBundleID: "local.nicegary.GaryTools"), ["local.nicegary.GaryTools"])
    }

    func testHoverGateRequiresDwellAndResetsOnExit() {
        var gate = HoverRevealGate()
        // First transition to collapsed while pointer is outside menu bar
        XCTAssertFalse(gate.update(inside: false, collapsed: true, enabled: true, now: 0))
        XCTAssertFalse(gate.update(inside: true, collapsed: true, enabled: true, now: 0.1))
        XCTAssertFalse(gate.update(inside: true, collapsed: true, enabled: true, now: 0.3))
        XCTAssertTrue(gate.update(inside: true, collapsed: true, enabled: true, now: 0.5))
        XCTAssertFalse(gate.update(inside: true, collapsed: true, enabled: true, now: 1.0))
        XCTAssertFalse(gate.update(inside: false, collapsed: true, enabled: true, now: 1.1))
        XCTAssertFalse(gate.update(inside: true, collapsed: true, enabled: true, now: 1.2))
        XCTAssertTrue(gate.update(inside: true, collapsed: true, enabled: true, now: 1.6))
    }

    func testCollapseWhilePointerInMenuBarWaitsForExitBeforeHoverReveal() {
        var gate = HoverRevealGate()
        // Pointer clicks arrow while on menu bar -> transitions to collapsed with inside == true
        XCTAssertFalse(gate.update(inside: true, collapsed: true, enabled: true, now: 0))
        XCTAssertFalse(gate.update(inside: true, collapsed: true, enabled: true, now: 0.5))
        XCTAssertFalse(gate.update(inside: true, collapsed: true, enabled: true, now: 5.0))
        // Pointer moves down off menu bar
        XCTAssertFalse(gate.update(inside: false, collapsed: true, enabled: true, now: 5.1))
        // Pointer moves back up to menu bar -> now hover reveal works after 0.35s dwell
        XCTAssertFalse(gate.update(inside: true, collapsed: true, enabled: true, now: 5.2))
        XCTAssertTrue(gate.update(inside: true, collapsed: true, enabled: true, now: 5.6))
    }

    func testRevealInvalidatesLateActivationCompletion() {
        var revision = ActivationRevision()
        let first = revision.next()
        let second = revision.next()
        XCTAssertFalse(revision.isCurrent(first))
        XCTAssertTrue(revision.isCurrent(second))
        revision.next()
        XCTAssertFalse(revision.isCurrent(second))
    }
}
