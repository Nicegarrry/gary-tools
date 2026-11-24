import Foundation

/// Everything Context Grab knows about one capture, rendered as a paste-ready block for an agent.
public struct ContextPack: Equatable {
    public var appName: String
    public var bundleID: String
    public var windowTitle: String
    public var url: String?
    public var repo: RepoContext?
    public var text: String
    public var imagePath: String?
    public var capturedAt: Date

    public init(appName: String, bundleID: String = "", windowTitle: String = "", url: String? = nil,
                repo: RepoContext? = nil, text: String = "", imagePath: String? = nil, capturedAt: Date = Date()) {
        self.appName = appName; self.bundleID = bundleID; self.windowTitle = windowTitle; self.url = url
        self.repo = repo; self.text = text; self.imagePath = imagePath; self.capturedAt = capturedAt
    }

    /// Lines in the captured text that look like errors, in order, without duplicates.
    public var errorLines: [String] { ContextGrab.errorLines(in: text) }

    /// Markdown an agent can read: where it came from, any errors, the screenshot path, then the text.
    public func markdown(home: String = NSHomeDirectory()) -> String {
        var lines = ["## Context from \(appName.isEmpty ? "screen" : appName)"]
        var source: [String] = []
        if !windowTitle.isEmpty { source.append("- Window: \(windowTitle)") }
        if let url, !url.isEmpty { source.append("- URL: \(url)") }
        if let repo {
            let branch = repo.branch.map { " (branch `\($0)`)" } ?? ""
            source.append("- Repo: `\(ContextGrab.abbreviate(repo.path, home: home))`\(branch)")
        }
        if let imagePath { source.append("- Screenshot: `\(imagePath)`") }
        source.append("- Captured: \(ContextGrab.timestamp(capturedAt))")
        lines.append(contentsOf: source)

        let errors = errorLines
        if !errors.isEmpty {
            lines.append("")
            lines.append("### Errors on screen")
            lines.append("```")
            lines.append(contentsOf: errors)
            lines.append("```")
        }

        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            lines.append("")
            lines.append("### Text on screen")
            lines.append("```")
            lines.append(body.replacingOccurrences(of: "```", with: "ʼʼʼ"))
            lines.append("```")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

public struct RepoContext: Equatable {
    public var path: String
    public var branch: String?
    public init(path: String, branch: String?) { self.path = path; self.branch = branch }
}

public enum ContextGrab {
    /// Words that mark a line of on-screen text as an error worth surfacing first.
    static let errorMarkers = [
        "error", "exception", "traceback", "panic", "fatal", "failed", "failure",
        "segmentation fault", "uncaught", "undefined is not", "cannot find", "not found", "denied", "✗", "✘",
    ]

    public static func errorLines(in text: String, limit: Int = 12) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.count >= 4, line.count <= 400 else { continue }
            let lower = line.lowercased()
            guard errorMarkers.contains(where: { lower.contains($0) }) else { continue }
            // "0 errors" / "no errors" are good news, not errors.
            if lower.range(of: #"\b(0|no|zero) (errors?|failures?)\b"#, options: .regularExpression) != nil { continue }
            guard seen.insert(line).inserted else { continue }
            result.append(line)
            if result.count == limit { break }
        }
        return result
    }

    /// Finds the git repo a window is showing, from its title.
    /// Terminals and editors put a path ("~/Developer/app — zsh") or a folder name ("main.swift — app") in the title.
    public static func repo(fromWindowTitle title: String, developerDir: String, home: String = NSHomeDirectory(),
                            fileManager: FileManager = .default) -> RepoContext? {
        guard !title.isEmpty else { return nil }
        let devDir = expand(developerDir, home: home)

        // 1. Explicit paths in the title, longest first.
        for path in pathCandidates(in: title, home: home) {
            if let root = gitRoot(containing: path, fileManager: fileManager) {
                return RepoContext(path: root, branch: branch(atRepo: root, fileManager: fileManager))
            }
        }

        // 2. Folder names matched against the developer folder (top level and one grouping folder deep, like Repo Sync).
        let names = title
            .components(separatedBy: CharacterSet(charactersIn: "—–|:·()[]").union(.newlines))
            .flatMap { $0.components(separatedBy: " - ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("/") && $0.count <= 100 }
        let groups = ((try? fileManager.contentsOfDirectory(atPath: devDir)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted()
        for name in names {
            var candidates = ["\(devDir)/\(name)"]
            candidates += groups.map { "\(devDir)/\($0)/\(name)" }
            for candidate in candidates where isGitRepo(candidate, fileManager: fileManager) {
                return RepoContext(path: candidate, branch: branch(atRepo: candidate, fileManager: fileManager))
            }
        }
        return nil
    }

    /// The checked-out branch, read from `.git/HEAD` (worktrees point `.git` at their own git dir).
    public static func branch(atRepo repo: String, fileManager: FileManager = .default) -> String? {
        guard let gitDir = gitDir(forRepo: repo, fileManager: fileManager),
              let head = try? String(contentsOfFile: "\(gitDir)/HEAD", encoding: .utf8)
        else { return nil }
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "ref: refs/heads/"
        if trimmed.hasPrefix(prefix) { return String(trimmed.dropFirst(prefix.count)) }
        return trimmed.isEmpty ? nil : "detached at \(trimmed.prefix(7))"
    }

    /// Keeps the newest `keep` captures in `directory` and deletes older ones. Only touches `.png` files Context Grab named.
    @discardableResult
    public static func pruneCaptures(in directory: URL, keep: Int, fileManager: FileManager = .default) -> Int {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return 0 }
        let captures = files
            .filter { $0.lastPathComponent.hasPrefix(capturePrefix) && $0.pathExtension == "png" }
            .sorted { modified($0) > modified($1) }
        var removed = 0
        for url in captures.dropFirst(max(0, keep)) where (try? fileManager.removeItem(at: url)) != nil { removed += 1 }
        return removed
    }

    public static let capturePrefix = "grab-"

    public static func captureFileName(at date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return "\(capturePrefix)\(f.string(from: date)).png"
    }

    // MARK: - Helpers

    static func timestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    static func expand(_ path: String, home: String) -> String {
        var p = path
        if p == "~" { p = home } else if p.hasPrefix("~/") { p = home + String(p.dropFirst(1)) }
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    static func abbreviate(_ path: String, home: String) -> String {
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + String(path.dropFirst(home.count)) : path
    }

    static func pathCandidates(in title: String, home: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(~|/)[^\s:—–|'"`]*"#) else { return [] }
        let ns = title as NSString
        return regex.matches(in: title, range: NSRange(location: 0, length: ns.length))
            .map { expand(ns.substring(with: $0.range), home: home) }
            .filter { $0.count > 1 }
            .sorted { $0.count > $1.count }
    }

    /// Walks up from `path` to the nearest folder holding `.git`, stopping at the filesystem root.
    static func gitRoot(containing path: String, fileManager: FileManager) -> String? {
        var current = URL(fileURLWithPath: path).standardizedFileURL
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: current.path, isDirectory: &isDir), !isDir.boolValue {
            current.deleteLastPathComponent()
        }
        for _ in 0..<40 {
            if isGitRepo(current.path, fileManager: fileManager) { return current.path }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
        return nil
    }

    static func isGitRepo(_ path: String, fileManager: FileManager) -> Bool {
        fileManager.fileExists(atPath: "\(path)/.git")
    }

    static func gitDir(forRepo repo: String, fileManager: FileManager) -> String? {
        let dotGit = "\(repo)/.git"
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: dotGit, isDirectory: &isDir) else { return nil }
        if isDir.boolValue { return dotGit }
        guard let contents = try? String(contentsOfFile: dotGit, encoding: .utf8),
              let line = contents.components(separatedBy: .newlines).first(where: { $0.hasPrefix("gitdir:") })
        else { return nil }
        let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        return target.hasPrefix("/") ? target : "\(repo)/\(target)"
    }

    static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
