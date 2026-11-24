import AppKit
import Combine
import Foundation
import GaryCore

@MainActor
final class GitSetupModel: ObservableObject {
    @Published private(set) var status = GitSetupStatus(
        gitInstalled: false,
        userName: "",
        userEmail: "",
        ghInstalled: false,
        ghAccount: nil,
        sshKeyNames: []
    )
    @Published private(set) var hooks: [AgentHookInfo] = []
    @Published private(set) var isRefreshing = false
    @Published var message: String?

    init() {
        refresh()
    }

    func refresh() {
        isRefreshing = true
        let home = FileManager.default.homeDirectoryForCurrentUser

        Task.detached(priority: .utility) { [weak self] in
            let gitExec = Self.resolveGitExecutable()
            var gitInstalled = false
            var userName = ""
            var userEmail = ""

            if let gitExec {
                let version = Self.runProcess(gitExec, ["--version"])
                gitInstalled = (version.status == 0)
                if gitInstalled {
                    let nameRes = Self.runProcess(gitExec, ["config", "--global", "user.name"])
                    if nameRes.status == 0 {
                        userName = nameRes.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    let emailRes = Self.runProcess(gitExec, ["config", "--global", "user.email"])
                    if emailRes.status == 0 {
                        userEmail = emailRes.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }

            let ghExec = Self.resolveGHExecutable()
            let ghInstalled = (ghExec != nil)
            var ghAccount: String?
            if let ghExec {
                let authRes = Self.runProcess(ghExec, ["auth", "status"])
                ghAccount = GitEnvironmentParser.parseGHAuthAccount(from: authRes.output)
            }

            let sshKeyNames = GitEnvironmentParser.findSSHKeyNames(in: home.appendingPathComponent(".ssh"))
            let hookStatuses = AgentHookManager.allStatuses(home: home)

            let nextStatus = GitSetupStatus(
                gitInstalled: gitInstalled,
                userName: userName,
                userEmail: userEmail,
                ghInstalled: ghInstalled,
                ghAccount: ghAccount,
                sshKeyNames: sshKeyNames
            )

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.status = nextStatus
                self.hooks = hookStatuses
                self.isRefreshing = false
            }
        }
    }

    func saveIdentity(name: String, email: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, !trimmedEmail.isEmpty else {
            message = "Enter both your Git name and email address."
            return
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let gitExec = Self.resolveGitExecutable() else {
                await MainActor.run { [weak self] in
                    self?.message = "Git isn’t installed yet. Install Command Line Tools first."
                }
                return
            }

            let nameRes = Self.runProcess(gitExec, ["config", "--global", "user.name", trimmedName])
            let emailRes = Self.runProcess(gitExec, ["config", "--global", "user.email", trimmedEmail])

            await MainActor.run { [weak self] in
                guard let self else { return }
                if nameRes.status == 0 && emailRes.status == 0 {
                    self.message = "Saved Git identity (\(trimmedName) <\(trimmedEmail)>)."
                } else {
                    let detail = [nameRes.output, emailRes.output]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    self.message = detail.isEmpty
                        ? "Couldn’t save Git identity."
                        : "Couldn’t save Git identity: \(detail)"
                }
                self.refresh()
            }
        }
    }

    func launchGitHubLogin() {
        let fm = FileManager.default
        if let ghExec = Self.resolveGHExecutable() {
            let script = fm.temporaryDirectory.appendingPathComponent("Gary Tools GitHub Login.command")
            let body = """
            #!/bin/bash
            echo "Gary Tools: signing in to GitHub CLI (gh)..."
            echo
            \(Self.shellQuote(ghExec)) auth login --web --git-protocol https
            echo
            echo "Done. You can close this window and go back to Gary Tools."
            rm -f "$0"

            """
            do {
                try body.write(to: script, atomically: true, encoding: .utf8)
                try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
                NSWorkspace.shared.open(script)
                message = "Opened Terminal for GitHub sign-in. Complete the browser prompt, then return to Gary Tools."
            } catch {
                message = "Couldn’t open Terminal for GitHub sign-in: \(error.localizedDescription)"
            }
            return
        }

        if let brewPath = DeveloperTools.homebrewPath() {
            let script = fm.temporaryDirectory.appendingPathComponent("Install GitHub CLI.command")
            let body = """
            #!/bin/bash
            echo "Gary Tools: installing GitHub CLI (gh) with Homebrew..."
            echo
            eval "$(\(Self.shellQuote(brewPath)) shellenv)"
            brew install gh && gh auth login --web --git-protocol https
            echo
            echo "Done. You can close this window and go back to Gary Tools."
            rm -f "$0"

            """
            do {
                try body.write(to: script, atomically: true, encoding: .utf8)
                try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
                NSWorkspace.shared.open(script)
                message = "Opened Terminal to install GitHub CLI (gh) via Homebrew and sign in."
            } catch {
                message = "Couldn’t open Terminal to install GitHub CLI: \(error.localizedDescription)"
            }
            return
        }

        if let url = URL(string: "https://cli.github.com") {
            NSWorkspace.shared.open(url)
        }
        message = "Opened cli.github.com. Install GitHub CLI (or Homebrew first), then return here."
    }

    func installHook(_ kind: AgentHookKind, dirs: [String]) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let localBin = home.appendingPathComponent(".local/bin", isDirectory: true)
        let symlinkURL = localBin.appendingPathComponent("dev-pull-all")

        let scriptPath: String
        if let bundledPath = Bundle.main.url(forResource: "dev-pull-all", withExtension: "sh")?.path,
           fm.fileExists(atPath: bundledPath) {
            do {
                try fm.createDirectory(at: localBin, withIntermediateDirectories: true)
                if fm.fileExists(atPath: symlinkURL.path) || (try? fm.attributesOfItem(atPath: symlinkURL.path)) != nil {
                    try fm.removeItem(at: symlinkURL)
                }
                try fm.createSymbolicLink(atPath: symlinkURL.path, withDestinationPath: bundledPath)
                scriptPath = symlinkURL.path
            } catch {
                // Fall back to invoking the bundled script directly if ~/.local/bin symlink couldn't be created.
                scriptPath = bundledPath
            }
        } else if fm.isExecutableFile(atPath: symlinkURL.path) {
            scriptPath = symlinkURL.path
        } else {
            message = "Couldn’t locate dev-pull-all.sh inside Gary Tools.app."
            return
        }

        let effectiveDirs = dirs.isEmpty ? [RepoSyncConfig.defaultFolder] : dirs
        do {
            try AgentHookManager.install(kind, scriptPath: scriptPath, dirs: effectiveDirs, home: home)
            hooks = AgentHookManager.allStatuses(home: home)
            message = "Installed \(kind.displayName) SessionStart hook."
        } catch {
            message = "Couldn’t install \(kind.displayName) hook: \(error.localizedDescription)"
        }
    }

    func uninstallHook(_ kind: AgentHookKind) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        do {
            try AgentHookManager.uninstall(kind, home: home)
            hooks = AgentHookManager.allStatuses(home: home)
            message = "Removed \(kind.displayName) SessionStart hook."
        } catch {
            message = "Couldn’t remove \(kind.displayName) hook: \(error.localizedDescription)"
        }
    }

    func detectedHooks() -> [AgentHookInfo] {
        hooks.filter { $0.clientDetected || $0.installed }
    }

    // MARK: - Helpers

    private nonisolated static func resolveGitExecutable() -> String? {
        let fm = FileManager.default
        for candidate in ["/opt/homebrew/bin/git", "/usr/local/bin/git"] {
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        // Only invoke /usr/bin/git when Command Line Tools are installed so macOS doesn't trigger an unexpected prompt.
        if DeveloperTools.commandLineToolsPath() != nil, fm.isExecutableFile(atPath: "/usr/bin/git") {
            return "/usr/bin/git"
        }
        return nil
    }

    private nonisolated static func resolveGHExecutable() -> String? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
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

    private nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
