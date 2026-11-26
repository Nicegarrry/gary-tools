import Foundation

// MARK: - Multi-folder repository sync configuration

public enum RepoSyncConfig {
    public static let defaultFolder = "~/Developer"

    /// Parses colon-separated `AUTO_PULL_DIRS`, falling back to legacy `AUTO_PULL_DIR`, then `~/Developer`.
    /// Normalizes paths to `~/...` display form when under `home` and deduplicates preserving order.
    public static func parseDirs(
        autoPullDirs: String?,
        fallbackSingleDir: String?,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        if let raw = autoPullDirs {
            let parsed = normalize(raw.split(separator: ":").map(String.init), home: home)
            if !parsed.isEmpty { return parsed }
        }
        if let fallback = fallbackSingleDir {
            let parsed = normalize(fallback.split(separator: ":").map(String.init), home: home)
            if !parsed.isEmpty { return parsed }
        }
        return [defaultFolder]
    }

    /// Joins normalized, deduplicated non-empty paths with `:`.
    public static func serializeDirs(
        _ dirs: [String],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        normalize(dirs, home: home).joined(separator: ":")
    }

    /// Expands a path string (including `~` and `~/...`) into a standardized directory URL.
    public static func expand(
        _ path: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let standardHome = home.standardizedFileURL
        if trimmed == "~" {
            return standardHome
        }
        if trimmed.hasPrefix("~/") {
            let remainder = String(trimmed.dropFirst(2))
            if remainder.isEmpty { return standardHome }
            return standardHome.appendingPathComponent(remainder, isDirectory: true).standardizedFileURL
        }
        return URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL
    }

    /// Formats a URL under `home` as `~/...` (or `~` for `home` itself).
    public static func display(
        _ url: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        if path == homePath { return "~" }
        let prefix = homePath.hasSuffix("/") ? homePath : homePath + "/"
        if path.hasPrefix(prefix) {
            return "~/" + path.dropFirst(prefix.count)
        }
        return path
    }

    /// Counts unique git repositories across `dirs` matching `dev-pull-all.sh` discovery:
    /// - depth 0: `dir/.git` (if the folder itself is a repo, count it and do not descend)
    /// - depth 1: `dir/*/.git` (direct child repo; do not descend further)
    /// - depth 2: `dir/*/*/.git` (one grouping subfolder deep)
    public static func countGitRepos(
        in dirs: [String],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Int {
        let fm = FileManager.default
        var seen: Set<String> = []

        func isDirectory(_ url: URL) -> Bool {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }

        func hasGitMarker(_ url: URL) -> Bool {
            fm.fileExists(atPath: url.appendingPathComponent(".git").path)
        }

        func canonicalKey(_ url: URL) -> String {
            url.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
        }

        func childDirectories(of url: URL) -> [URL] {
            guard let items = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }
            return items.filter { isDirectory($0) }
        }

        for raw in dirs {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let root = expand(trimmed, home: home)
            guard isDirectory(root) else { continue }

            // Depth 0: folder itself is a git repo
            if hasGitMarker(root) {
                seen.insert(canonicalKey(root))
                continue
            }

            // Depth 1 & Depth 2
            for child in childDirectories(of: root) {
                if hasGitMarker(child) {
                    seen.insert(canonicalKey(child))
                } else {
                    for grandchild in childDirectories(of: child) {
                        if hasGitMarker(grandchild) {
                            seen.insert(canonicalKey(grandchild))
                        }
                    }
                }
            }
        }

        return seen.count
    }

    private static func normalize(_ rawDirs: [String], home: URL) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []

        for raw in rawDirs {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let expanded = expand(trimmed, home: home)
            let dedupKey = expanded.standardizedFileURL.path.lowercased()
            guard seen.insert(dedupKey).inserted else { continue }
            result.append(display(expanded, home: home))
        }

        return result
    }
}

// MARK: - Coding agent SessionStart hooks

