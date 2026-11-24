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
    @Published private(set) var developerFolderExists = false
    @Published private(set) var commandLineToolsPath: String?
    @Published private(set) var homebrewPath: String?
    @Published private(set) var chromeApp: AppChoice?
    @Published private(set) var chromeRunning = false
    @Published private(set) var chromeProfiles: [(profile: ChromeSettings.Profile, folder: String?)] = []
    @Published private(set) var chromeInstall: ChromeInstallState = .idle

    enum ChromeInstallState: Equatable {
        case idle
        case working(String)
        case failed(String)
    }

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
        refreshChrome()
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

    // MARK: Developer folder

    func refreshDeveloperFolder(_ raw: String) {
        var isDir: ObjCBool = false
        developerFolderExists = FileManager.default.fileExists(atPath: DeveloperFolder.resolve(raw).path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Creates the folder (never touches one that exists) and offers to pin it to the Finder sidebar.
    func createDeveloperFolder(_ raw: String) {
        let url = DeveloperFolder.resolve(raw)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            message = "Created \(ScreenshotLocation.display(url))."
        } catch {
            message = "Couldn't create \(ScreenshotLocation.display(url)): \(error.localizedDescription)"
        }
        refreshDeveloperFolder(raw)
    }

    /// macOS has no supported API for the Finder sidebar, so Gary Tools selects the folder in Finder and
    /// presses Finder's own File > Add to Sidebar (⌃⌘T). Without Accessibility access it asks you to press it.
    func addDeveloperFolderToSidebar(_ raw: String) {
        let url = DeveloperFolder.resolve(raw)
        workspace.activateFileViewerSelecting([url])
        guard AXIsProcessTrusted() else {
            message = "Finder has \(ScreenshotLocation.display(url)) selected. Press ⌃⌘T to add it to the sidebar."
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
                self?.message = "Finder has \(ScreenshotLocation.display(url)) selected. Press ⌃⌘T to add it to the sidebar."
                return
            }
            let source = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0x11, keyDown: down) // T
                event?.flags = [.maskControl, .maskCommand]
                event?.post(tap: .cghidEventTap)
            }
            self?.message = "Added \(ScreenshotLocation.display(url)) to the Finder sidebar (File > Add to Sidebar)."
        }
    }

    // MARK: Developer tools

    func refreshDeveloperTools() {
        Task { @MainActor [weak self] in
            let clt = await Task.detached { DeveloperTools.commandLineToolsPath() }.value
            self?.commandLineToolsPath = clt
            self?.homebrewPath = DeveloperTools.homebrewPath()
        }
    }

    /// Opens Apple's own installer for the Command Line Tools (git, clang, make). Nothing installs without your click.
    func installCommandLineTools() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        p.arguments = ["--install"]
        do {
            try p.run()
            message = "Apple's installer is open. Click Install, then come back here."
        } catch {
            message = "Couldn't open Apple's installer: \(error.localizedDescription)"
        }
    }

    /// Opens Terminal with Homebrew's official install command, so you can see it and type your password.
    func installHomebrew() {
        guard commandLineToolsPath != nil else {
            message = "Install the Command Line Tools first. Homebrew needs them."
            return
        }
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("Install Homebrew.command")
        let body = """
        #!/bin/bash
        echo "Gary Tools: installing Homebrew with its official script (https://brew.sh)."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        echo
        echo "Done. You can close this window and go back to Gary Tools."
        rm -f "$0"

        """
        do {
            try body.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            workspace.open(script)
            message = "Homebrew's installer is running in Terminal. It will ask for your Mac password."
        } catch {
            message = "Couldn't start the Homebrew installer: \(error.localizedDescription)"
        }
    }

    // MARK: Chrome

    func refreshChrome() {
        chromeApp = workspace.urlForApplication(withBundleIdentifier: ChromeSettings.bundleID).map(AppChoice.init)
        chromeRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: ChromeSettings.bundleID).isEmpty
        chromeProfiles = ChromeSettings.profiles().map { profile in
            let folder = (try? Data(contentsOf: profile.preferencesURL)).flatMap { try? ChromeSettings.downloadDirectory(preferences: $0) }
            return (profile, folder)
        }
    }

    func quitChrome() {
        NSRunningApplication.runningApplications(withBundleIdentifier: ChromeSettings.bundleID).forEach { $0.terminate() }
        Task { @MainActor [weak self] in
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if NSRunningApplication.runningApplications(withBundleIdentifier: ChromeSettings.bundleID).isEmpty { break }
            }
            self?.refreshChrome()
        }
    }

    func chooseChromeDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = chromeProfiles.first?.folder.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        panel.prompt = "Use for Chrome Downloads"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setChromeDownloadFolder(url.standardizedFileURL.path)
    }

    /// Sets the download folder in every Chrome profile. Only while Chrome is quit, with a backup of each file.
    func setChromeDownloadFolder(_ path: String) {
        refreshChrome()
        guard !chromeRunning else {
            message = "Quit Chrome first. Chrome rewrites its settings file while it runs."
            return
        }
        var changed = 0
        var failures: [String] = []
        for (profile, current) in chromeProfiles where current != path {
            do {
                let data = try Data(contentsOf: profile.preferencesURL)
                let updated = try ChromeSettings.settingDownloadDirectory(path, in: data)
                try backup(profile.preferencesURL, name: profile.id)
                recordOriginal(OriginalsJournal.chromeKey(profile.id), current.map { .value($0) } ?? .absent)
                try updated.write(to: profile.preferencesURL, options: .atomic)
                changed += 1
            } catch {
                failures.append(profile.name)
            }
        }
        refreshChrome()
        if !failures.isEmpty {
            message = "Couldn't change Chrome profile \(failures.joined(separator: ", ")). Nothing else in it was touched."
        } else if changed > 0 {
            message = "Chrome now downloads to \(ScreenshotLocation.display(URL(fileURLWithPath: path))) in \(changed) profile\(changed == 1 ? "" : "s")."
        }
    }

    private func backup(_ file: URL, name: String) throws {
        let dir = GaryToolsPaths.appSupportRoot.appendingPathComponent("Chrome Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let stamp = Int(Date().timeIntervalSince1970)
        let dest = dir.appendingPathComponent("\(name)-Preferences-\(stamp).json")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: file, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
    }

    /// Downloads Chrome from Google, checks it is signed by Google, and copies it to /Applications.
    func installChrome() {
        guard chromeApp == nil, !isInstallingChrome else { return }
        chromeInstall = .working("Downloading Chrome…")
        Task { @MainActor [weak self] in
            do {
                let (dmg, _) = try await URLSession.shared.download(from: ChromeSettings.downloadURL)
                self?.chromeInstall = .working("Checking Google's signature and installing…")
                try await Task.detached(priority: .userInitiated) { try ChromeInstaller.install(dmg: dmg) }.value
                self?.chromeInstall = .idle
                self?.refreshChrome()
                self?.message = "Installed Google Chrome in /Applications."
            } catch {
                self?.chromeInstall = .failed(error.localizedDescription)
            }
        }
    }

    var isInstallingChrome: Bool {
        if case .working = chromeInstall { return true }
        return false
    }

    // MARK: Undo

    /// Puts every setting Gary Tools changed back to what it was before the first change.
    func restoreOriginals() {
        refreshChrome()
        var entries = journal.entries
        var kept = OriginalsJournal()
        if chromeRunning {
            for (key, original) in entries where key.hasPrefix("chrome|") {
                kept.recordIfNeeded(key, current: original)
                entries.removeValue(forKey: key)
            }
        }
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
            case "chrome" where parts.count == 2:
                guard let profile = chromeProfiles.first(where: { $0.profile.id == parts[1] })?.profile,
                      let data = try? Data(contentsOf: profile.preferencesURL) else { break }
                let path: String? = { if case .value(let v) = original { return v } else { return nil } }()
                if let updated = try? ChromeSettings.settingDownloadDirectory(path, in: data) {
                    try? backup(profile.preferencesURL, name: profile.id)
                    try? updated.write(to: profile.preferencesURL, options: .atomic)
                }
            default:
                break
            }
        }
        journal = kept
        persistJournal()
        finderNeedsRelaunch = needsFinder
        message = "Put back \(entries.count) setting\(entries.count == 1 ? "" : "s") as they were before Gary Tools changed them."
            + (kept.isEmpty ? "" : " Quit Chrome and press Undo again to put back its download folder.")
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

