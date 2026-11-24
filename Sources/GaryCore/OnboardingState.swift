import Foundation

// MARK: - First-run onboarding detection

public enum OnboardingDetector {
    public static let completedKey = "garyTools.onboardingCompleted.v1"
    public static let freshInstallMarker = ".fresh_install"

    /// Shows onboarding only for genuinely fresh installs:
    /// - `false` if already completed in `defaults`
    /// - `true` if `install.sh` marked a fresh install via `.fresh_install`
    /// - `false` if `settings.conf` or `Clipboard/library.json` already exists under `appSupportRoot`
    /// - `true` otherwise
    public static func shouldShowOnLaunch(
        appSupportRoot: URL = GaryToolsPaths.appSupportRoot,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> Bool {
        if defaults.bool(forKey: completedKey) {
            return false
        }
        let freshMarkerPath = appSupportRoot.appendingPathComponent(freshInstallMarker).path
        if fileManager.fileExists(atPath: freshMarkerPath) {
            return true
        }
        let settingsPath = appSupportRoot.appendingPathComponent("settings.conf").path
        if fileManager.fileExists(atPath: settingsPath) {
            return false
        }
        let libraryPath = appSupportRoot.appendingPathComponent("Clipboard/library.json").path
        if fileManager.fileExists(atPath: libraryPath) {
            return false
        }
        return true
    }

    public static func markCompleted(
        appSupportRoot: URL = GaryToolsPaths.appSupportRoot,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        defaults.set(true, forKey: completedKey)
        try? fileManager.removeItem(at: appSupportRoot.appendingPathComponent(freshInstallMarker))
    }

    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: completedKey)
    }
}

// MARK: - Git & GitHub environment status

public struct GitSetupStatus: Equatable, Sendable {
    public var gitInstalled: Bool
    public var userName: String
    public var userEmail: String
    public var ghInstalled: Bool
    public var ghAccount: String?
    public var sshKeyNames: [String]

    public init(
        gitInstalled: Bool = false,
        userName: String = "",
        userEmail: String = "",
        ghInstalled: Bool = false,
        ghAccount: String? = nil,
        sshKeyNames: [String] = []
    ) {
        self.gitInstalled = gitInstalled
        self.userName = userName
        self.userEmail = userEmail
        self.ghInstalled = ghInstalled
        self.ghAccount = ghAccount
        self.sshKeyNames = sshKeyNames
    }

    public var hasIdentity: Bool {
        !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !userEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var hasGitHubAuth: Bool {
        let hasGH = ghAccount.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        return hasGH || !sshKeyNames.isEmpty
    }

    public var isReady: Bool {
        gitInstalled && hasIdentity && hasGitHubAuth
    }
}

public enum GitEnvironmentParser {
    /// Parses `gh auth status` output and returns the active (or first) logged-in GitHub account name.
    public static func parseGHAuthAccount(from output: String) -> String? {
        let cleaned = stripANSI(output)
        let lines = cleaned.components(separatedBy: .newlines)

        var firstAccount: String?
        var lastSeenAccount: String?

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if let account = extractLoggedInAccount(from: line) {
                if firstAccount == nil {
                    firstAccount = account
                }
                lastSeenAccount = account
                continue
            }

            if let candidate = lastSeenAccount {
                let lower = line.lowercased()
                if lower.contains("active account:") {
                    if lower.contains("true") {
                        return candidate
                    }
                    lastSeenAccount = nil
                }
            }
        }

        return firstAccount
    }

    /// Lists `*.pub` public key filenames in `sshDir`, sorted alphabetically.
    public static func findSSHKeyNames(
        in sshDir: URL,
        fileManager: FileManager = .default
    ) -> [String] {
        guard let items = try? fileManager.contentsOfDirectory(
            at: sshDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return items
            .filter { url in
                guard url.pathExtension.lowercased() == "pub" else { return false }
                var isDir: ObjCBool = false
                return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
            }
            .map(\.lastPathComponent)
            .sorted()
    }

    private static func extractLoggedInAccount(from line: String) -> String? {
        // Matches:
        //   "✓ Logged in to github.com account Nicegarrry (keyring)"
        //   "✓ Logged in to github.com as Nicegarrry (/Users/np/.config/gh/hosts.yml)"
        //   "Logged in to github.com account octocat"
        let pattern = #"(?i)logged\s+in\s+to\s+\S+\s+(?:account|as)\s+([^\s()]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 2,
              let accountRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        let account = String(line[accountRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()\"'"))
        return account.isEmpty ? nil : account
    }

    private static func stripANSI(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\u{001B}\[[0-9;]*[A-Za-z]"#, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
}
