import AppKit
import Foundation
import GaryCore

enum SettingsFile {
    static func read(from url: URL = GaryToolsPaths.settingsConfURL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { continue }
            let key = t[..<eq].trimmingCharacters(in: .whitespaces)
            let value = t[t.index(after: eq)...].split(separator: "#").first.map(String.init) ?? ""
            out[key] = value.trimmingCharacters(in: .whitespaces)
        }
        return out
    }

    /// Replace the KEY=… line (or append it), leaving every comment untouched.
    static func write(_ key: String, _ value: String, to url: URL = GaryToolsPaths.settingsConfURL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var lines = text.components(separatedBy: "\n")
        let isLine: (String) -> Bool = { l in
            let t = l.trimmingCharacters(in: .whitespaces)
            return !t.hasPrefix("#") && t.hasPrefix(key) &&
                t.dropFirst(key.count).trimmingCharacters(in: .whitespaces).hasPrefix("=")
        }
        if let i = lines.firstIndex(where: isLine) { lines[i] = "\(key)=\(value)" }
        else { lines.append("\(key)=\(value)") }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

let untilFormat: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm"
    return f
}()

let timeOnlyFormat: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .none
    f.timeStyle = .short
    return f
}()

func next7am() -> Date {
    Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 7, minute: 0), matchingPolicy: .nextTime)!
}

struct HookStatus: Identifiable {
    let id: String
    let name: String
    let installed: Bool
    let path: String
}

@MainActor
final class LidGuardModel: ObservableObject {
    nonisolated static let daemonLabel = "com.\(NSUserName()).garytools.daemon"

    @Published var enabled = false                 { didSet { save("ENABLED", enabled) } }
    @Published var keepAwake = false               { didSet { save("KEEP_AWAKE_ALWAYS", keepAwake) } }
    @Published var keepAwakeUntil = ""             { didSet { save("KEEP_AWAKE_UNTIL", keepAwakeUntil) } }
    @Published var waitForInput = 3                { didSet { save("WAIT_FOR_INPUT_MINUTES", waitForInput) } }
    @Published var minBattery = 20                 { didSet { save("MIN_BATTERY_PERCENT", minBattery) } }
    @Published var sleepInLowPower = true          { didSet { save("SLEEP_IN_LOW_POWER_MODE", sleepInLowPower) } }
    @Published var heatLimit = "serious"           { didSet { save("HEAT_LIMIT", heatLimit) } }
    @Published var batteryLimitHours = 4.0         { didSet { save("BATTERY_LID_CLOSED_LIMIT_HOURS", hoursString) } }
    @Published var leaveAloneWithMonitor = true    { didSet { save("LEAVE_ALONE_WITH_EXTERNAL_MONITOR", leaveAloneWithMonitor) } }
    @Published var lockOnLidClose = true           { didSet { save("LOCK_SCREEN_WHEN_LID_CLOSES", lockOnLidClose) } }
    @Published var notifyOnSleep = true            { didSet { save("NOTIFY_ON_SLEEP", notifyOnSleep) } }
    @Published var startAtLogin = true             { didSet { save("START_AT_LOGIN", startAtLogin) } }
    @Published var turnOnAtLogin = false           { didSet { save("TURN_ON_AT_LOGIN", turnOnAtLogin) } }
    @Published var checkEvery = 2                  { didSet { save("CHECK_EVERY_SECONDS", checkEvery) } }
    @Published var waitBeforeSleep = 20            { didSet { save("WAIT_BEFORE_SLEEP_SECONDS", waitBeforeSleep) } }
    @Published var autoPullRepos = true            { didSet { save("AUTO_PULL_REPOS", autoPullRepos) } }
    @Published var autoPullIntervalMinutes = 60    { didSet { save("AUTO_PULL_INTERVAL_MINUTES", autoPullIntervalMinutes) } }
    @Published var autoPullDirs: [String] = [RepoSyncConfig.defaultFolder] {
        didSet {
            guard !loading, !syncingDirs else { return }
            syncingDirs = true
            let serialized = RepoSyncConfig.serializeDirs(autoPullDirs)
            let primary = autoPullDirs.first ?? RepoSyncConfig.defaultFolder
            autoPullDir = primary
            syncingDirs = false
            save("AUTO_PULL_DIRS", serialized)
            save("AUTO_PULL_DIR", primary)
            refreshRepoCount()
        }
    }
    @Published var autoPullDir = RepoSyncConfig.defaultFolder {
        didSet {
            guard !loading, !syncingDirs else { return }
            syncingDirs = true
            let trimmed = autoPullDir.trimmingCharacters(in: .whitespacesAndNewlines)
            let primary = trimmed.isEmpty ? RepoSyncConfig.defaultFolder : trimmed
            var updated = autoPullDirs
            if updated.isEmpty {
                updated = [primary]
            } else {
                updated[0] = primary
            }
            autoPullDirs = updated
            let serialized = RepoSyncConfig.serializeDirs(updated)
            syncingDirs = false
            save("AUTO_PULL_DIR", primary)
            save("AUTO_PULL_DIRS", serialized)
            refreshRepoCount()
        }
    }

