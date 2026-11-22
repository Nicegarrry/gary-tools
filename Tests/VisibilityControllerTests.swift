import XCTest
@testable import GaryTools

private final class FakeHandle: VisibilityHandle {
    var invalidations = 0
    func invalidate() { invalidations += 1 }
}

@MainActor
final class VisibilityControllerTests: XCTestCase {
    private var handles: [FakeHandle] = []
    private var callbacks: [(Error?) -> Void] = []

    private func controller(timeout: UInt64 = 5_000_000_000) -> VisibilityController {
        VisibilityController(backend: RestrictionBackend(isAvailable: true) { [unowned self] _, callback in
            let handle = FakeHandle()
            self.handles.append(handle)
            self.callbacks.append(callback)
            return handle
        }, timeoutNanoseconds: timeout)
    }

    func testOnlyReportsCollapsedAfterActivationSucceeds() async {
        let controller = controller()
        controller.collapse(allowing: ["self"])
        XCTAssertFalse(controller.isCollapsed)
        XCTAssertTrue(controller.isWorking)
        callbacks[0](nil)
        XCTAssertTrue(controller.isCollapsed)
        XCTAssertFalse(controller.isWorking)
        controller.reveal()
        XCTAssertEqual(handles[0].invalidations, 1)
    }

    func testRevealCancelsPendingActivationAndLateSuccessCannotHideAgain() async {
        let controller = controller()
        controller.collapse(allowing: ["self"])
        controller.reveal()
        callbacks[0](nil)
        XCTAssertFalse(controller.isCollapsed)
        XCTAssertFalse(controller.wantsCollapsed)
        XCTAssertEqual(handles[0].invalidations, 1)
    }

    func testTimeoutRestoresAndLateCompletionIsIgnored() async throws {
        let controller = controller(timeout: 1_000_000)
        controller.collapse(allowing: ["self"])
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertFalse(controller.isWorking)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertEqual(handles[0].invalidations, 1)
        callbacks[0](nil)
        XCTAssertFalse(controller.isCollapsed)
    }

    func testUnavailableBackendLeavesIconsAlone() async {
        let controller = VisibilityController(backend: RestrictionBackend(isAvailable: false) { _, _ in
            XCTFail("Unavailable backend must not activate")
            return nil
        })
        controller.collapse(allowing: ["self"])
        XCTAssertFalse(controller.isCollapsed)
        XCTAssertNotNil(controller.errorMessage)
    }
}