/// Installs Chrome from a downloaded disk image. Runs off the main thread.
enum ChromeInstaller {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    static func install(dmg: URL) throws {
        let fm = FileManager.default
        let target = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        guard !fm.fileExists(atPath: target.path) else { throw Failure("Chrome is already in /Applications.") }
        let work = fm.temporaryDirectory.appendingPathComponent("gary-chrome-\(UUID().uuidString)", isDirectory: true)
        let mount = work.appendingPathComponent("mount", isDirectory: true)
        let image = work.appendingPathComponent("googlechrome.dmg")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        defer {
            _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"])
            try? fm.removeItem(at: work)
            try? fm.removeItem(at: dmg)
        }
        try fm.moveItem(at: dmg, to: image)
        guard run("/usr/bin/hdiutil", ["attach", image.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path]).status == 0 else {
            throw Failure("The Chrome download couldn't be opened.")
        }
        let app = mount.appendingPathComponent("Google Chrome.app")
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]).status == 0 else {
            throw Failure("The downloaded Chrome failed its code signature check, so it wasn't installed.")
        }
        let info = run("/usr/bin/codesign", ["-dv", app.path])
        guard ChromeSettings.teamIdentifier(fromCodesignOutput: info.output) == ChromeSettings.googleTeamID else {
            throw Failure("The downloaded app isn't signed by Google, so it wasn't installed.")
        }
        guard run("/usr/bin/ditto", [app.path, target.path]).status == 0 else {
            throw Failure("Couldn't copy Chrome into /Applications.")
        }
    }

    /// Runs a tool and returns its exit status with stdout and stderr together (codesign -dv writes to stderr).
    private static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

enum DeveloperTools {
    /// The active developer directory if the Command Line Tools (or Xcode) are installed.
    static func commandLineToolsPath() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        p.arguments = ["-p"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard p.terminationStatus == 0, !path.isEmpty,
              FileManager.default.isExecutableFile(atPath: path + "/usr/bin/git") else { return nil }
        return path
    }

    static func homebrewPath() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
