import AppKit

@MainActor public protocol ClipboardSource {
    var changeCount: Int { get }
    var types: Set<String> { get }
    func read(limit: Int) -> ClipPayload?
}

@MainActor public final class SystemClipboardSource: ClipboardSource {
    public let pasteboard: NSPasteboard
    public init(_ pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }
    public var changeCount: Int { pasteboard.changeCount }
    public var types: Set<String> { Set((pasteboard.pasteboardItems ?? []).flatMap { $0.types.map(\.rawValue) }) }
    public func read(limit: Int) -> ClipPayload? { ClipPayload.read(from: pasteboard, limit: limit) }
}

@MainActor public final class ClipboardMonitor {
    private let store: LibraryStore
    private var timer: Timer?
    private var lastChange: Int
    private let clipboard: any ClipboardSource

    public init(store: LibraryStore, clipboard: any ClipboardSource) {
        self.store = store; self.clipboard = clipboard; lastChange = clipboard.changeCount
    }

    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    public func stop() { timer?.invalidate(); timer = nil }

    public func poll() {
        let change = clipboard.changeCount
        guard change != lastChange else { return }
        lastChange = change
        guard !store.paused else { return }
        let app = NSWorkspace.shared.frontmostApplication
        let bundle = app?.bundleIdentifier ?? ""
        guard !CapturePolicy.shouldIgnore(types: clipboard.types, sourceBundle: bundle, preferences: store.preferences) else { return }
        guard let payload = clipboard.read(limit: max(1, store.preferences.maxCaptureMB) * 1_048_576), clipboard.changeCount == change else { return }
        _ = store.add(payload, sourceName: app?.localizedName ?? "Unknown app", sourceBundle: bundle)
    }
}
