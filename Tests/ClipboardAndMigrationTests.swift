import AppKit
import XCTest
@testable import GaryCore

@MainActor
final class ClipboardAndMigrationTests: XCTestCase {
    private final class SyntheticClipboard: ClipboardSource {
        var changeCount = 0
        var types = Set<String>()
        var payload: ClipPayload?
        var changeDuringRead = false
        func read(limit: Int) -> ClipPayload? {
            if changeDuringRead { changeCount += 1 }
            guard let payload, payload.byteCount <= limit else { return nil }
            return payload
        }
        func set(_ text: String, types: Set<String> = ["public.utf8-plain-text"]) {
            payload = .text(text); self.types = types; changeCount += 1
        }
    }

    func testPersistenceDeduplicationPinboardsStackAndRetention() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("garytools-clip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LibraryStore(root: root)
        var prefs = store.preferences; prefs.retentionDays = 0
        store.updatePreferences(prefs)
        let now = Date()

        let first = try XCTUnwrap(store.add(.text("Hello local clipboard"), sourceName: "Notes", sourceBundle: "com.apple.Notes", now: now))
        let second = try XCTUnwrap(store.add(.text("https://example.invalid/guide"), sourceName: "Safari", sourceBundle: "com.apple.Safari", now: now.addingTimeInterval(1)))
        XCTAssertEqual(store.clips.count, 2)
        XCTAssertEqual(store.clips.first?.kind, .link)

        let same = store.add(.text("Hello local clipboard"), sourceName: "Editor", sourceBundle: "test.editor", now: now.addingTimeInterval(2))
        XCTAssertEqual(same, first)
        XCTAssertEqual(store.clips.count, 2)

        let board = store.boards[0].id
        store.togglePin(first, board: board)
        XCTAssertEqual(store.filtered(query: "hello editor", board: board, kind: .text, source: "test.editor", days: 0).count, 1)

        let restored = try LibraryStore(root: root)
        XCTAssertEqual(restored.clips.count, 2)
        XCTAssertEqual(try restored.payload(for: first).plainText, "Hello local clipboard")

        store.enqueue(first); store.enqueue(second); store.enqueue(first)
        XCTAssertEqual(store.stack, [first, second])
        store.clearHistory()
        XCTAssertEqual(store.clips.map(\.id), [first])
        XCTAssertEqual(store.stack, [first])

        let edited = try XCTUnwrap(store.editText(first, text: "Revised snippet"))
        XCTAssertEqual(store.stack, [edited])
        XCTAssertEqual(try store.payload(for: edited).plainText, "Revised snippet")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.payloadURL(first).path))

        let attrs = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("library.json").path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testPrivacyRulesAndMonitor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("garytools-mon-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(root: root)
        let synthetic = SyntheticClipboard()
        let monitor = ClipboardMonitor(store: store, clipboard: synthetic)

        monitor.poll()
        XCTAssertTrue(store.clips.isEmpty)

        synthetic.set("Normal clip"); monitor.poll()
        XCTAssertEqual(store.clips.count, 1)

        store.paused = true; synthetic.set("While paused"); monitor.poll()
        store.paused = false; monitor.poll()
        XCTAssertEqual(store.clips.count, 1)

        synthetic.set("Password", types: ["org.nspasteboard.ConcealedType"]); monitor.poll()
        XCTAssertEqual(store.clips.count, 1)

        synthetic.set("Own restore", types: [CapturePolicy.ownMarker]); monitor.poll()
        XCTAssertEqual(store.clips.count, 1)

        synthetic.set("Racing"); synthetic.changeDuringRead = true; monitor.poll()
        XCTAssertEqual(store.clips.count, 1)
    }

    func testDeliveryQueueSerializesOperations() {
        let queue = DeliveryQueue()
        var events: [String] = []
        var finishA: (() -> Void)?
        queue.enqueue { done in events.append("A"); finishA = done }
        queue.enqueue { done in events.append("B"); done() }
        XCTAssertEqual(events, ["A"])
        finishA?()
        XCTAssertEqual(events, ["A", "B"])
    }

    func testDataMigrationCopiesLegacyPasteLocalAndLidGuardSafely() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("garytools-mig-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let pasteSrc = base.appendingPathComponent("PasteLocal")
        let lidSrc = base.appendingPathComponent("LidGuard")
        let dest = base.appendingPathComponent("GaryTools")
        try FileManager.default.createDirectory(at: lidSrc, withIntermediateDirectories: true)

        // Seed synthetic Paste Local library
        let legacyStore = try LibraryStore(root: pasteSrc)
        _ = legacyStore.add(.text("Migrated clip"), sourceName: "Notes", sourceBundle: "com.apple.Notes")

        // Seed synthetic LidGuard settings
        try "ENABLED=yes\nAUTO_PULL_REPOS=yes\n".write(to: lidSrc.appendingPathComponent("settings.conf"), atomically: true, encoding: .utf8)

        let defaultsSuiteName = "local.garytools.test.defaults.\(UUID().uuidString)"
        let arrowSuiteName = "local.garytools.test.arrow.\(UUID().uuidString)"
        let targetDefaults = UserDefaults(suiteName: defaultsSuiteName)!
        let arrowDefaults = UserDefaults(suiteName: arrowSuiteName)!
        defer {
            targetDefaults.removePersistentDomain(forName: defaultsSuiteName)
            arrowDefaults.removePersistentDomain(forName: arrowSuiteName)
            let prefsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
            try? FileManager.default.removeItem(at: prefsDir.appendingPathComponent("\(defaultsSuiteName).plist"))
            try? FileManager.default.removeItem(at: prefsDir.appendingPathComponent("\(arrowSuiteName).plist"))
        }
        arrowDefaults.set(true, forKey: "expandOnHover")

        let migrated = DataMigration.migrateIfNeeded(
            appSupportRoot: dest,
            pasteLocalSource: pasteSrc,
            lidguardSources: [lidSrc],
            defaults: targetDefaults,
            arrowBarDefaults: arrowDefaults
        )
        XCTAssertEqual(migrated.count, 3)

        let reopened = try LibraryStore(root: dest.appendingPathComponent("Clipboard"))
        XCTAssertEqual(reopened.clips.first?.text, "Migrated clip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("settings.conf").path))
        XCTAssertEqual(targetDefaults.bool(forKey: "expandOnHover"), true)
    }
}