public enum AgentHookKind: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case antigravity

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .antigravity: return "Antigravity"
        }
    }

    public func configURL(home: URL) -> URL {
        switch self {
        case .antigravity:
            return home.appendingPathComponent(".gemini/config/hooks.json")
        case .claude:
            return home.appendingPathComponent(".claude/hooks/dev-pull-all.sh")
        case .codex:
            return home.appendingPathComponent(".codex/hooks.json")
        }
    }

    public func isClientInstalled(home: URL) -> Bool {
        isClientInstalled(home: home, includeSystemPaths: true)
    }

    internal func isClientInstalled(home: URL, includeSystemPaths: Bool) -> Bool {
        let fm = FileManager.default
        let homeCandidates: [URL]
        let systemCandidates: [String]

        switch self {
        case .claude:
            homeCandidates = [
                home.appendingPathComponent(".claude"),
                home.appendingPathComponent(".local/bin/claude"),
            ]
            systemCandidates = [
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude",
            ]
        case .codex:
            homeCandidates = [
                home.appendingPathComponent(".codex"),
                home.appendingPathComponent(".local/bin/codex"),
            ]
            systemCandidates = [
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
                "/Applications/Codex.app",
            ]
        case .antigravity:
            homeCandidates = [
                home.appendingPathComponent(".gemini"),
                home.appendingPathComponent(".local/bin/agy"),
            ]
            systemCandidates = [
                "/Applications/Antigravity.app",
                "/opt/homebrew/bin/agy",
                "/usr/local/bin/agy",
            ]
        }

        if homeCandidates.contains(where: { fm.fileExists(atPath: $0.path) }) {
            return true
        }
        if includeSystemPaths && systemCandidates.contains(where: { fm.fileExists(atPath: $0) }) {
            return true
        }
        return false
    }
}

public struct AgentHookInfo: Identifiable, Equatable, Sendable {
    public let kind: AgentHookKind
    public var id: String { kind.rawValue }
    public let installed: Bool
    public let clientDetected: Bool
    public let path: String

    public init(kind: AgentHookKind, installed: Bool, clientDetected: Bool, path: String) {
        self.kind = kind
        self.installed = installed
        self.clientDetected = clientDetected
        self.path = path
    }
}

public enum AgentHookError: Error, LocalizedError, Equatable {
    case invalidJSON(URL)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let url):
            return "Could not parse JSON object at \(url.path)"
        }
    }
}

public enum AgentHookManager {
    private static let marker = "dev-pull-all"