    @Published private(set) var daemonState = "stale"
    @Published private(set) var statusMessage = "Starting daemon…"
    @Published private(set) var lastSleepMessage = ""
    @Published private(set) var lastGitSyncText = "Not synced yet"
    @Published private(set) var daemonRunning = false
    @Published private(set) var sudoersInstalled = false
    @Published var pullingNow = false
    @Published private(set) var sessionHooks: [HookStatus] = []
    @Published private(set) var repoCount: Int = 0
    @Published private(set) var herdrInstalled: Bool = false

    private var loading = false
    private var syncingDirs = false

    var hoursString: String {
        batteryLimitHours == batteryLimitHours.rounded() ? String(Int(batteryLimitHours)) : String(batteryLimitHours)
    }

    var keepAwakeUntilDate: Date? { untilFormat.date(from: keepAwakeUntil) }

    var keepAwakeStatus: String {
        guard keepAwake else { return "Off" }
        if let d = keepAwakeUntilDate { return "On until \(timeOnlyFormat.string(from: d))" }
        return "On until you turn it off"
    }

    var intervalLabel: String {
        let m = autoPullIntervalMinutes
        let h = m / 60, rem = m % 60
        if h > 0 && rem > 0 { return "\(h)h \(rem)m" }
        if h > 0 { return "\(h) h" }
        return "\(m) min"
    }

    init() {
        ensureDefaultSettings()
        reload()
        refreshStatus()
        checkEnvironment()
    }

    private func ensureDefaultSettings() {
        let dest = GaryToolsPaths.settingsConfURL
        let fm = FileManager.default
        if !fm.fileExists(atPath: dest.path) {
            if let bundled = Bundle.main.url(forResource: "settings.default", withExtension: "conf") {
                try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.copyItem(at: bundled, to: dest)
            }
        }
    }

    func reload() {
        loading = true
        defer { loading = false }
        let s = SettingsFile.read()
        func bool(_ k: String, _ d: Bool) -> Bool { s[k].map { $0.lowercased() == "yes" } ?? d }
        func int(_ k: String, _ d: Int) -> Int { s[k].flatMap(Int.init) ?? d }
        enabled                 = bool("ENABLED", false)
        keepAwake               = bool("KEEP_AWAKE_ALWAYS", false)
        keepAwakeUntil          = s["KEEP_AWAKE_UNTIL"] ?? ""
        waitForInput            = int("WAIT_FOR_INPUT_MINUTES", 3)
        minBattery              = int("MIN_BATTERY_PERCENT", 20)
        sleepInLowPower         = bool("SLEEP_IN_LOW_POWER_MODE", true)
        heatLimit               = (s["HEAT_LIMIT"] ?? "serious").lowercased()
        batteryLimitHours       = s["BATTERY_LID_CLOSED_LIMIT_HOURS"].flatMap(Double.init) ?? 4
        leaveAloneWithMonitor   = bool("LEAVE_ALONE_WITH_EXTERNAL_MONITOR", true)
        lockOnLidClose          = bool("LOCK_SCREEN_WHEN_LID_CLOSES", true)
        notifyOnSleep           = bool("NOTIFY_ON_SLEEP", true)
        startAtLogin            = bool("START_AT_LOGIN", true)
        turnOnAtLogin           = bool("TURN_ON_AT_LOGIN", false)
        checkEvery              = int("CHECK_EVERY_SECONDS", 2)
        waitBeforeSleep         = int("WAIT_BEFORE_SLEEP_SECONDS", 20)
        autoPullRepos           = bool("AUTO_PULL_REPOS", true)
        autoPullIntervalMinutes = int("AUTO_PULL_INTERVAL_MINUTES", 60)
        autoPullDirs            = RepoSyncConfig.parseDirs(autoPullDirs: s["AUTO_PULL_DIRS"], fallbackSingleDir: s["AUTO_PULL_DIR"])
        autoPullDir             = autoPullDirs.first ?? RepoSyncConfig.defaultFolder
        refreshRepoCount()
    }

