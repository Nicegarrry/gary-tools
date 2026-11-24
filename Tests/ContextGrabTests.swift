import XCTest
@testable import GaryCore

final class ContextGrabTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("garytools-grab-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func makeRepo(_ relative: String, branch: String = "main") throws -> String {
        let path = root.appendingPathComponent(relative).path
        try fm.createDirectory(atPath: "\(path)/.git", withIntermediateDirectories: true)
        try "ref: refs/heads/\(branch)\n".write(toFile: "\(path)/.git/HEAD", atomically: true, encoding: .utf8)
        return path
    }

    func testErrorLinesPicksErrorsAndSkipsGoodNews() {
        let text = """
        Compiling app
        error: cannot find 'foo' in scope
        Build complete with 0 errors
        TypeError: undefined is not a function
        error: cannot find 'foo' in scope
        All good
        """
        XCTAssertEqual(ContextGrab.errorLines(in: text), [
            "error: cannot find 'foo' in scope",
            "TypeError: undefined is not a function",
        ])
    }

    func testRepoFromTerminalTitlePath() throws {
        let repo = try makeRepo("Developer/gary-tools", branch: "feature/grab")
        try fm.createDirectory(atPath: "\(repo)/Sources", withIntermediateDirectories: true)
        let found = ContextGrab.repo(fromWindowTitle: "~/Developer/gary-tools/Sources — zsh — 120×40",
                                     developerDir: "~/Developer", home: root.path)
        XCTAssertEqual(found, RepoContext(path: repo, branch: "feature/grab"))
    }

    func testRepoFromEditorTitleFolderNameOneLevelDeep() throws {
        let repo = try makeRepo("Developer/local/qos")
        let found = ContextGrab.repo(fromWindowTitle: "AGENTS.md — qos", developerDir: "~/Developer", home: root.path)
        XCTAssertEqual(found, RepoContext(path: repo, branch: "main"))
    }

    func testNoRepoWhenTitleHasNoMatch() throws {
        _ = try makeRepo("Developer/qos")
        XCTAssertNil(ContextGrab.repo(fromWindowTitle: "Inbox — Mail", developerDir: "~/Developer", home: root.path))
        XCTAssertNil(ContextGrab.repo(fromWindowTitle: "", developerDir: "~/Developer", home: root.path))
    }

    func testBranchFromWorktreeAndDetachedHead() throws {
        let gitDir = root.appendingPathComponent("worktree-git").path
        try fm.createDirectory(atPath: gitDir, withIntermediateDirectories: true)
        try "0123456789abcdef\n".write(toFile: "\(gitDir)/HEAD", atomically: true, encoding: .utf8)
        let worktree = root.appendingPathComponent("wt").path
        try fm.createDirectory(atPath: worktree, withIntermediateDirectories: true)
        try "gitdir: \(gitDir)\n".write(toFile: "\(worktree)/.git", atomically: true, encoding: .utf8)
        XCTAssertEqual(ContextGrab.branch(atRepo: worktree), "detached at 0123456")
    }

    func testMarkdownIncludesSourceErrorsAndText() {
        let pack = ContextPack(
            appName: "Terminal",
            windowTitle: "gary-tools — zsh",
            url: nil,
            repo: RepoContext(path: "/Users/nick/Developer/gary-tools", branch: "main"),
            text: "$ swift build\nerror: missing return\n```\ndone",
            imagePath: "/tmp/grab.png",
            capturedAt: Date(timeIntervalSince1970: 0)
        )
        let md = pack.markdown(home: "/Users/nick")
        XCTAssertTrue(md.hasPrefix("## Context from Terminal\n- Window: gary-tools — zsh\n"))
        XCTAssertTrue(md.contains("- Repo: `~/Developer/gary-tools` (branch `main`)"))
        XCTAssertTrue(md.contains("- Screenshot: `/tmp/grab.png`"))
        XCTAssertTrue(md.contains("### Errors on screen\n```\nerror: missing return\n```"))
        XCTAssertTrue(md.contains("### Text on screen"))
        // A fence inside the captured text must not close the block early.
        XCTAssertEqual(md.components(separatedBy: "```").count - 1, 4)
    }

    func testMarkdownWithoutTextOrErrorsStaysShort() {
        let md = ContextPack(appName: "Safari", url: "https://example.com", capturedAt: Date(timeIntervalSince1970: 0)).markdown()
        XCTAssertTrue(md.contains("- URL: https://example.com"))
        XCTAssertFalse(md.contains("###"))
    }

    func testPruneKeepsNewestCapturesOnly() throws {
        for i in 0..<5 {
            let url = root.appendingPathComponent(ContextGrab.captureFileName(at: Date(timeIntervalSince1970: Double(i))))
            try Data([0]).write(to: url)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(i * 100))], ofItemAtPath: url.path)
        }
        let unrelated = root.appendingPathComponent("keep-me.png")
        try Data([0]).write(to: unrelated)

        XCTAssertEqual(ContextGrab.pruneCaptures(in: root, keep: 2), 3)
        let left = try fm.contentsOfDirectory(atPath: root.path).sorted()
        XCTAssertEqual(left.count, 3)
        XCTAssertTrue(left.contains("keep-me.png"))
        XCTAssertTrue(left.contains(ContextGrab.captureFileName(at: Date(timeIntervalSince1970: 4))))
        XCTAssertTrue(left.contains(ContextGrab.captureFileName(at: Date(timeIntervalSince1970: 3))))
    }
}
