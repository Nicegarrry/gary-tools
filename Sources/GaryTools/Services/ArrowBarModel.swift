import AppKit
import ApplicationServices
import Combine
import CoreServices
import GaryCore
import MenuBarBridge

// MARK: - Catalog & Registration

struct CatalogApp: Identifiable {
    let id: String
    var name: String
    var path: String
    var isRunning: Bool
    var hasMenuBarItem: Bool
    var bundleIDs: Set<String>
    var icon: NSImage { NSWorkspace.shared.icon(forFile: path) }
}

private struct SavedApp: Codable {
    let id: String
    let name: String
    let path: String
}

@MainActor
final class AppCatalog: ObservableObject {
    @Published private(set) var apps: [CatalogApp] = []
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var scanning = false
    private var knownIconApps = Set<String>()
    private let ownID: String
    private let defaults: UserDefaults
    private var generation = 0

    init(ownID: String, defaults: UserDefaults = .standard) {
        self.ownID = ownID
        self.defaults = defaults
        if let data = defaults.data(forKey: "knownMenuBarApps"),
           let saved = try? JSONDecoder().decode([SavedApp].self, from: data) {
            apps = saved.map {
                CatalogApp(id: $0.id, name: $0.name, path: $0.path,
                           isRunning: false, hasMenuBarItem: true, bundleIDs: [$0.id])
            }
            knownIconApps = Set(saved.map(\.id))
        }
    }

    static func ownerBundle(for app: NSRunningApplication) -> Bundle? {
        guard let url = app.bundleURL else { return nil }
        let parts = url.pathComponents
        if let index = parts.firstIndex(where: { $0.hasSuffix(".app") }) {
            return Bundle(path: NSString.path(withComponents: Array(parts[...index])))
        }
        return Bundle(url: url)
    }

    static func identities() -> [AppIdentity] {
        var groups: [String: Set<String>] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier else { continue }
            let owner = ownerBundle(for: app)?.bundleIdentifier ?? id
            groups[owner, default: []].insert(id)
        }
        return groups.map { AppIdentity(owner: $0.key, bundleIDs: $0.value) }
    }

    func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
        guard !scanning else { return }
        scanning = true
        generation += 1
        let revision = generation
        let trusted = accessibilityGranted
        let running = NSWorkspace.shared.runningApplications
        var grouped: [String: CatalogApp] = [:]
        var processes: [(String, pid_t)] = []
        for app in running {
            guard let id = app.bundleIdentifier, let bundle = Self.ownerBundle(for: app),
                  bundle.bundleURL.pathExtension == "app" else { continue }
            let owner = bundle.bundleIdentifier ?? id
            guard owner != ownID, !owner.hasPrefix("com.apple.") else { continue }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? app.localizedName ?? owner
            if grouped[owner] == nil {
                grouped[owner] = CatalogApp(id: owner, name: name, path: bundle.bundlePath,
                                            isRunning: true, hasMenuBarItem: false, bundleIDs: [owner])
            }
            grouped[owner]?.bundleIDs.insert(id)
            processes.append((owner, app.processIdentifier))
        }
        let snapshot = grouped
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var detected = Set<String>()
            if trusted {
                for (owner, pid) in processes {
                    let element = AXUIElementCreateApplication(pid)
                    AXUIElementSetMessagingTimeout(element, 0.12)
                    var value: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &value) == .success,
                       let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                        let menu = unsafeBitCast(value, to: AXUIElement.self)
                        var count: CFIndex = 0
                        if AXUIElementGetAttributeValueCount(menu, kAXChildrenAttribute as CFString, &count) == .success,
                           count > 0 { detected.insert(owner) }
                    }
                }
            }
            DispatchQueue.main.async {
                guard let self, revision == self.generation else { return }
                self.knownIconApps.formUnion(detected)
                var merged = snapshot
                for old in self.apps where merged[old.id] == nil {
                    var offline = old
                    offline.isRunning = false
                    merged[old.id] = offline
                }
                for id in merged.keys { merged[id]?.hasMenuBarItem = self.knownIconApps.contains(id) }
                self.apps = merged.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                let known = self.apps.filter { self.knownIconApps.contains($0.id) }
                    .map { SavedApp(id: $0.id, name: $0.name, path: $0.path) }
                if let data = try? JSONEncoder().encode(known) { self.defaults.set(data, forKey: "knownMenuBarApps") }
                self.scanning = false
            }
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func remember(_ id: String) {
        knownIconApps.insert(id)
        if let index = apps.firstIndex(where: { $0.id == id }) { apps[index].hasMenuBarItem = true }
        let saved = apps.filter { knownIconApps.contains($0.id) }
            .map { SavedApp(id: $0.id, name: $0.name, path: $0.path) }
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: "knownMenuBarApps") }
    }

    func addApplication() {
        let panel = NSOpenPanel()
        panel.title = "Add an app to Menu Bar Organizer"
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier, id != ownID, !id.hasPrefix("com.apple.") else { return }
        knownIconApps.insert(id)
        if !apps.contains(where: { $0.id == id }) {
            apps.append(CatalogApp(id: id, name: (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent, path: url.path,
                isRunning: false, hasMenuBarItem: true, bundleIDs: [id]))
        }
        refresh()
    }
}

