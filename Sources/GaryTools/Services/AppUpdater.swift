import Combine
import Foundation
import GaryCore

@MainActor
final class AppUpdater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(commit: String)
        case available(UpdateInfo)
        case updating(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date?
    @Published private(set) var sourceRepoURL: URL?

    private static let silentCheckThrottleInterval: TimeInterval = 300
    private static let bootstrapScriptURL = "https://raw.githubusercontent.com/Nicegarrry/gary-tools/main/scripts/bootstrap.sh"

    private var isCheckingInFlight = false
    private var updateProcess: Process?

    var currentCommit: String {
        let raw = (Bundle.main.infoDictionary?["GaryToolsGitCommit"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "local" : raw
    }

    var hasUpdate: Bool {
        if case .available = state { return true }
        return false
    }

    var isBusy: Bool {
        switch state {
        case .checking, .updating: return true
        default: return false
        }
    }

    init() {
        sourceRepoURL = UpdateSourceLocator.locateSourceRepo(bundleURL: Bundle.main.bundleURL)
    }

    func checkForUpdates(silent: Bool = false) {
        guard !isBusy, !isCheckingInFlight else { return }
        if silent, let lastChecked, Date().timeIntervalSince(lastChecked) < Self.silentCheckThrottleInterval {
            return
        }

        sourceRepoURL = UpdateSourceLocator.locateSourceRepo(bundleURL: Bundle.main.bundleURL)
        isCheckingInFlight = true
        if !silent {
            state = .checking
        }

        let commit = currentCommit
        Task { @MainActor [weak self] in
            defer { self?.isCheckingInFlight = false }
            do {
                let outcome = try await Self.fetchUpdateOutcome(currentCommit: commit)
                guard let self else { return }
                self.lastChecked = Date()
                switch outcome {
                case .upToDate(let resolvedCommit):
                    self.state = .upToDate(commit: resolvedCommit)
                case .updateAvailable(let info):
                    self.state = .available(info)
                case .unknown(let reason):
                    if silent {
                        if case .checking = self.state { self.state = .idle }
                    } else {
                        self.state = .failed(reason)
                    }
                }
            } catch {
                guard let self else { return }
                if silent {
                    if case .checking = self.state { self.state = .idle }
                } else {
                    self.state = .failed(Self.friendlyNetworkError(error))
                }
            }
        }
    }

    func installUpdate() {
        guard !isBusy else { return }

        sourceRepoURL = UpdateSourceLocator.locateSourceRepo(bundleURL: Bundle.main.bundleURL)
        state = .updating("Downloading and building update…")

        let logURL = Self.updateLogURL
        let fm = FileManager.default
        try? fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let command: String
        if let repoURL = sourceRepoURL {
            let updateScript = repoURL.appendingPathComponent("update.sh").path
            if fm.fileExists(atPath: updateScript) {
                var args = [Self.shellQuote(updateScript), "--no-sudo"]
                let bundleURL = Bundle.main.bundleURL.standardizedFileURL
                if bundleURL.path.hasPrefix("/Applications/") {
                    args.append("--applications")
                } else if bundleURL.deletingLastPathComponent().lastPathComponent == "dist" {
                    args.append("--local-dist")
                }
                command = "/bin/bash " + args.joined(separator: " ")
            } else {
                command = "curl -fsSL \(Self.shellQuote(Self.bootstrapScriptURL)) | /bin/bash"
            }
        } else {
            command = "curl -fsSL \(Self.shellQuote(Self.bootstrapScriptURL)) | /bin/bash"
        }

        // Ignore SIGHUP and redirect all I/O directly to the log file so that when install.sh
        // gracefully quits this running app to swap in the new build, the updater continues cleanly.
        let wrappedCommand = "trap '' HUP; (\(command)) > \(Self.shellQuote(logURL.path)) 2>&1"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", wrappedCommand]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        var env = ProcessInfo.processInfo.environment
        let home = fm.homeDirectoryForCurrentUser.path
        let requiredPath = "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let existing = env["PATH"], !existing.isEmpty {
            env["PATH"] = "\(requiredPath):\(existing)"
        } else {
            env["PATH"] = requiredPath
        }
        process.environment = env

        process.terminationHandler = { [weak self] finished in
            let exitCode = finished.terminationStatus
            let summary = exitCode == 0 ? nil : Self.readLastErrorLine(from: logURL)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateProcess = nil
                if exitCode != 0 {
                    self.state = .failed(summary ?? "Update failed (exit code \(exitCode)). Check ~/Library/Logs/gary-tools-update.log.")
                } else {
                    self.state = .upToDate(commit: self.currentCommit)
                }
            }
        }

        do {
            try process.run()
            updateProcess = process
        } catch {
            state = .failed("Couldn’t start updater: \(error.localizedDescription)")
        }
    }

    // MARK: - Networking

    private enum FetchError: LocalizedError {
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .httpStatus(403):
                return "GitHub API rate limit reached. Try again in a few minutes."
            case .httpStatus(let code):
                return "GitHub returned HTTP \(code)."
            }
        }
    }

    private nonisolated static func fetchUpdateOutcome(currentCommit: String) async throws -> UpdateCheckOutcome {
        if isValidHexSHA(currentCommit) {
            let compareURL = UpdateParser.compareAPIURL(from: currentCommit)
            let (data, status) = try await fetchJSON(from: compareURL)
            if status == 200 {
                return try UpdateParser.parseGitHubCompareResponse(data, currentCommit: currentCommit)
            }
            if status != 404 {
                throw FetchError.httpStatus(status)
            }
        }

        let latestURL = UpdateParser.latestCommitAPIURL()
        let (data, status) = try await fetchJSON(from: latestURL)
        guard status == 200 else {
            throw FetchError.httpStatus(status)
        }
        let compareBase = isValidHexSHA(currentCommit) ? currentCommit : nil
        return try UpdateParser.parseGitHubLatestCommitResponse(data, currentCommit: compareBase)
    }

    private nonisolated static func fetchJSON(from url: URL) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GaryTools", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (data, status)
    }

    private nonisolated static func isValidHexSHA(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 7, trimmed.count <= 40 else { return false }
        return trimmed.unicodeScalars.allSatisfy { scalar in
            (scalar >= "0" && scalar <= "9")
                || (scalar >= "a" && scalar <= "f")
                || (scalar >= "A" && scalar <= "F")
        }
    }

    private nonisolated static func friendlyNetworkError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                return "Couldn’t reach GitHub. Check your internet connection."
            case .timedOut:
                return "Timed out checking GitHub for updates."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    // MARK: - Log & shell helpers

    private nonisolated static var updateLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/gary-tools-update.log")
    }

    private nonisolated static func readLastErrorLine(from logURL: URL) -> String? {
        guard let raw = try? String(contentsOf: logURL, encoding: .utf8) else { return nil }
        let cleaned = stripANSI(raw)
        let lines = cleaned
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let explicitError = lines.last(where: { $0.localizedCaseInsensitiveContains("error:") || $0.localizedCaseInsensitiveContains("fatal:") }) {
            return explicitError
        }
        return lines.last
    }

    private nonisolated static func stripANSI(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\u{001B}\[[0-9;]*[A-Za-z]"#, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    private nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
