import XCTest
@testable import GaryCore

final class ShareableSetupTests: XCTestCase {
    private var tempDirs: [URL] = []

    override func tearDown() {
        for dir in tempDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDirs.removeAll()
        super.tearDown()
    }

    private func makeTempDir(_ prefix: String = "gary-shareable") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        return dir
    }

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suite = "gary.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
        }
        return (defaults, suite)
    }

    // MARK: - RepoSyncConfig Tests

    func testExpandAndDisplayPaths() {
        let home = URL(fileURLWithPath: "/Users/alice", isDirectory: true)

        XCTAssertEqual(RepoSyncConfig.expand("~", home: home).path, "/Users/alice")
        XCTAssertEqual(RepoSyncConfig.expand("~/Developer", home: home).path, "/Users/alice/Developer")
        XCTAssertEqual(RepoSyncConfig.expand("~/Developer/sub/", home: home).path, "/Users/alice/Developer/sub")
        XCTAssertEqual(RepoSyncConfig.expand("/Volumes/Code/Repos", home: home).path, "/Volumes/Code/Repos")

        XCTAssertEqual(RepoSyncConfig.display(home, home: home), "~")
        XCTAssertEqual(RepoSyncConfig.display(URL(fileURLWithPath: "/Users/alice/Developer"), home: home), "~/Developer")
        XCTAssertEqual(RepoSyncConfig.display(URL(fileURLWithPath: "/Users/alice2/Developer"), home: home), "/Users/alice2/Developer")
        XCTAssertEqual(RepoSyncConfig.display(URL(fileURLWithPath: "/opt/work"), home: home), "/opt/work")
    }

    func testParseDirsFallbacksNormalizationAndDedup() {
        let home = URL(fileURLWithPath: "/Users/alice", isDirectory: true)

        // Both nil -> defaultFolder
        XCTAssertEqual(
            RepoSyncConfig.parseDirs(autoPullDirs: nil, fallbackSingleDir: nil, home: home),
            ["~/Developer"]
        )

        // Empty autoPullDirs falls back to fallbackSingleDir
        XCTAssertEqual(
            RepoSyncConfig.parseDirs(autoPullDirs: "  :: ", fallbackSingleDir: "/Users/alice/Projects", home: home),
            ["~/Projects"]
        )

        // Empty both falls back to defaultFolder
        XCTAssertEqual(
            RepoSyncConfig.parseDirs(autoPullDirs: "", fallbackSingleDir: "  ", home: home),
            ["~/Developer"]
        )

        // Colon-separated parsing, tilde normalization, case-insensitive dedup preserving order
        let parsed = RepoSyncConfig.parseDirs(
            autoPullDirs: " ~/Developer : /Users/alice/developer/ : /Volumes/Work :: ~/Code : /Users/alice/Code/../Developer ",
            fallbackSingleDir: "~/Ignored",
            home: home
        )
        XCTAssertEqual(parsed, ["~/Developer", "/Volumes/Work", "~/Code"])
    }

    func testSerializeDirsNormalizesAndDeduplicates() {
        let home = URL(fileURLWithPath: "/Users/alice", isDirectory: true)
        let serialized = RepoSyncConfig.serializeDirs(
            ["/Users/alice/Developer", "", " ~/developer/ ", "/Volumes/Projects", "~/Work"],
            home: home
        )
        XCTAssertEqual(serialized, "~/Developer:/Volumes/Projects:~/Work")
    }

    func testCountGitReposDepthZeroOneTwoAndDedup() throws {
        let home = try makeTempDir("repo-count")
        let fm = FileManager.default

        func makeRepo(_ relativePath: String, gitAsFile: Bool = false) throws {
            let repoDir = home.appendingPathComponent(relativePath, isDirectory: true)
            try fm.createDirectory(at: repoDir, withIntermediateDirectories: true)
            let gitURL = repoDir.appendingPathComponent(".git")
            if gitAsFile {
                try "gitdir: /tmp/fake\n".write(to: gitURL, atomically: true, encoding: .utf8)
            } else {
                try fm.createDirectory(at: gitURL, withIntermediateDirectories: true)
            }
        }

        // Depth 0: direct repo folder (contains nested repo that should NOT be counted)
        try makeRepo("SoloRepo")
        try makeRepo("SoloRepo/NestedIgnored")

        // Depth 1: direct child repo (and a nested submodule/repo inside it that should NOT be counted)
        try makeRepo("Dev/app-one")
        try makeRepo("Dev/app-one/nested-ignored")
        // Depth 1 worktree (.git file)
        try makeRepo("Dev/app-worktree", gitAsFile: true)

        // Depth 2: grouping subfolder
        try makeRepo("Dev/local/gary-tools")
        try makeRepo("Dev/local/other-tool")

        // Depth 3: too deep, should NOT be counted
        try makeRepo("Dev/group/sub/too-deep")

        // Hidden folder should NOT be counted
        try makeRepo("Dev/.hidden-repo")

        // Non-repo folder
        try fm.createDirectory(at: home.appendingPathComponent("Dev/notes"), withIntermediateDirectories: true)

        // Symlink duplicate pointing to Dev/app-one
        let aliasDir = home.appendingPathComponent("AliasRoot", isDirectory: true)
        try fm.createDirectory(at: aliasDir, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            at: aliasDir.appendingPathComponent("app-one-link"),
            withDestinationURL: home.appendingPathComponent("Dev/app-one")
        )

        let count = RepoSyncConfig.countGitRepos(
            in: ["~/SoloRepo", "~/Dev", "~/AliasRoot", "~/DoesNotExist"],
            home: home
        )
        // SoloRepo (1) + Dev/app-one (2) + Dev/app-worktree (3) + Dev/local/gary-tools (4) + Dev/local/other-tool (5)
        // AliasRoot/app-one-link deduplicates against Dev/app-one
        XCTAssertEqual(count, 5)
    }

    // MARK: - AgentHookKind & AgentHookManager Tests

    func testAgentHookKindConfigURLsAndDisplayNames() {
        let home = URL(fileURLWithPath: "/Users/alice", isDirectory: true)

        XCTAssertEqual(AgentHookKind.claude.displayName, "Claude Code")
        XCTAssertEqual(AgentHookKind.codex.displayName, "Codex")
        XCTAssertEqual(AgentHookKind.antigravity.displayName, "Antigravity")

        XCTAssertEqual(AgentHookKind.antigravity.configURL(home: home).path, "/Users/alice/.gemini/config/hooks.json")
        XCTAssertEqual(AgentHookKind.claude.configURL(home: home).path, "/Users/alice/.claude/hooks/dev-pull-all.sh")
        XCTAssertEqual(AgentHookKind.codex.configURL(home: home).path, "/Users/alice/.codex/hooks.json")
    }

    func testClientInstalledDetectionInIsolatedHome() throws {
        let home = try makeTempDir("client-detect")
        let fm = FileManager.default

        XCTAssertFalse(AgentHookKind.claude.isClientInstalled(home: home, includeSystemPaths: false))
        XCTAssertFalse(AgentHookKind.codex.isClientInstalled(home: home, includeSystemPaths: false))
        XCTAssertFalse(AgentHookKind.antigravity.isClientInstalled(home: home, includeSystemPaths: false))

        try fm.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent(".gemini"), withIntermediateDirectories: true)

        XCTAssertTrue(AgentHookKind.claude.isClientInstalled(home: home, includeSystemPaths: false))
        XCTAssertTrue(AgentHookKind.codex.isClientInstalled(home: home, includeSystemPaths: false))
        XCTAssertTrue(AgentHookKind.antigravity.isClientInstalled(home: home, includeSystemPaths: false))
    }

    func testClaudeInstallPreservesSettingsIsIdempotentAndUninstallsCleanly() throws {
        let home = try makeTempDir("hook-claude")
        let fm = FileManager.default
        let settingsURL = home.appendingPathComponent(".claude/settings.json")
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Pre-populate user settings with another SessionStart hook and unrelated keys
        let existingSettings: [String: Any] = [
            "theme": "dark",
            "permissions": ["defaultMode": "auto"],
            "hooks": [
                "SessionStart": [
                    [
                        "matcher": "startup",
                        "hooks": [
                            ["type": "command", "command": "/usr/local/bin/other-hook", "timeout": 10]
                        ],
                    ]
                ],
                "Stop": [
                    ["hooks": [["type": "command", "command": "/usr/local/bin/stop-hook"]]]
                ],
            ],
        ]
        let existingData = try JSONSerialization.data(withJSONObject: existingSettings, options: [.prettyPrinted])
        try existingData.write(to: settingsURL)

        XCTAssertFalse(AgentHookManager.status(for: .claude, home: home).installed)

        let scriptPath = "/Applications/Gary Tools.app/Contents/Resources/dev-pull-all.sh"
        try AgentHookManager.install(.claude, scriptPath: scriptPath, dirs: ["~/Developer", "~/Work"], home: home)

        // Verify wrapper script permissions & content
        let wrapperURL = AgentHookKind.claude.configURL(home: home)
        XCTAssertTrue(fm.fileExists(atPath: wrapperURL.path))
        let perms = try fm.attributesOfItem(atPath: wrapperURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o755)
        let scriptText = try String(contentsOf: wrapperURL, encoding: .utf8)
        XCTAssertTrue(scriptText.contains("\"\(scriptPath)\""))
        XCTAssertTrue(scriptText.contains("--dirs \"~/Developer:~/Work\""))
        XCTAssertTrue(scriptText.contains("\"$@\""))
        XCTAssertTrue(AgentHookManager.status(for: .claude, home: home).installed)

        // Re-installing with updated dirs should update script and NOT duplicate settings.json entry
        try AgentHookManager.install(.claude, scriptPath: scriptPath, dirs: ["~/Developer", "/Volumes/Code"], home: home)
        let updatedScript = try String(contentsOf: wrapperURL, encoding: .utf8)
        XCTAssertTrue(updatedScript.contains("--dirs \"~/Developer:/Volumes/Code\""))

        let mergedObj = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as! [String: Any]
        XCTAssertEqual(mergedObj["theme"] as? String, "dark")
        let mergedHooks = mergedObj["hooks"] as! [String: Any]
        let sessionStart = mergedHooks["SessionStart"] as! [[String: Any]]
        XCTAssertEqual(sessionStart.count, 2, "Should contain original hook + single dev-pull-all entry")
        XCTAssertNotNil(mergedHooks["Stop"])

        // Uninstall removes wrapper and only our SessionStart entry
        try AgentHookManager.uninstall(.claude, home: home)
        XCTAssertFalse(fm.fileExists(atPath: wrapperURL.path))
        XCTAssertFalse(AgentHookManager.status(for: .claude, home: home).installed)

        let afterObj = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as! [String: Any]
        XCTAssertEqual(afterObj["theme"] as? String, "dark")
        let afterHooks = afterObj["hooks"] as! [String: Any]
        let remainingSessionStart = afterHooks["SessionStart"] as! [[String: Any]]
        XCTAssertEqual(remainingSessionStart.count, 1)
        let remainingInner = (remainingSessionStart[0]["hooks"] as! [[String: Any]])[0]
        XCTAssertEqual(remainingInner["command"] as? String, "/usr/local/bin/other-hook")
        XCTAssertNotNil(afterHooks["Stop"])
    }

    func testAntigravityInstallUpdatesIdempotentlyPreservesOtherKeysAndUninstalls() throws {
        let home = try makeTempDir("hook-antigravity")
        let hooksURL = AgentHookKind.antigravity.configURL(home: home)
        try FileManager.default.createDirectory(at: hooksURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let existing: [String: Any] = [
            "user-custom": [
                "SessionStart": [
                    ["type": "command", "command": "/usr/local/bin/my-hook", "timeout": 15]
                ]
            ]
        ]
        try JSONSerialization.data(withJSONObject: existing).write(to: hooksURL)

        XCTAssertFalse(AgentHookManager.status(for: .antigravity, home: home).installed)

        let script = "/Applications/Gary Tools.app/Contents/Resources/dev-pull-all.sh"
        try AgentHookManager.install(.antigravity, scriptPath: script, dirs: ["~/Developer"], home: home)
        XCTAssertTrue(AgentHookManager.status(for: .antigravity, home: home).installed)

        // Second install updates dirs in place without duplicating
        try AgentHookManager.install(.antigravity, scriptPath: script, dirs: ["~/Developer", "~/Client"], home: home)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: hooksURL)) as! [String: Any]
        XCTAssertNotNil(json["user-custom"])
        let group = json["dev-pull-all"] as! [String: Any]
        let entries = group["SessionStart"] as! [[String: Any]]
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(
            entries[0]["command"] as? String,
            "\"\(script)\" --format antigravity --dirs \"~/Developer:~/Client\""
        )

        // Uninstall removes only dev-pull-all
        try AgentHookManager.uninstall(.antigravity, home: home)
        XCTAssertFalse(AgentHookManager.status(for: .antigravity, home: home).installed)
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: hooksURL)) as! [String: Any]
        XCTAssertNil(after["dev-pull-all"])
        XCTAssertNotNil(after["user-custom"])
    }

    func testCodexInstallCreatesMissingFilePreservesOtherHooksAndUninstalls() throws {
        let home = try makeTempDir("hook-codex")
        let hooksURL = AgentHookKind.codex.configURL(home: home)

        // Starts missing
        XCTAssertFalse(AgentHookManager.status(for: .codex, home: home).installed)

        let script = "/Users/alice/.local/bin/dev-pull-all"
        try AgentHookManager.install(.codex, scriptPath: script, dirs: ["~/Developer"], home: home)
        XCTAssertTrue(AgentHookManager.status(for: .codex, home: home).installed)

        // Inject another user hook alongside ours
        var obj = try JSONSerialization.jsonObject(with: Data(contentsOf: hooksURL)) as! [String: Any]
        var hooks = obj["hooks"] as! [String: Any]
        var ss = hooks["SessionStart"] as! [[String: Any]]
        ss.insert(["hooks": [["type": "command", "command": "/usr/local/bin/qsync start", "timeout": 30]]], at: 0)
        hooks["SessionStart"] = ss
        obj["hooks"] = hooks
        obj["extraKey"] = true
        try JSONSerialization.data(withJSONObject: obj).write(to: hooksURL)

        // Re-install with 2 dirs updates our entry in place
        try AgentHookManager.install(.codex, scriptPath: script, dirs: ["~/Developer", "~/OSS"], home: home)
        let afterInstall = try JSONSerialization.jsonObject(with: Data(contentsOf: hooksURL)) as! [String: Any]
        XCTAssertEqual(afterInstall["extraKey"] as? Bool, true)
        let installedSS = (afterInstall["hooks"] as! [String: Any])["SessionStart"] as! [[String: Any]]
        XCTAssertEqual(installedSS.count, 2)
        let ourCmd = ((installedSS[1]["hooks"] as! [[String: Any]])[0]["command"] as? String)
        XCTAssertEqual(ourCmd, "\"\(script)\" --format plain --dirs \"~/Developer:~/OSS\"")

        // Uninstall leaves qsync & extraKey intact
        try AgentHookManager.uninstall(.codex, home: home)
        XCTAssertFalse(AgentHookManager.status(for: .codex, home: home).installed)
        let afterUninstall = try JSONSerialization.jsonObject(with: Data(contentsOf: hooksURL)) as! [String: Any]
        XCTAssertEqual(afterUninstall["extraKey"] as? Bool, true)
        let remainingSS = (afterUninstall["hooks"] as! [String: Any])["SessionStart"] as! [[String: Any]]
        XCTAssertEqual(remainingSS.count, 1)
        let remainingCmd = ((remainingSS[0]["hooks"] as! [[String: Any]])[0]["command"] as? String)
        XCTAssertEqual(remainingCmd, "/usr/local/bin/qsync start")
    }

    func testAllStatusesReturnsAllThreeKinds() throws {
        let home = try makeTempDir("hook-all")
        let statuses = AgentHookManager.allStatuses(home: home)
        XCTAssertEqual(statuses.map(\.kind), [.claude, .codex, .antigravity])
        XCTAssertTrue(statuses.allSatisfy { !$0.installed })
    }

    // MARK: - UpdateChecker Tests

    func testUpdateParserURLs() {
        XCTAssertEqual(
            UpdateParser.compareAPIURL(from: "abc1234").absoluteString,
            "https://api.github.com/repos/Nicegarrry/gary-tools/compare/abc1234...main"
        )
        XCTAssertEqual(
            UpdateParser.compareAPIURL(from: "abc1234", branch: "release").absoluteString,
            "https://api.github.com/repos/Nicegarrry/gary-tools/compare/abc1234...release"
        )
        XCTAssertEqual(
            UpdateParser.latestCommitAPIURL().absoluteString,
            "https://api.github.com/repos/Nicegarrry/gary-tools/commits/main"
        )
    }

    func testParseGitHubCompareResponseUpToDateStates() throws {
        let identicalJSON = Data("""
        {
          "status": "identical",
          "ahead_by": 0,
          "behind_by": 0,
          "html_url": "https://github.com/Nicegarrry/gary-tools/compare/1234567...main",
          "commits": []
        }
        """.utf8)
        XCTAssertEqual(
            try UpdateParser.parseGitHubCompareResponse(identicalJSON, currentCommit: "1234567890abcdef"),
            .upToDate(commit: "1234567")
        )

        let behindJSON = Data("""
        {
          "status": "behind",
          "ahead_by": 0,
          "behind_by": 3,
          "commits": []
        }
        """.utf8)
        XCTAssertEqual(
            try UpdateParser.parseGitHubCompareResponse(behindJSON, currentCommit: "abcdef0123"),
            .upToDate(commit: "abcdef0")
        )
    }

    func testParseGitHubCompareResponseUpdateAvailableLimitsToTenNewestFirst() throws {
        // Build 12 commits oldest -> newest
        let commitObjects = (1...12).map { i -> String in
            let sha = String(format: "%07xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", i)
            return """
            {"sha": "\(sha)", "commit": {"message": "Commit #\(i)\\n\\nBody details for #\(i)"}}
            """
        }.joined(separator: ",")

        let json = Data("""
        {
          "status": "ahead",
          "ahead_by": 12,
          "html_url": "https://github.com/Nicegarrry/gary-tools/compare/0000000...main",
          "commits": [\(commitObjects)]
        }
        """.utf8)

        let outcome = try UpdateParser.parseGitHubCompareResponse(json, currentCommit: "0000000999")
        guard case .updateAvailable(let info) = outcome else {
            return XCTFail("Expected .updateAvailable, got \(outcome)")
        }
        XCTAssertEqual(info.currentCommit, "0000000")
        XCTAssertEqual(info.latestCommit, "000000c")
        XCTAssertEqual(info.commitsBehind, 12)
        XCTAssertEqual(info.compareURL.absoluteString, "https://github.com/Nicegarrry/gary-tools/compare/0000000...main")
        XCTAssertEqual(info.summaryLines.count, 10)
        XCTAssertEqual(info.summaryLines.first, "Commit #12")
        XCTAssertEqual(info.summaryLines.last, "Commit #3")
    }

    func testParseGitHubLatestCommitResponseFallback() throws {
        let json = Data("""
        {
          "sha": "9f8e7d6c5b4a32109876543210fedcba98765432",
          "html_url": "https://github.com/Nicegarrry/gary-tools/commit/9f8e7d6",
          "commit": {
            "message": "Add onboarding wizard\\n\\nMore details"
          }
        }
        """.utf8)

        // Matching short SHA -> upToDate
        XCTAssertEqual(
            try UpdateParser.parseGitHubLatestCommitResponse(json, currentCommit: "9f8e7d6"),
            .upToDate(commit: "9f8e7d6")
        )

        // Different commit -> updateAvailable
        let diffOutcome = try UpdateParser.parseGitHubLatestCommitResponse(json, currentCommit: "1111111")
        guard case .updateAvailable(let info) = diffOutcome else {
            return XCTFail("Expected .updateAvailable, got \(diffOutcome)")
        }
        XCTAssertEqual(info.currentCommit, "1111111")
        XCTAssertEqual(info.latestCommit, "9f8e7d6")
        XCTAssertEqual(info.commitsBehind, 1)
        XCTAssertEqual(info.summaryLines, ["Add onboarding wizard"])
        XCTAssertEqual(info.compareURL.absoluteString, "https://github.com/Nicegarrry/gary-tools/commit/9f8e7d6")

        // Unknown / nil currentCommit -> .unknown
        let unknownOutcome = try UpdateParser.parseGitHubLatestCommitResponse(json, currentCommit: nil)
        guard case .unknown(let reason) = unknownOutcome else {
            return XCTFail("Expected .unknown, got \(unknownOutcome)")
        }
        XCTAssertTrue(reason.contains("9f8e7d6"))
    }

    func testUpdateSourceLocatorPriorityOrder() throws {
        let root = try makeTempDir("update-locator")
        let fm = FileManager.default
        let appSupport = root.appendingPathComponent("AppSupport", isDirectory: true)
        try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)

        func makeValidRepo(_ name: String) throws -> URL {
            let dir = root.appendingPathComponent(name, isDirectory: true)
            try fm.createDirectory(at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true)
            try "#!/bin/bash\n".write(to: dir.appendingPathComponent("update.sh"), atomically: true, encoding: .utf8)
            return dir
        }

        // 0. None present -> nil
        XCTAssertNil(UpdateSourceLocator.locateSourceRepo(appSupportRoot: appSupport, bundleURL: nil))

        // 3. Fallback appSupportRoot/source
        let defaultClone = appSupport.appendingPathComponent("source", isDirectory: true)
        try fm.createDirectory(at: defaultClone.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "#!/bin/bash\n".write(to: defaultClone.appendingPathComponent("update.sh"), atomically: true, encoding: .utf8)
        XCTAssertEqual(
            UpdateSourceLocator.locateSourceRepo(appSupportRoot: appSupport, bundleURL: nil)?.standardizedFileURL,
            defaultClone.standardizedFileURL
        )

        // 2. Bundle inside <repo>/dist/Gary Tools.app takes precedence over appSupport/source
        let bundleRepo = try makeValidRepo("bundle-repo")
        let bundleURL = bundleRepo.appendingPathComponent("dist/Gary Tools.app", isDirectory: true)
        XCTAssertEqual(
            UpdateSourceLocator.locateSourceRepo(appSupportRoot: appSupport, bundleURL: bundleURL)?.standardizedFileURL,
            bundleRepo.standardizedFileURL
        )

        // 1. source-repo.txt takes precedence over bundleRepo and appSupport/source
        let pointerRepo = try makeValidRepo("pointer-repo")
        try (pointerRepo.path + "\n").write(
            to: appSupport.appendingPathComponent("source-repo.txt"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(
            UpdateSourceLocator.locateSourceRepo(appSupportRoot: appSupport, bundleURL: bundleURL)?.standardizedFileURL,
            pointerRepo.standardizedFileURL
        )

        // Invalid source-repo.txt (missing update.sh) falls through to bundleRepo
        let incompleteRepo = root.appendingPathComponent("incomplete", isDirectory: true)
        try fm.createDirectory(at: incompleteRepo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try incompleteRepo.path.write(
            to: appSupport.appendingPathComponent("source-repo.txt"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(
            UpdateSourceLocator.locateSourceRepo(appSupportRoot: appSupport, bundleURL: bundleURL)?.standardizedFileURL,
            bundleRepo.standardizedFileURL
        )
    }

    // MARK: - OnboardingState Tests

    func testOnboardingDetectorFreshExistingAndCompleted() throws {
        let appSupport = try makeTempDir("onboarding")
        let (defaults, _) = makeIsolatedDefaults()
        let fm = FileManager.default

        // Fresh install -> true
        XCTAssertTrue(OnboardingDetector.shouldShowOnLaunch(appSupportRoot: appSupport, defaults: defaults))

        // Mark completed -> false; reset -> true
        OnboardingDetector.markCompleted(defaults: defaults)
        XCTAssertFalse(OnboardingDetector.shouldShowOnLaunch(appSupportRoot: appSupport, defaults: defaults))
        OnboardingDetector.reset(defaults: defaults)
        XCTAssertTrue(OnboardingDetector.shouldShowOnLaunch(appSupportRoot: appSupport, defaults: defaults))

        // Existing settings.conf -> false, UNLESS install.sh placed .fresh_install marker
        let settingsConf = appSupport.appendingPathComponent("settings.conf")
        try "KEEP_AWAKE=no\n".write(to: settingsConf, atomically: true, encoding: .utf8)
        XCTAssertFalse(OnboardingDetector.shouldShowOnLaunch(appSupportRoot: appSupport, defaults: defaults))

        let freshMarker = appSupport.appendingPathComponent(OnboardingDetector.freshInstallMarker)
        try "".write(to: freshMarker, atomically: true, encoding: .utf8)
        XCTAssertTrue(OnboardingDetector.shouldShowOnLaunch(appSupportRoot: appSupport, defaults: defaults))
        OnboardingDetector.markCompleted(appSupportRoot: appSupport, defaults: defaults)
        XCTAssertFalse(fm.fileExists(atPath: freshMarker.path))
        XCTAssertFalse(OnboardingDetector.shouldShowOnLaunch(appSupportRoot: appSupport, defaults: defaults))
        OnboardingDetector.reset(defaults: defaults)

        try fm.removeItem(at: settingsConf)
        XCTAssertTrue(OnboardingDetector.shouldShowOnLaunch(appSupportRoot: appSupport, defaults: defaults))

        // Existing Clipboard/library.json -> false
        let clipDir = appSupport.appendingPathComponent("Clipboard", isDirectory: true)
        try fm.createDirectory(at: clipDir, withIntermediateDirectories: true)
        try "[]".write(to: clipDir.appendingPathComponent("library.json"), atomically: true, encoding: .utf8)
        XCTAssertFalse(OnboardingDetector.shouldShowOnLaunch(appSupportRoot: appSupport, defaults: defaults))
    }

    func testGitSetupStatusComputedProperties() {
        var status = GitSetupStatus(
            gitInstalled: true,
            userName: "  ",
            userEmail: "alice@example.com",
            ghInstalled: false,
            ghAccount: nil,
            sshKeyNames: []
        )
        XCTAssertFalse(status.hasIdentity)
        XCTAssertFalse(status.hasGitHubAuth)
        XCTAssertFalse(status.isReady)

        status.userName = "Alice"
        XCTAssertTrue(status.hasIdentity)
        XCTAssertFalse(status.isReady)

        status.sshKeyNames = ["id_ed25519.pub"]
        XCTAssertTrue(status.hasGitHubAuth)
        XCTAssertTrue(status.isReady)

        status.sshKeyNames = []
        status.ghAccount = "alice"
        XCTAssertTrue(status.hasGitHubAuth)
        XCTAssertTrue(status.isReady)

        status.gitInstalled = false
        XCTAssertFalse(status.isReady)
    }

    func testParseGHAuthAccountVariants() {
        let modernOutput = """
        github.com
          ✓ Logged in to github.com account Nicegarrry (keyring)
          - Active account: true
          - Git operations protocol: https
          - Token: gho_****
        """
        XCTAssertEqual(GitEnvironmentParser.parseGHAuthAccount(from: modernOutput), "Nicegarrry")

        let legacyOutput = """
        github.com
          ✓ Logged in to github.com as octocat (/Users/octocat/.config/gh/hosts.yml)
          ✓ Token: *******************
        """
        XCTAssertEqual(GitEnvironmentParser.parseGHAuthAccount(from: legacyOutput), "octocat")

        let multiAccountOutput = """
        github.com
          ✓ Logged in to github.com account work-user (keyring)
          - Active account: false

          ✓ Logged in to github.com account personal-user (keyring)
          - Active account: true
        """
        XCTAssertEqual(GitEnvironmentParser.parseGHAuthAccount(from: multiAccountOutput), "personal-user")

        let ansiOutput = "\u{001B}[32m✓\u{001B}[0m Logged in to github.com account ansi-user (keyring)"
        XCTAssertEqual(GitEnvironmentParser.parseGHAuthAccount(from: ansiOutput), "ansi-user")

        let notLoggedIn = "You are not logged into any GitHub hosts. To log in, run: gh auth login"
        XCTAssertNil(GitEnvironmentParser.parseGHAuthAccount(from: notLoggedIn))
        XCTAssertNil(GitEnvironmentParser.parseGHAuthAccount(from: ""))
    }

    func testFindSSHKeyNamesFiltersAndSorts() throws {
        let sshDir = try makeTempDir("ssh-keys")
        let fm = FileManager.default

        try "ssh-rsa AAAA...".write(to: sshDir.appendingPathComponent("id_rsa.pub"), atomically: true, encoding: .utf8)
        try "ssh-ed25519 AAAA...".write(to: sshDir.appendingPathComponent("id_ed25519.pub"), atomically: true, encoding: .utf8)
        try "PRIVATE".write(to: sshDir.appendingPathComponent("id_ed25519"), atomically: true, encoding: .utf8)
        try "host *".write(to: sshDir.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: sshDir.appendingPathComponent("not-a-key.pub"), withIntermediateDirectories: true)

        XCTAssertEqual(
            GitEnvironmentParser.findSSHKeyNames(in: sshDir),
            ["id_ed25519.pub", "id_rsa.pub"]
        )

        let missing = sshDir.appendingPathComponent("nonexistent", isDirectory: true)
        XCTAssertEqual(GitEnvironmentParser.findSSHKeyNames(in: missing), [])
    }
}
