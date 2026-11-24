import AppKit
import GaryCore
import UniformTypeIdentifiers

/// An app that can open something, as shown in a picker.
struct AppChoice: Identifiable, Hashable {
    let url: URL
    var id: String { url.path }
    var name: String {
        (Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

/// One extension's current default app and the apps that can open it.
struct FileTypeDefault: Identifiable {
    let entry: FileTypeEntry
    let type: UTType?
    var current: AppChoice?
    var candidates: [AppChoice]
    var id: String { entry.ext }
}

/// Reads and changes the hard-to-find macOS settings shown in the Mac Settings section.
/// Every change records the original value first, so "Undo All" puts the Mac back exactly as it was.
@MainActor
final class MacSettingsModel: ObservableObject {
    @Published private(set) var screenshotFolder: URL = ScreenshotLocation.resolve(nil)
    @Published private(set) var screenshotFormat: ScreenshotFormat = .png
    @Published private(set) var toggleValues: [String: Bool] = [:]
    @Published private(set) var browsers: [AppChoice] = []
    @Published private(set) var currentBrowser: AppChoice?
    @Published private(set) var fileTypes: [FileTypeDefault] = []
    @Published private(set) var finderNeedsRelaunch = false
    @Published private(set) var journal: OriginalsJournal
    @Published var message: String?

    private let workspace = NSWorkspace.shared

    init() {
        journal = OriginalsJournal.load()
    }

    var hasChanges: Bool { !journal.isEmpty }

    func refresh() {
        screenshotFolder = ScreenshotLocation.resolve(read(MacDomains.screenCapture, MacSettingsCatalog.screenshotLocationKey))
        screenshotFormat = ScreenshotFormat(preference: read(MacDomains.screenCapture, MacSettingsCatalog.screenshotTypeKey))
        var values: [String: Bool] = [:]
        for toggle in MacSettingsCatalog.screenshotToggles + MacSettingsCatalog.finderToggles {
            values[toggle.id] = MacSettingsCatalog.boolValue(read(toggle.domain, toggle.key), default: toggle.appleDefault)
        }
        toggleValues = values
        refreshBrowsers()
        refreshFileTypes()
    }

    // MARK: Screenshots

    func chooseScreenshotFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = screenshotFolder
        panel.prompt = "Save Screenshots Here"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setScreenshotFolder(url)
    }

    func setScreenshotFolder(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            message = "That folder doesn't exist, so screenshots still go to \(ScreenshotLocation.display(screenshotFolder))."
            return
        }
        write(MacDomains.screenCapture, MacSettingsCatalog.screenshotLocationKey, url.standardizedFileURL.path)
        message = "Screenshots now save to \(ScreenshotLocation.display(url))."
        refresh()
    }

    func setScreenshotFormat(_ format: ScreenshotFormat) {
        write(MacDomains.screenCapture, MacSettingsCatalog.screenshotTypeKey, format.rawValue)
        refresh()
    }

    func revealScreenshotFolder() {
        workspace.open(screenshotFolder)
    }

    // MARK: Toggles

    func value(of toggle: MacToggle) -> Bool {
        toggleValues[toggle.id] ?? toggle.appleDefault
    }

    func set(_ toggle: MacToggle, _ on: Bool) {
        write(toggle.domain, toggle.key, on)
        if toggle.takesEffect == .afterFinderRelaunch { finderNeedsRelaunch = true }
        refresh()
    }

    /// Quits and reopens Finder so it reads its preferences again. Open Finder windows come back.
    func relaunchFinder() {
        let finders = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
        finders.forEach { $0.terminate() }
        finderNeedsRelaunch = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self else { return }
            if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").isEmpty,
               let finder = self.workspace.urlForApplication(withBundleIdentifier: "com.apple.finder") {
                self.workspace.openApplication(at: finder, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }

    // MARK: Default browser

    private static let probeURL = URL(string: "https://example.com")!

    private func refreshBrowsers() {
        currentBrowser = workspace.urlForApplication(toOpen: Self.probeURL).map(AppChoice.init)
        browsers = uniqueApps(workspace.urlsForApplications(toOpen: Self.probeURL))
    }

    func setDefaultBrowser(_ app: AppChoice) {
        guard app != currentBrowser else { return }
        let key = OriginalsJournal.schemeKey("http")
        if let current = currentBrowser {
            recordOriginal(key, .value(current.url.path))
        }
        // macOS asks for confirmation ("Use X as your default browser?") and sets http and https together.
        Task { @MainActor [weak self] in
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: app.url, toOpenURLsWithScheme: "http")
                self?.refreshBrowsers()
                if self?.currentBrowser == app { self?.message = "\(app.name) is now the default browser." }
            } catch {
                self?.refreshBrowsers()
                self?.message = "macOS didn't change the browser: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Default apps for file types

    private func refreshFileTypes() {
        fileTypes = FileTypeCatalog.groups.flatMap(\.entries).map { entry in
            let type = UTType(filenameExtension: entry.ext)
            let current = type.flatMap { workspace.urlForApplication(toOpen: $0) }.map(AppChoice.init)
            let candidates = type.map { uniqueApps(workspace.urlsForApplications(toOpen: $0)) } ?? []
            return FileTypeDefault(entry: entry, type: type, current: current, candidates: candidates)
        }
    }

    /// Editors worth offering for every text-like file, even when they don't declare the type.
    var commonEditors: [AppChoice] {
        let ids = ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.sublimetext.4",
                   "com.panic.Nova", "com.barebones.bbedit", "com.apple.dt.Xcode", "com.apple.TextEdit",
                   "abnerworks.Typora", "md.obsidian", "com.google.antigravity"]
        return ids.compactMap { workspace.urlForApplication(withBundleIdentifier: $0) }.map(AppChoice.init)
    }

    func choices(for item: FileTypeDefault) -> [AppChoice] {
        uniqueApps((item.candidates + commonEditors).map(\.url))
    }

    func setDefault(_ app: AppChoice, for items: [FileTypeDefault]) {
        let targets = items.filter { $0.current != app && $0.type != nil }
        guard !targets.isEmpty else { return }
        // Two extensions can share one system type (md and markdown); set each type once.
        var done = Set<String>()
        var types: [(ext: String, type: UTType)] = []
        for item in targets {
            guard let type = item.type, done.insert(type.identifier).inserted else { continue }
            if let current = item.current {
                recordOriginal(OriginalsJournal.contentTypeKey(type.identifier), .value(current.url.path))
            }
            types.append((item.entry.ext, type))
        }
        let names = targets.map { ".\($0.entry.ext)" }.joined(separator: ", ")
        Task { @MainActor [weak self] in
            var failures: [String] = []
            for (ext, type) in types {
                do { try await NSWorkspace.shared.setDefaultApplication(at: app.url, toOpen: type) }
                catch { failures.append(".\(ext)") }
            }
            guard let self else { return }
            self.refreshFileTypes()
            self.message = failures.isEmpty
                ? "\(names) now open in \(app.name)."
                : "macOS didn't change \(failures.joined(separator: ", ")). Try choosing the app again."
        }
    }

    func chooseOtherApp(for items: [FileTypeDefault]) {
        guard let app = pickApplication() else { return }
        setDefault(app, for: items)
    }

    func chooseOtherBrowser() {
        guard let app = pickApplication() else { return }
        setDefaultBrowser(app)
    }

    private func pickApplication() -> AppChoice? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Use This App"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return AppChoice(url: url)
    }

    // MARK: Undo

    /// Puts every setting Gary Tools changed back to what it was before the first change.
    func restoreOriginals() {
        let entries = journal.entries
        var needsFinder = false
        for (key, original) in entries {
            let parts = key.split(separator: "|", maxSplits: 2).map(String.init)
            switch parts.first {
            case "defaults" where parts.count == 3:
                writeRaw(parts[1], parts[2], PreferenceCoding.decode(original))
                if MacSettingsCatalog.finderToggles.contains(where: { $0.domain == parts[1] && $0.key == parts[2] }) {
                    needsFinder = true
                }
            case "type" where parts.count == 2:
                if case .value(let path) = original, let type = UTType(parts[1]) {
                    Task { try? await NSWorkspace.shared.setDefaultApplication(at: URL(fileURLWithPath: path), toOpen: type) }
                }
            case "scheme" where parts.count == 2:
                if case .value(let path) = original {
                    let scheme = parts[1]
                    Task { try? await NSWorkspace.shared.setDefaultApplication(at: URL(fileURLWithPath: path), toOpenURLsWithScheme: scheme) }
                }
            default:
                break
            }
        }
        journal = OriginalsJournal()
        persistJournal()
        finderNeedsRelaunch = needsFinder
        message = "Put back \(entries.count) setting\(entries.count == 1 ? "" : "s") as they were before Gary Tools changed them."
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.refresh()
        }
    }

    // MARK: Preferences backend

    private func cfDomain(_ domain: String) -> CFString {
        domain == MacDomains.global ? kCFPreferencesAnyApplication : domain as CFString
    }

    private func read(_ domain: String, _ key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, cfDomain(domain))
    }

    private func write(_ domain: String, _ key: String, _ value: Any) {
        recordOriginal(OriginalsJournal.preferenceKey(domain: domain, key: key), PreferenceCoding.encode(read(domain, key)))
        writeRaw(domain, key, value)
    }

    /// Writes (or with nil, removes) a key for the current user on any host, the same place `defaults write` uses.
    private func writeRaw(_ domain: String, _ key: String, _ value: Any?) {
        let app = cfDomain(domain)
        let cfValue: CFPropertyList? = value.map { $0 as AnyObject }
        CFPreferencesSetValue(key as CFString, cfValue, app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private func recordOriginal(_ key: String, _ original: OriginalsJournal.Original) {
        if journal.recordIfNeeded(key, current: original) { persistJournal() }
    }

    private func persistJournal() {
        do { try journal.save() }
        catch { message = "Couldn't save the undo record: \(error.localizedDescription)" }
    }

    private func uniqueApps(_ urls: [URL]) -> [AppChoice] {
        var seen = Set<String>()
        var result: [AppChoice] = []
        for url in urls {
            let id = Bundle(url: url)?.bundleIdentifier ?? url.path
            if seen.insert(id).inserted { result.append(AppChoice(url: url)) }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