    func refreshStatus() {
        let s = SettingsFile.read()
        let isEnabled = s["ENABLED"].map { $0.lowercased() == "yes" } ?? enabled
        let isKeepAwake = s["KEEP_AWAKE_ALWAYS"].map { $0.lowercased() == "yes" } ?? keepAwake
        if isEnabled != enabled || isKeepAwake != keepAwake {
            reload()
        }

        var state = isKeepAwake ? "caffeine" : (isEnabled ? "idle" : "off")
        var message = isKeepAwake ? "Keep Awake" : (isEnabled ? "On — watching agents" : "Off — Mac sleeps normally")
        var running = false

        if let raw = try? String(contentsOf: GaryToolsPaths.statusURL, encoding: .utf8),
           let modified = (try? FileManager.default.attributesOfItem(atPath: GaryToolsPaths.statusURL.path))?[.modificationDate] as? Date {
            let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", maxSplits: 1).map(String.init)
            if Date().timeIntervalSince(modified) > 90 {
                state = "stale"
                message = "Background daemon isn’t running"
                running = false
            } else if parts.count == 2 {
                running = true
                let consistent = isKeepAwake ? (parts[0] == "caffeine" || parts[0] == "idle")
                    : (isEnabled ? (parts[0] == "idle" || parts[0] == "awake") : parts[0] == "off")
                if consistent {
                    state = parts[0]
                    message = parts[1]
                }
            }
        } else {
            state = "stale"
            message = "Background daemon isn’t running"
            running = false
        }

        daemonState = state
        statusMessage = message
        daemonRunning = running

        if let raw = try? String(contentsOf: GaryToolsPaths.lastSleepURL, encoding: .utf8) {
            let p = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", maxSplits: 1).map(String.init)
            lastSleepMessage = p.count == 2 ? "Last put to sleep \(p[0]) — \(p[1])" : ""
        } else {
            lastSleepMessage = ""
        }

        refreshGitSync()
    }

    func refreshGitSync() {
        if let raw = try? String(contentsOf: GaryToolsPaths.lastGitSyncURL, encoding: .utf8) {
            let p = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", maxSplits: 2).map(String.init)
            if p.count == 3 {
                lastGitSyncText = "\(p[1]) — \(p[2])"
                if pullingNow, let ts = Double(p[0]), Date().timeIntervalSince1970 - ts < 15 {
                    pullingNow = false
                }
                return
            }
        }
        lastGitSyncText = "Not synced yet"
    }

    func checkEnvironment() {
        sudoersInstalled = FileManager.default.fileExists(atPath: "/etc/sudoers.d/lidguard")
            || FileManager.default.fileExists(atPath: "/etc/sudoers.d/gary-tools")
        let home = FileManager.default.homeDirectoryForCurrentUser
        herdrInstalled = [
            home.appendingPathComponent(".local/bin/herdr").path,
            "/opt/homebrew/bin/herdr",
            "/usr/local/bin/herdr",
        ].contains { FileManager.default.isExecutableFile(atPath: $0) }
        sessionHooks = AgentHookManager.allStatuses(home: home).map {
            HookStatus(id: $0.id, name: $0.kind.displayName, installed: $0.installed, path: $0.path)
        }
    }