@MainActor
final class ApplicationRegistration {
    private var registered: [String: URL] = [:]
    private let registerURL: (URL) -> OSStatus
    private let resolveURL: (String) -> URL?

    init(registerURL: @escaping (URL) -> OSStatus = { LSRegisterURL($0 as CFURL, true) },
         resolveURL: @escaping (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) {
        self.registerURL = registerURL
        self.resolveURL = resolveURL
    }

    @discardableResult
    func register(_ url: URL, bundleID: String) -> Bool {
        let actual = url.resolvingSymlinksInPath().standardizedFileURL
        guard actual.pathExtension == "app", Bundle(url: actual)?.bundleIdentifier == bundleID else { return false }
        func resolvesHere() -> Bool {
            resolveURL(bundleID)?.resolvingSymlinksInPath().standardizedFileURL == actual
        }
        if registered[bundleID] == actual && resolvesHere() { return true }
        let status = registerURL(actual)
        let success = status == noErr && resolvesHere()
        if success { registered[bundleID] = actual }
        return success
    }

    func prepare(ownBundleID: String, pinnedIDs: Set<String>, catalog: [CatalogApp]) -> Set<String> {
        var paths = [String: URL]()
        paths[ownBundleID] = Bundle.main.bundleURL
        for app in catalog where pinnedIDs.contains(app.id) {
            paths[app.id] = URL(fileURLWithPath: app.path)
        }
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier else { continue }
            if let owner = AppCatalog.ownerBundle(for: app), let ownerID = owner.bundleIdentifier,
               pinnedIDs.contains(ownerID) {
                paths[ownerID] = owner.bundleURL
            }
            if pinnedIDs.contains(id), let url = app.bundleURL { paths[id] = url }
        }
        var failures = Set<String>()
        for (id, url) in paths where !register(url, bundleID: id) { failures.insert(id) }
        return failures
    }
}

// MARK: - Visibility Restriction Backend (MenuBarClientCore)

protocol VisibilityHandle: AnyObject { func invalidate() }

private final class AssessmentHandle: VisibilityHandle {
    private var restriction: GTAssessmentRestriction?
    init(_ restriction: GTAssessmentRestriction) { self.restriction = restriction }
    func invalidate() {
        restriction?.invalidate()
        restriction = nil
    }
    deinit { invalidate() }
}

struct RestrictionBackend {
    var isAvailable: Bool
    var activate: ([String], @escaping @MainActor @Sendable (Error?) -> Void) -> VisibilityHandle?
    @MainActor static var live: Self {
        Self(isAvailable: GTAssessmentRestriction.isAvailable()) { bundles, completion in
            let restriction = GTAssessmentRestriction()
            restriction.activate(
                withAllowedSystemItems: GTAssessmentRestriction.allSystemItems(),
                allowedBundleIdentifiers: bundles,
                completion: { error in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { completion(error) }
                    }
                }
            )
            return AssessmentHandle(restriction)
        }
    }
}

