import AppKit
import Combine
import GaryCore
import ServiceManagement
import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case sleepGuard = "Sleep Guard"
    case clipboard = "Clipboard"
    case menuBar = "Menu Bar"
    case repoSync = "Repo Sync"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .sleepGuard: return "cup.and.saucer"
        case .clipboard: return "doc.on.clipboard"
        case .menuBar: return "chevron.left.2"
        case .repoSync: return "arrow.triangle.2.circlepath"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return "Your local Mac toolkit, all in one place."
        case .sleepGuard: return "Keep the Mac awake while agents work, with built-in safety cut-offs."
        case .clipboard: return "Local clipboard history, pinboards, and paste stack."
        case .menuBar: return "Pin the icons you want and tuck the rest away cleanly."
        case .repoSync: return "Fast-forward Developer repos hourly and on session start."
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case sleepGuard = "Sleep Guard"
    case clipboard = "Clipboard"
    case menuBar = "Menu Bar"
    case permissions = "Permissions"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .sleepGuard: return "cup.and.saucer"
        case .clipboard: return "doc.on.clipboard"
        case .menuBar: return "chevron.left.2"
        case .permissions: return "checkmark.shield"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Startup, Dock, and menu bar hub preferences."
        case .sleepGuard: return "Polling intervals, safety thresholds, and lid behavior."
        case .clipboard: return "History retention, privacy exclusions, and shortcuts."
        case .menuBar: return "Hover reveal, recovery button, and icon organizer behavior."
        case .permissions: return "macOS access status for direct paste, menu bar, and sleep control."
        }
    }
}

@MainActor
final class BrowserState: ObservableObject {
    @Published var query = ""
    @Published var board: UUID?
    @Published var kind: ClipKind?
    @Published var source = ""
    @Published var days = 0
    @Published var selected: UUID?

    var hasFilters: Bool { kind != nil || !source.isEmpty || days != 0 }
    func results(_ store: LibraryStore) -> [Clip] {
        store.filtered(query: query, board: board, kind: kind, source: source, days: days)
    }
    func resetFilters() { kind = nil; source = ""; days = 0 }
}

@MainActor
final class AppCoordinator: ObservableObject {
    let lidGuard: LidGuardModel
    let clipboardStore: LibraryStore
    let clipboardState = BrowserState()
    let arrowBar: ArrowBarModel
    let migratedItems: [String]

    @Published var activeSection: MainSection = .overview
    @Published var loginEnabled: Bool = false
    @Published var loginNeedsApproval: Bool = false
    @Published var loginError: String?
    @Published var accessibilityGranted: Bool = AXIsProcessTrusted()

    // Actions wired by AppDelegate
    var openClipboardBrowser: () -> Void = {}
    var openSettings: (SettingsPane?) -> Void = { _ in }
    var pasteClip: (UUID, Bool) -> Void = { _, _ in }
    var copyClip: (UUID, Bool) -> Void = { _, _ in }
    var previewClip: (UUID) -> Void = { _ in }
    var editClip: (UUID?) -> Void = { _ in }
    var renameClip: (UUID) -> Void = { _ in }
    var deleteClip: (UUID) -> Void = { _ in }
    var newBoard: () -> Void = {}
    var renameBoard: (UUID) -> Void = { _ in }
    var deleteBoard: (UUID) -> Void = { _ in }
    var pasteStack: (Bool) -> Void = { _ in }
    var toggleClipboardPause: () -> Void = {}
    var eraseClipboardHistory: () -> Void = {}
    var reconfigureHotKeys: () -> Void = {}
    var requestAccessibility: () -> Void = {}

    private var tokens = Set<AnyCancellable>()

    init(clipboardStore: LibraryStore, migratedItems: [String]) {
        self.clipboardStore = clipboardStore
        self.migratedItems = migratedItems
        self.lidGuard = LidGuardModel()
        self.arrowBar = ArrowBarModel()

        lidGuard.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &tokens)
        clipboardStore.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &tokens)
        arrowBar.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &tokens)
        refreshSystemState()
    }

    func refreshAll() {
        lidGuard.refreshStatus()
        refreshSystemState()
    }

    func refreshSystemState() {
        accessibilityGranted = AXIsProcessTrusted()
        let status = SMAppService.mainApp.status
        loginEnabled = (status == .enabled)
        loginNeedsApproval = (status == .requiresApproval)
    }

    func setLoginEnabled(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            loginError = error.localizedDescription
        }
        refreshSystemState()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
    }
}