    func addAutoPullFolder(_ url: URL) {
        let display = RepoSyncConfig.display(url)
        let incomingKey = RepoSyncConfig.expand(display).standardizedFileURL.path.lowercased()
        let alreadyPresent = autoPullDirs.contains {
            RepoSyncConfig.expand($0).standardizedFileURL.path.lowercased() == incomingKey
        }
        guard !alreadyPresent else { return }
        autoPullDirs.append(display)
    }

    func chooseAutoPullFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = RepoSyncConfig.expand(autoPullDirs.first ?? RepoSyncConfig.defaultFolder)
        panel.prompt = "Add Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addAutoPullFolder(url)
    }

    func removeAutoPullFolder(_ path: String) {
        let targetKey = RepoSyncConfig.expand(path).standardizedFileURL.path.lowercased()
        autoPullDirs.removeAll {
            $0 == path || RepoSyncConfig.expand($0).standardizedFileURL.path.lowercased() == targetKey
        }
    }

    func refreshRepoCount() {
        let dirs = autoPullDirs
        Task.detached(priority: .utility) { [weak self] in
            let count = RepoSyncConfig.countGitRepos(in: dirs)
            await MainActor.run { [weak self] in
                self?.repoCount = count
            }
        }
    }

    func startKeepAwake(until: Date?) {
        reload()
        keepAwakeUntil = until.map { untilFormat.string(from: $0) } ?? ""
        keepAwake = true
    }

    func stopKeepAwake() {
        reload()
        keepAwake = false
        keepAwakeUntil = ""
    }

    func triggerPullNow() {
        pullingNow = true
        try? FileManager.default.createDirectory(at: GaryToolsPaths.appSupportRoot, withIntermediateDirectories: true)
        try? "".write(to: GaryToolsPaths.pullNowURL, atomically: true, encoding: .utf8)
        // If the background daemon is not running, invoke the bundled script directly.
        if !daemonRunning {
            runDirectGitSync()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            self?.pullingNow = false
            self?.refreshGitSync()
        }
    }

    private func runDirectGitSync() {
        let scriptPath = Bundle.main.url(forResource: "dev-pull-all", withExtension: "sh")?.path
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/dev-pull-all").path
        guard FileManager.default.isExecutableFile(atPath: scriptPath) else { return }
        let serializedDirs = RepoSyncConfig.serializeDirs(autoPullDirs)
        let dirsArg = serializedDirs.isEmpty ? RepoSyncConfig.defaultFolder : serializedDirs
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: scriptPath)
            proc.arguments = ["--always", "--format", "log", "--dirs", dirsArg]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let summary = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "sync completed"
            let now = Int(Date().timeIntervalSince1970)
            let fmt = DateFormatter()
            fmt.dateFormat = "EEE HH:mm"
            let line = "\(now)|\(fmt.string(from: Date()))|\(summary.isEmpty ? "sync completed" : summary)\n"
            try? line.write(to: GaryToolsPaths.lastGitSyncURL, atomically: true, encoding: .utf8)
            DispatchQueue.main.async {
                self?.pullingNow = false
                self?.refreshGitSync()
            }
        }
    }

    func ensureDaemonRunning() {
        let uid = getuid()
        if runProcess("/bin/launchctl", ["print", "gui/\(uid)/\(Self.daemonLabel)"]) == 0 { return }
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.daemonLabel).plist").path
        guard FileManager.default.fileExists(atPath: plist) else { return }
        _ = runProcess("/bin/launchctl", ["enable", "gui/\(uid)/\(Self.daemonLabel)"])
        _ = runProcess("/bin/launchctl", ["bootstrap", "gui/\(uid)", plist])
    }

    func openLog() {
        if FileManager.default.fileExists(atPath: GaryToolsPaths.logURL.path) {
            NSWorkspace.shared.open(GaryToolsPaths.logURL)
        } else {
            let legacy = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/lidguard.log")
            if FileManager.default.fileExists(atPath: legacy.path) { NSWorkspace.shared.open(legacy) }
        }
    }

    @discardableResult
    private func runProcess(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus } catch { return -1 }
    }

    private func save(_ key: String, _ v: Bool) { save(key, v ? "yes" : "no") }
    private func save(_ key: String, _ v: Int) { save(key, String(v)) }
    private func save(_ key: String, _ v: String) {
        guard !loading else { return }
        SettingsFile.write(key, v)
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
}