@MainActor
final class VisibilityController: ObservableObject {
    @Published private(set) var isCollapsed = false
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?
    let available: Bool
    private let backend: RestrictionBackend
    private let timeoutNanoseconds: UInt64
    private var active: VisibilityHandle?
    private var pending: VisibilityHandle?
    private var timeout: Task<Void, Never>?
    private var revision = ActivationRevision()
    private var appliedAllowlist: Set<String>?
    private var requestedAllowlist: Set<String>?
    private(set) var wantsCollapsed = false

    init(backend: RestrictionBackend? = nil, timeoutNanoseconds: UInt64 = 5_000_000_000) {
        self.backend = backend ?? .live
        self.available = self.backend.isAvailable
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func collapse(allowing bundles: Set<String>, refresh: Bool = false) {
        guard available else {
            errorMessage = "This version of macOS does not provide menu bar visibility control. All icons remain visible."
            return
        }
        guard !(wantsCollapsed && (isWorking ? requestedAllowlist : appliedAllowlist) == bundles && (!refresh || isWorking)) else { return }
        wantsCollapsed = true
        let request = revision.next()
        timeout?.cancel()
        pending?.invalidate()
        pending = nil
        requestedAllowlist = bundles
        isWorking = true
        errorMessage = nil
        pending = backend.activate(bundles.sorted()) { [weak self] error in
            guard let self, self.revision.isCurrent(request) else { return }
            self.timeout?.cancel()
            if let error { self.fail(error.localizedDescription); return }
            guard let replacement = self.pending else {
                self.fail("macOS did not return a menu bar controller.")
                return
            }
            self.active?.invalidate()
            self.active = replacement
            self.pending = nil
            self.appliedAllowlist = bundles
            self.isCollapsed = true
            self.isWorking = false
        }
        let delay = timeoutNanoseconds
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard let self, self.revision.isCurrent(request), self.isWorking else { return }
            self.fail("macOS did not respond. Icons have been restored; click the arrow to try again.")
        }
    }

    func reveal() {
        revision.next()
        timeout?.cancel()
        timeout = nil
        pending?.invalidate()
        active?.invalidate()
        pending = nil
        active = nil
        appliedAllowlist = nil
        requestedAllowlist = nil
        wantsCollapsed = false
        isCollapsed = false
        isWorking = false
        errorMessage = nil
    }

    private func fail(_ message: String) {
        reveal()
        errorMessage = message
    }
}

// MARK: - ArrowBar Module Model

@MainActor
final class ArrowBarModel: ObservableObject {
    static let bundleID = "local.nicegary.GaryTools"

