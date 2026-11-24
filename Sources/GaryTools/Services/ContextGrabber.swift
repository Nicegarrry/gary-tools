import AppKit
import ApplicationServices
import GaryCore
import Vision

/// Context Grab: ⌃⌥G captures a region or window, reads its text, notes where it came from,
/// and puts one paste-ready block for an agent on the clipboard (markdown text + the screenshot).
@MainActor
final class ContextGrabber {
    enum GrabError: LocalizedError {
        case screenRecordingDenied, captureFailed
        var errorDescription: String? {
            switch self {
            case .screenRecordingDenied:
                return "Context Grab needs Screen Recording access to see other apps' windows. Turn on Gary Tools in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen Gary Tools."
            case .captureFailed:
                return "macOS couldn't take the screenshot. Try again, or check Screen Recording access for Gary Tools."
            }
        }
    }

    /// How many screenshots to keep in the Captures folder.
    static let keepCaptures = 50

    private(set) var isCapturing = false
    var developerDir: () -> String = { "~/Developer" }
    var onError: ((String) -> Void)?
    var onCaptured: ((ContextPack) -> Void)?

    static var capturesDir: URL {
        GaryToolsPaths.appSupportRoot.appendingPathComponent("Captures", isDirectory: true)
    }

    func grab() {
        guard !isCapturing else { return }
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            onError?(GrabError.screenRecordingDenied.localizedDescription)
            return
        }

        // Read the source before the capture UI takes focus.
        let front = NSWorkspace.shared.frontmostApplication
        let appName = front?.localizedName ?? ""
        let bundleID = front?.bundleIdentifier ?? ""
        let title = front.map { Self.focusedWindowTitle(pid: $0.processIdentifier) } ?? ""
        let url = Self.browserURL(bundleID: bundleID)
        let repo = ContextGrab.repo(fromWindowTitle: title, developerDir: developerDir())

        let dir = Self.capturesDir
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            onError?(error.localizedDescription); return
        }
        let now = Date()
        let file = dir.appendingPathComponent(ContextGrab.captureFileName(at: now))

        isCapturing = true
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i interactive (drag a region, Space for a window, Esc cancels), -x no sound, -o no window shadow.
        process.arguments = ["-i", "-x", "-o", file.path]
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                defer { self.isCapturing = false }
                // Esc leaves no file: a cancel, not an error.
                guard FileManager.default.fileExists(atPath: file.path) else { return }
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                let text = await Self.recognizeText(at: file)
                let pack = ContextPack(appName: appName, bundleID: bundleID, windowTitle: title, url: url,
                                       repo: repo, text: text, imagePath: file.path, capturedAt: now)
                self.deliver(pack, imageURL: file)
                ContextGrab.pruneCaptures(in: dir, keep: Self.keepCaptures)
            }
        }
        do {
            try process.run()
        } catch {
            isCapturing = false
            onError?(GrabError.captureFailed.localizedDescription)
        }
    }

    /// One clipboard item: markdown for text fields and terminals, PNG for apps that take images.
    /// It carries no Gary Tools marker, so Clipboard history keeps it like any other copy.
    private func deliver(_ pack: ContextPack, imageURL: URL) {
        let item = NSPasteboardItem()
        item.setString(pack.markdown(), forType: .string)
        if let png = try? Data(contentsOf: imageURL) { item.setData(png, forType: .png) }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            onError?(GrabError.captureFailed.localizedDescription); return
        }
        NSSound(named: "Pop")?.play()
        onCaptured?(pack)
    }

    // MARK: - Sources

    /// The focused window's title, through Accessibility (already granted for the clipboard's paste).
    static func focusedWindowTitle(pid: pid_t) -> String {
        guard AXIsProcessTrusted() else { return "" }
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return "" }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success else { return "" }
        return (title as? String) ?? ""
    }

    private static let browserScripts: [String: String] = [
        "com.apple.Safari": #"tell application "Safari" to return URL of front document"#,
        "com.google.Chrome": #"tell application "Google Chrome" to return URL of active tab of front window"#,
        "company.thebrowser.Browser": #"tell application "Arc" to return URL of active tab of front window"#,
        "com.brave.Browser": #"tell application "Brave Browser" to return URL of active tab of front window"#,
        "com.microsoft.edgemac": #"tell application "Microsoft Edge" to return URL of active tab of front window"#,
    ]

    /// The front tab's URL in a known browser. macOS asks once for Automation access per browser; a "no" just leaves the URL out.
    static func browserURL(bundleID: String) -> String? {
        guard let source = browserScripts[bundleID], let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil, let url = result.stringValue, !url.isEmpty else { return nil }
        return url
    }

    /// On-device text recognition with Vision. Returns lines top to bottom.
    nonisolated static func recognizeText(at url: URL) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false // code and paths read better uncorrected
                let handler = VNImageRequestHandler(url: url, options: [:])
                do {
                    try handler.perform([request])
                    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: lines.joined(separator: "\n"))
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}
