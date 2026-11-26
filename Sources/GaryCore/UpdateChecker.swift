import Foundation

// MARK: - GitHub update checking

public struct UpdateInfo: Equatable, Sendable {
    public let currentCommit: String
    public let latestCommit: String
    public let commitsBehind: Int
    public let summaryLines: [String]
    public let compareURL: URL

    public init(
        currentCommit: String,
        latestCommit: String,
        commitsBehind: Int,
        summaryLines: [String],
        compareURL: URL
    ) {
        self.currentCommit = currentCommit
        self.latestCommit = latestCommit
        self.commitsBehind = commitsBehind
        self.summaryLines = summaryLines
        self.compareURL = compareURL
    }
}

public enum UpdateCheckOutcome: Equatable, Sendable {
    case upToDate(commit: String)
    case updateAvailable(UpdateInfo)
    case unknown(reason: String)
}

public enum UpdateParser {
    public static let repoOwner = "Nicegarrry"
    public static let repoName = "gary-tools"
    public static let defaultBranch = "main"

    public static func compareAPIURL(from currentCommit: String, branch: String = defaultBranch) -> URL {
        let base = encodedSegment(currentCommit.trimmingCharacters(in: .whitespacesAndNewlines))
        let head = encodedSegment(branch.trimmingCharacters(in: .whitespacesAndNewlines))
        return URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/compare/\(base)...\(head)")!
    }

    public static func latestCommitAPIURL(branch: String = defaultBranch) -> URL {
        let head = encodedSegment(branch.trimmingCharacters(in: .whitespacesAndNewlines))
        return URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/commits/\(head)")!
    }

    public static func parseGitHubCompareResponse(_ data: Data, currentCommit: String) throws -> UpdateCheckOutcome {
        let response = try JSONDecoder().decode(CompareResponse.self, from: data)
        let shortCurrent = shortSHA(currentCommit)

        if response.status == "identical" || response.status == "behind" || response.aheadBy <= 0 {
            return .upToDate(commit: shortCurrent)
        }

        let commits = response.commits ?? []
        let latestSHA = commits.last.map { shortSHA($0.sha) } ?? shortCurrent
        let summaries = commits.reversed().compactMap { firstLine(of: $0.commit.message) }.prefix(10)
        let fallbackURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/compare/\(shortCurrent)...\(defaultBranch)")!
        let compareURL = response.htmlURL.flatMap(URL.init(string:)) ?? fallbackURL

        return .updateAvailable(UpdateInfo(
            currentCommit: shortCurrent,
            latestCommit: latestSHA,
            commitsBehind: response.aheadBy,
            summaryLines: Array(summaries),
            compareURL: compareURL
        ))
    }

    public static func parseGitHubLatestCommitResponse(_ data: Data, currentCommit: String?) throws -> UpdateCheckOutcome {
        let response = try JSONDecoder().decode(LatestCommitResponse.self, from: data)
        let latestFull = response.sha.trimmingCharacters(in: .whitespacesAndNewlines)
        let latestShort = shortSHA(latestFull)
        let cleanedCurrent = currentCommit?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let current = cleanedCurrent, !current.isEmpty else {
            return .unknown(reason: "Installed commit is unknown (latest on GitHub: \(latestShort))")
        }

        let currentLower = current.lowercased()
        let latestLower = latestFull.lowercased()
        if latestLower.hasPrefix(currentLower) || currentLower.hasPrefix(latestLower) || shortSHA(current).lowercased() == latestShort.lowercased() {
            return .upToDate(commit: latestShort)
        }

        let summaries = firstLine(of: response.commit.message).map { [$0] } ?? []
        let fallbackURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/commits/\(defaultBranch)")!
        let compareURL = response.htmlURL.flatMap(URL.init(string:)) ?? fallbackURL

        return .updateAvailable(UpdateInfo(
            currentCommit: shortSHA(current),
            latestCommit: latestShort,
            commitsBehind: 1,
            summaryLines: summaries,
            compareURL: compareURL
        ))
    }

    private static func shortSHA(_ sha: String) -> String {
        let trimmed = sha.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(7))
    }

    private static func firstLine(of message: String) -> String? {
        for raw in message.components(separatedBy: .newlines) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func encodedSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private struct CompareResponse: Decodable {
        let status: String
        let aheadBy: Int
        let htmlURL: String?
        let commits: [CommitItem]?

        enum CodingKeys: String, CodingKey {
            case status
            case aheadBy = "ahead_by"
            case htmlURL = "html_url"
            case commits
        }
    }

    private struct CommitItem: Decodable {
        let sha: String
        let commit: CommitDetail
    }

    private struct LatestCommitResponse: Decodable {
        let sha: String
        let htmlURL: String?
        let commit: CommitDetail

        enum CodingKeys: String, CodingKey {
            case sha
            case htmlURL = "html_url"
            case commit
        }
    }

    private struct CommitDetail: Decodable {
        let message: String
    }
}

// MARK: - Local source checkout resolution

public enum UpdateSourceLocator {
    /// Resolves a local `gary-tools` git checkout containing `.git` and `update.sh`.
    /// Checks in order:
    /// 1. `<appSupportRoot>/source-repo.txt`
    /// 2. `<repo>` when `bundleURL` is `<repo>/dist/Gary Tools.app`
    /// 3. `<appSupportRoot>/source`
    public static func locateSourceRepo(
        appSupportRoot: URL = GaryToolsPaths.appSupportRoot,
        bundleURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        // 1. Explicit pointer recorded at install time
        let pointerFile = appSupportRoot.appendingPathComponent("source-repo.txt")
        if let raw = try? String(contentsOf: pointerFile, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let candidate = RepoSyncConfig.expand(trimmed)
                if isValidSourceRepo(candidate, fileManager: fileManager) {
                    return candidate
                }
            }
        }

        // 2. Running directly from <repo>/dist/Gary Tools.app
        if let bundleURL {
            let standardized = bundleURL.standardizedFileURL
            let parent = standardized.deletingLastPathComponent()
            if parent.lastPathComponent == "dist" {
                let repoCandidate = parent.deletingLastPathComponent()
                if isValidSourceRepo(repoCandidate, fileManager: fileManager) {
                    return repoCandidate
                }
            }
        }

        // 3. Default bootstrap clone location
        let defaultClone = appSupportRoot.appendingPathComponent("source", isDirectory: true)
        if isValidSourceRepo(defaultClone, fileManager: fileManager) {
            return defaultClone
        }

        return nil
    }

    private static func isValidSourceRepo(_ url: URL, fileManager: FileManager) -> Bool {
        let gitPath = url.appendingPathComponent(".git").path
        let updateScriptPath = url.appendingPathComponent("update.sh").path
        return fileManager.fileExists(atPath: gitPath) && fileManager.fileExists(atPath: updateScriptPath)
    }
}
