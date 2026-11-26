import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import GaryCore

@MainActor
final class PermissionsModel: ObservableObject {
    @Published private(set) var accessibilityGranted: Bool = AXIsProcessTrusted()
    @Published private(set) var screenRecordingGranted: Bool = CGPreflightScreenCaptureAccess()
    @Published private(set) var daemonRunning: Bool = false
    @Published private(set) var daemonInstalled: Bool = false
    @Published private(set) var pmsetRuleInstalled: Bool = false
    @Published private(set) var herdrInstalled: Bool = false
    @Published private(set) var isStablySigned: Bool = false
    @Published var actionMessage: String?

    var allCorePermissionsGranted: Bool { accessibilityGranted && screenRecordingGranted }

    private var pollRefCount = 0
    private var pollTimer: Timer?
    private var hasCheckedSignature = false

    init() {
        refresh()
    }

    func refresh() {
        let fm = FileManager.default
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        pmsetRuleInstalled = fm.fileExists(atPath: "/etc/sudoers.d/lidguard")
            || fm.fileExists(atPath: "/etc/sudoers.d/gary-tools")
        daemonInstalled = fm.fileExists(atPath: Self.daemonPlistURL.path)
        herdrInstalled = Self.detectHerdrInstalled()

        let shouldCheckSignature = !hasCheckedSignature
        let bundlePath = Bundle.main.bundlePath
        let daemonLabel = LidGuardModel.daemonLabel
        let uid = getuid()

        Task.detached(priority: .utility) { [weak self] in
            let running = Self.checkDaemonRunning(uid: uid, label: daemonLabel)
            let stablySigned: Bool? = shouldCheckSignature ? Self.checkStablySigned(bundlePath: bundlePath) : nil

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.daemonRunning = running
                if let stablySigned {
                    self.isStablySigned = stablySigned
                    self.hasCheckedSignature = true
                }
            }
        }
    }

    func startLivePolling() {
        pollRefCount += 1
        guard pollTimer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopLivePolling() {
        pollRefCount = max(0, pollRefCount - 1)
        guard pollRefCount == 0 else { return }
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openAccessibilitySettings()
    }

    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        openScreenRecordingSettings()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func installPmsetRule() {
        let user = NSUserName()
        guard !user.isEmpty,
              user.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else {
            actionMessage = "Couldn’t validate your macOS username for the sudoers rule."
            return
        }

        actionMessage = "Waiting for administrator approval…"

        Task.detached(priority: .userInitiated) { [weak self] in
            let shellScript = """
            set -e
            TMP=$(mktemp /tmp/gary-tools-sudoers.XXXXXX)
            trap 'rm -f "$TMP"' EXIT
            printf '%s ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\\n' '\(user)' > "$TMP"
            /usr/sbin/visudo -cf "$TMP" >/dev/null
            /usr/bin/install -m 0440 -o root -g wheel "$TMP" /etc/sudoers.d/gary-tools
            """
            let escaped = shellScript
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "; ")

            let appleScript = "do shell script \"\(escaped)\" with administrator privileges"
            let result = Self.runProcess("/usr/bin/osascript", ["-e", appleScript])

            await MainActor.run { [weak self] in
                guard let self else { return }
                if result.status == 0 {
                    self.actionMessage = "Sleep control rule installed."
                } else if result.output.localizedCaseInsensitiveContains("User canceled")
                    || result.output.contains("-128") {
                    self.actionMessage = "Administrator prompt was cancelled."
                } else {
                    let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.actionMessage = detail.isEmpty
                        ? "Couldn’t install the sleep control rule."
                        : "Couldn’t install the sleep control rule: \(detail)"
                }
                self.refresh()
            }
        }
    }

    func installOrRepairDaemon() {
        let fm = FileManager.default
        let scriptURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/lidguard.sh")
        guard fm.fileExists(atPath: scriptURL.path) else {
            actionMessage = "Background daemon script isn’t bundled in this build. Launch Gary Tools.app to install the daemon."
            return
        }

        let dataDir = GaryToolsPaths.appSupportRoot
        let settingsURL = GaryToolsPaths.settingsConfURL
        let plistURL = Self.daemonPlistURL
        let logPath = GaryToolsPaths.logURL.path
        let homePath = fm.homeDirectoryForCurrentUser.path
        let daemonLabel = LidGuardModel.daemonLabel
        let uid = getuid()

        do {
            try fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            if !fm.fileExists(atPath: settingsURL.path),
               let bundledDefault = Bundle.main.url(forResource: "settings.default", withExtension: "conf") {
                try fm.copyItem(at: bundledDefault, to: settingsURL)
            }

            let plistObject: [String: Any] = [
                "Label": daemonLabel,
                "ProgramArguments": [scriptURL.path],
                "EnvironmentVariables": [
                    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:\(homePath)/.local/bin:/opt/homebrew/bin:/usr/local/bin",
                    "GARY_TOOLS_DATA_DIR": dataDir.path,
                ],
                "RunAtLoad": true,
                "KeepAlive": true,
                "StandardOutPath": logPath,
                "StandardErrorPath": logPath,
            ]
            let plistData = try PropertyListSerialization.data(fromPropertyList: plistObject, format: .xml, options: 0)
            try plistData.write(to: plistURL, options: .atomic)
        } catch {
            actionMessage = "Couldn’t write daemon LaunchAgent: \(error.localizedDescription)"
            return
        }

        actionMessage = "Starting background daemon…"

        Task.detached(priority: .userInitiated) { [weak self] in
            let guiDomain = "gui/\(uid)"
            let serviceTarget = "\(guiDomain)/\(daemonLabel)"
            _ = Self.runProcess("/bin/launchctl", ["bootout", serviceTarget])
            _ = Self.runProcess("/bin/launchctl", ["enable", serviceTarget])
            let bootstrap = Self.runProcess("/bin/launchctl", ["bootstrap", guiDomain, plistURL.path])

            await MainActor.run { [weak self] in
                guard let self else { return }
                if bootstrap.status == 0 {
                    self.actionMessage = "Background daemon installed and running."
                } else {
                    let detail = bootstrap.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.actionMessage = detail.isEmpty
                        ? "Couldn’t start background daemon (launchctl exit \(bootstrap.status))."
                        : "Couldn’t start background daemon: \(detail)"
                }
                self.refresh()
            }
        }
    }

    // MARK: - Helpers

    private nonisolated static var daemonPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(LidGuardModel.daemonLabel).plist")
    }

    private nonisolated static func detectHerdrInstalled() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/herdr").path,
            "/opt/homebrew/bin/herdr",
            "/usr/local/bin/herdr",
        ]
        return candidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private nonisolated static func checkDaemonRunning(uid: uid_t, label: String) -> Bool {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: GaryToolsPaths.statusURL.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) <= 90 {
            return true
        }
        return runProcess("/bin/launchctl", ["print", "gui/\(uid)/\(label)"]).status == 0
    }

    private nonisolated static func checkStablySigned(bundlePath: String) -> Bool {
        let result = runProcess("/usr/bin/codesign", ["-dv", bundlePath])
        guard result.status == 0 else { return false }
        return !result.output.contains("Signature=adhoc") && !result.output.contains("flags=0x2(adhoc)")
    }

    @discardableResult
    private nonisolated static func runProcess(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