    /// Apple system and Live Activity bundle IDs always kept in the allowlist.
    private static let appleSystemBundles: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.Spotlight",
        "com.apple.Siri",
        "com.apple.MediaRemoteUIService",
        "com.apple.ClockAngel",
        "com.apple.chrono.WidgetRenderer-Activities",
        "com.apple.InCallService",
        "com.apple.ScreenContinuity",
        "com.apple.screencaptureui",
        "com.apple.Sharing.AirDropUI",
        "com.apple.menuextra.TimeMachine",
        "com.apple.menuextra.vpn",
        "com.apple.weather.menu",
        "com.apple.musicrecognition.mac",
        "com.apple.printcenter"
    ]

    let catalog = AppCatalog(ownID: bundleID)
    let visibility = VisibilityController()
    let registration = ApplicationRegistration()

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "arrowBarEnabled")
            if !enabled { revealAll() }
        }
    }
    @Published var policy: VisibilityPolicy
    @Published var editing = false
    @Published var search = ""
    @Published var showAllRunningApps = false
    @Published var startCollapsed: Bool { didSet { UserDefaults.standard.set(startCollapsed, forKey: "startCollapsed") } }
    @Published var expandOnHover: Bool { didSet { UserDefaults.standard.set(expandOnHover, forKey: "expandOnHover") } }
    @Published var showRecoveryButton: Bool { didSet { UserDefaults.standard.set(showRecoveryButton, forKey: "showRecoveryButton") } }
    @Published var revealShortcutAvailable = false
    @Published private(set) var conflictingManagers: [String] = []

    private var observers: [NSObjectProtocol] = []
    private var tokens = Set<AnyCancellable>()
    private var refreshTimer: Timer?

    init() {
        enabled = UserDefaults.standard.object(forKey: "arrowBarEnabled") as? Bool ?? true
        var loadedPolicy = UserDefaults.standard.data(forKey: "policy")
            .flatMap { try? JSONDecoder().decode(VisibilityPolicy.self, from: $0) } ?? VisibilityPolicy()
        // Prune retired standalone bundle IDs that were consolidated into Gary Tools.
        let retired: Set<String> = ["local.pastelocal.app", "local.lidguard.menubar", "local.np.ArrowBar"]
        if !loadedPolicy.pinnedBundleIDs.isDisjoint(with: retired) {
            loadedPolicy.pinnedBundleIDs.subtract(retired)
            if let data = try? JSONEncoder().encode(loadedPolicy) {
                UserDefaults.standard.set(data, forKey: "policy")
            }
        }
        policy = loadedPolicy
        startCollapsed = UserDefaults.standard.object(forKey: "startCollapsed") as? Bool ?? false
        expandOnHover = UserDefaults.standard.object(forKey: "expandOnHover") as? Bool ?? true
        showRecoveryButton = UserDefaults.standard.object(forKey: "showRecoveryButton") as? Bool ?? true

        catalog.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &tokens)
        visibility.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &tokens)

        let center = NSWorkspace.shared.notificationCenter
        for event in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                      NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    var displayedApps: [CatalogApp] {
        catalog.apps.filter { app in
            (showAllRunningApps || !catalog.accessibilityGranted || app.hasMenuBarItem || policy.isPinned(app.id)) &&
            (search.isEmpty || app.name.localizedCaseInsensitiveContains(search) || app.id.localizedCaseInsensitiveContains(search))
        }
    }

    var pinnedCount: Int { policy.pinnedBundleIDs.count }

    func setPinned(_ id: String, _ pinned: Bool) {
        guard catalog.apps.contains(where: { $0.id == id }) else { return }
        catalog.remember(id)
        policy.setPinned(id, pinned)
        if let data = try? JSONEncoder().encode(policy) { UserDefaults.standard.set(data, forKey: "policy") }
        if visibility.wantsCollapsed && !editing { applyCollapsed() }
    }

    func toggle() {
        guard enabled else { return }
        if visibility.wantsCollapsed { revealAll() }
        else {
            if editing { editing = false }
            applyCollapsed()
        }
    }

    func beginEditing() {
        revealAll()
        editing = true
        catalog.refresh()
    }

    func finishEditing() {
        editing = false
        if enabled && visibility.available {
            applyCollapsed()
        }
    }

    func applyCollapsed(refresh: Bool = false) {
        guard enabled, conflictingManagers.isEmpty else { return }
        _ = registration.prepare(ownBundleID: Self.bundleID, pinnedIDs: policy.pinnedBundleIDs, catalog: catalog.apps)
        let known = catalog.apps.map { AppIdentity(owner: $0.id, bundleIDs: $0.bundleIDs) }
        let allowed = policy.allowlist(apps: AppCatalog.identities() + known, ownBundleID: Self.bundleID)
            .union(Self.appleSystemBundles)
        visibility.collapse(allowing: allowed, refresh: refresh)
    }

    func revealAll() {
        visibility.reveal()
    }

    func refresh() {
        let managerIDs: Set<String> = [
            "com.surteesstudios.Bartender",
            "com.jordanbaird.Ice",
            "com.stonerl.Thaw",
            "com.brentc22.Stash",
            "local.np.ArrowBar"
        ]
        conflictingManagers = NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier, managerIDs.contains(id) else { return nil }
            return app.localizedName ?? id
        }
        if !conflictingManagers.isEmpty { revealAll() }
        catalog.refresh()
        if enabled && visibility.wantsCollapsed && !editing { applyCollapsed(refresh: true) }
    }
}