    public static func status(
        for kind: AgentHookKind,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> AgentHookInfo {
        let url = kind.configURL(home: home)
        let installed: Bool
        switch kind {
        case .claude:
            installed = isClaudeHookInstalled(home: home)
        case .antigravity:
            installed = isAntigravityHookInstalled(url: url)
        case .codex:
            installed = isCodexHookInstalled(url: url)
        }

        return AgentHookInfo(
            kind: kind,
            installed: installed,
            clientDetected: kind.isClientInstalled(home: home),
            path: url.path
        )
    }

    public static func allStatuses(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [AgentHookInfo] {
        AgentHookKind.allCases.map { status(for: $0, home: home) }
    }

    public static func install(
        _ kind: AgentHookKind,
        scriptPath: String,
        dirs: [String],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws {
        let serialized = RepoSyncConfig.serializeDirs(dirs, home: home)
        let dirsArg = serialized.isEmpty ? RepoSyncConfig.defaultFolder : serialized

        switch kind {
        case .claude:
            try installClaude(scriptPath: scriptPath, dirsArg: dirsArg, home: home)
        case .antigravity:
            try installAntigravity(scriptPath: scriptPath, dirsArg: dirsArg, home: home)
        case .codex:
            try installCodex(scriptPath: scriptPath, dirsArg: dirsArg, home: home)
        }
    }

    public static func uninstall(
        _ kind: AgentHookKind,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws {
        switch kind {
        case .claude:
            try uninstallClaude(home: home)
        case .antigravity:
            try uninstallAntigravity(home: home)
        case .codex:
            try uninstallCodex(home: home)
        }
    }

    // MARK: - Claude Code

    private static func claudeSettingsURL(home: URL) -> URL {
        home.appendingPathComponent(".claude/settings.json")
    }

    private static func isClaudeHookInstalled(home: URL) -> Bool {
        let fm = FileManager.default
        let scriptURL = AgentHookKind.claude.configURL(home: home)
        let settingsURL = claudeSettingsURL(home: home)

        let scriptExists = fm.fileExists(atPath: scriptURL.path)
            && ((try? String(contentsOf: scriptURL, encoding: .utf8))?.contains(marker) ?? false)

        if let root = try? readJSONObjectIfExists(at: settingsURL),
           let hooks = root["hooks"] as? [String: Any],
           let sessionStart = hooks["SessionStart"] as? [[String: Any]] {
            let matchingCommands = extractSessionStartCommands(from: sessionStart).filter { $0.contains(marker) }
            if !matchingCommands.isEmpty {
                // If settings points at our wrapper script, ensure the wrapper script exists too.
                if matchingCommands.allSatisfy({ $0.contains(".claude/hooks/dev-pull-all.sh") }) {
                    return scriptExists
                }
                return true
            }
        }
        return false
    }

    private static func installClaude(scriptPath: String, dirsArg: String, home: URL) throws {
        let fm = FileManager.default
        let wrapperURL = AgentHookKind.claude.configURL(home: home)
        try fm.createDirectory(at: wrapperURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let scriptBody = """
        #!/bin/bash
        exec \(doubleQuote(scriptPath)) --format plain --dirs \(doubleQuote(dirsArg)) "$@"
        """ + "\n"
        try scriptBody.write(to: wrapperURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperURL.path)

        let settingsURL = claudeSettingsURL(home: home)
        var root = try readJSONObjectIfExists(at: settingsURL) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var sessionStart = hooks["SessionStart"] as? [[String: Any]] ?? []

        let alreadyRegistered = extractSessionStartCommands(from: sessionStart).contains { $0.contains(marker) }
        if !alreadyRegistered {
            let newEntry: [String: Any] = [
                "matcher": "startup",
                "hooks": [
                    [
                        "type": "command",
                        "command": "bash \(singleQuote(wrapperURL.path))",
                        "timeout": 90,
                        "statusMessage": "Pulling Developer repos...",
                    ] as [String: Any]
                ],
            ]
            sessionStart.append(newEntry)
            hooks["SessionStart"] = sessionStart
            root["hooks"] = hooks
            try writeJSONObject(root, to: settingsURL)
        }
    }

    private static func uninstallClaude(home: URL) throws {
        let fm = FileManager.default
        let wrapperURL = AgentHookKind.claude.configURL(home: home)
        if fm.fileExists(atPath: wrapperURL.path) {
            try fm.removeItem(at: wrapperURL)
        }

        let settingsURL = claudeSettingsURL(home: home)
        guard var root = try readJSONObjectIfExists(at: settingsURL) else { return }
        guard var hooks = root["hooks"] as? [String: Any],
              let sessionStart = hooks["SessionStart"] as? [[String: Any]] else {
            return
        }

        let (filtered, changed) = removeMarkerEntries(from: sessionStart)
        guard changed else { return }

        if filtered.isEmpty {
            hooks.removeValue(forKey: "SessionStart")
        } else {
            hooks["SessionStart"] = filtered
        }
        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        try writeJSONObject(root, to: settingsURL)
    }

    // MARK: - Antigravity

    private static func isAntigravityHookInstalled(url: URL) -> Bool {
        guard let root = try? readJSONObjectIfExists(at: url) else { return false }
        for (_, value) in root {
            if let group = value as? [String: Any],
               let sessionStart = group["SessionStart"] as? [[String: Any]],
               extractSessionStartCommands(from: sessionStart).contains(where: { $0.contains(marker) }) {
                return true
            }
        }
        return false
    }

    private static func installAntigravity(scriptPath: String, dirsArg: String, home: URL) throws {
        let url = AgentHookKind.antigravity.configURL(home: home)
        var root = try readJSONObjectIfExists(at: url) ?? [:]
        let command = "\(doubleQuote(scriptPath)) --format antigravity --dirs \(doubleQuote(dirsArg))"

        // If an existing group already contains a dev-pull-all SessionStart entry, update it in place.
        var updatedInPlace = false
        for (key, value) in root {
            guard var group = value as? [String: Any],
                  let sessionStart = group["SessionStart"] as? [[String: Any]] else {
                continue
            }
            let (updated, didUpdate) = updateMarkerCommand(in: sessionStart, to: command)
            if didUpdate {
                group["SessionStart"] = updated
                root[key] = group
                updatedInPlace = true
                break
            }
        }

        if !updatedInPlace {
            var group = root[marker] as? [String: Any] ?? [:]
            var sessionStart = group["SessionStart"] as? [[String: Any]] ?? []
            sessionStart.append([
                "type": "command",
                "command": command,
                "timeout": 90,
            ])
            group["SessionStart"] = sessionStart
            root[marker] = group
        }

        try writeJSONObject(root, to: url)
    }

    private static func uninstallAntigravity(home: URL) throws {
        let url = AgentHookKind.antigravity.configURL(home: home)
        guard var root = try readJSONObjectIfExists(at: url) else { return }

        var anyChanged = false
        for key in Array(root.keys) {
            guard var group = root[key] as? [String: Any],
                  let sessionStart = group["SessionStart"] as? [[String: Any]] else {
                continue
            }
            let (filtered, changed) = removeMarkerEntries(from: sessionStart)
            guard changed else { continue }
            anyChanged = true
            if filtered.isEmpty {
                group.removeValue(forKey: "SessionStart")
            } else {
                group["SessionStart"] = filtered
            }
            if group.isEmpty {
                root.removeValue(forKey: key)
            } else {
                root[key] = group
            }
        }

        if anyChanged {
            try writeJSONObject(root, to: url)
        }
    }

    // MARK: - Codex

    private static func isCodexHookInstalled(url: URL) -> Bool {
        guard let root = try? readJSONObjectIfExists(at: url),
              let hooks = root["hooks"] as? [String: Any],
              let sessionStart = hooks["SessionStart"] as? [[String: Any]] else {
            return false
        }
        return extractSessionStartCommands(from: sessionStart).contains { $0.contains(marker) }
    }

    private static func installCodex(scriptPath: String, dirsArg: String, home: URL) throws {
        let url = AgentHookKind.codex.configURL(home: home)
        var root = try readJSONObjectIfExists(at: url) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let sessionStart = hooks["SessionStart"] as? [[String: Any]] ?? []
        let command = "\(doubleQuote(scriptPath)) --format plain --dirs \(doubleQuote(dirsArg))"

        let (updated, didUpdate) = updateMarkerCommand(in: sessionStart, to: command)
        if didUpdate {
            hooks["SessionStart"] = updated
        } else {
            var next = sessionStart
            next.append([
                "hooks": [
                    [
                        "type": "command",
                        "command": command,
                        "timeout": 90,
                    ] as [String: Any]
                ]
            ])
            hooks["SessionStart"] = next
        }

        root["hooks"] = hooks
        try writeJSONObject(root, to: url)
    }

    private static func uninstallCodex(home: URL) throws {
        let url = AgentHookKind.codex.configURL(home: home)
        guard var root = try readJSONObjectIfExists(at: url),
              var hooks = root["hooks"] as? [String: Any],
              let sessionStart = hooks["SessionStart"] as? [[String: Any]] else {
            return
        }

        let (filtered, changed) = removeMarkerEntries(from: sessionStart)
        guard changed else { return }

        if filtered.isEmpty {
            hooks.removeValue(forKey: "SessionStart")
        } else {
            hooks["SessionStart"] = filtered
        }
        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        try writeJSONObject(root, to: url)
    }

    // MARK: - JSON & shell helpers

    private static func extractSessionStartCommands(from entries: [[String: Any]]) -> [String] {
        var commands: [String] = []
        for entry in entries {
            if let cmd = entry["command"] as? String {
                commands.append(cmd)
            }
            if let nested = entry["hooks"] as? [[String: Any]] {
                for item in nested {
                    if let cmd = item["command"] as? String {
                        commands.append(cmd)
                    }
                }
            }
        }
        return commands
    }

    private static func updateMarkerCommand(in entries: [[String: Any]], to newCommand: String) -> ([[String: Any]], Bool) {
        var updated = entries
        var didUpdate = false

        for idx in updated.indices {
            if let cmd = updated[idx]["command"] as? String, cmd.contains(marker) {
                updated[idx]["command"] = newCommand
                didUpdate = true
                continue
            }
            if var nested = updated[idx]["hooks"] as? [[String: Any]] {
                var nestedUpdated = false
                for j in nested.indices {
                    if let cmd = nested[j]["command"] as? String, cmd.contains(marker) {
                        nested[j]["command"] = newCommand
                        nestedUpdated = true
                        didUpdate = true
                    }
                }
                if nestedUpdated {
                    updated[idx]["hooks"] = nested
                }
            }
        }

        return (updated, didUpdate)
    }

    private static func removeMarkerEntries(from entries: [[String: Any]]) -> ([[String: Any]], Bool) {
        var result: [[String: Any]] = []
        var changed = false

        for entry in entries {
            if let cmd = entry["command"] as? String, cmd.contains(marker) {
                changed = true
                continue
            }
            if let nested = entry["hooks"] as? [[String: Any]] {
                let remaining = nested.filter { item in
                    guard let cmd = item["command"] as? String else { return true }
                    return !cmd.contains(marker)
                }
                if remaining.count != nested.count {
                    changed = true
                    if remaining.isEmpty {
                        continue
                    }
                    var copy = entry
                    copy["hooks"] = remaining
                    result.append(copy)
                    continue
                }
            }
            result.append(entry)
        }

        return (result, changed)
    }

    private static func readJSONObjectIfExists(at url: URL) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        guard let parsed = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw AgentHookError.invalidJSON(url)
        }
        return parsed
    }

    private static func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
        if #available(macOS 10.15, *) {
            options.insert(.withoutEscapingSlashes)
        }
        var data = try JSONSerialization.data(withJSONObject: object, options: options)
        data.append(0x0A) // trailing newline
        try data.write(to: url, options: .atomic)
    }

    private static func doubleQuote(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count + 2)
        escaped.append("\"")
        for ch in value {
            switch ch {
            case "\\", "\"", "$", "`":
                escaped.append("\\")
                escaped.append(ch)
            default:
                escaped.append(ch)
            }
        }
        escaped.append("\"")
        return escaped
    }

    private static func singleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
