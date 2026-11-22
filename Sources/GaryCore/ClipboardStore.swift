import AppKit
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor public final class LibraryStore: ObservableObject {
    @Published public private(set) var index: LibraryIndex
    @Published public var errorMessage: String?
    @Published public var notice = ""
    @Published public var paused = false
    @Published public var stack: [UUID] = []
    public let root: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return encoder
    }()
    private let images = NSCache<NSString, NSImage>()
    public var clips: [Clip] { index.clips }
    public var boards: [Pinboard] { index.boards }
    public var preferences: ClipboardPreferences { index.preferences }
    public var historyBytes: Int { clips.reduce(0) { $0 + $1.byteCount } }
    private var indexURL: URL { root.appendingPathComponent("library.json") }
    private var payloadDirectory: URL { root.appendingPathComponent("clips", isDirectory: true) }
    private var previewDirectory: URL { root.appendingPathComponent("previews", isDirectory: true) }

    public init(root: URL) throws {
        self.root = root
        let fm = FileManager.default
        for directory in [root, root.appendingPathComponent("clips"), root.appendingPathComponent("previews")] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
        if fm.fileExists(atPath: root.appendingPathComponent("library.json").path) {
            index = try JSONDecoder().decode(LibraryIndex.self, from: Data(contentsOf: root.appendingPathComponent("library.json")))
            guard index.version == 1 else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        } else {
            index = LibraryIndex()
            try writeIndex(index)
        }
        images.countLimit = 100
        prune()
        collectOrphans()
    }

    public func payloadURL(_ id: UUID) -> URL { payloadDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
    private func previewURL(_ id: UUID) -> URL { previewDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("png") }

    public func payload(for id: UUID) throws -> ClipPayload {
        try JSONDecoder().decode(ClipPayload.self, from: Data(contentsOf: payloadURL(id)))
    }

    public func thumbnail(for id: UUID) -> NSImage? {
        let key = id.uuidString as NSString
        if let image = images.object(forKey: key) { return image }
        guard let image = NSImage(contentsOf: previewURL(id)) else { return nil }
        images.setObject(image, forKey: key); return image
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func writeIndex(_ value: LibraryIndex) throws { try writePrivate(encoder.encode(value), to: indexURL) }

    @discardableResult private func commit(_ value: LibraryIndex) -> Bool {
        do { try writeIndex(value); index = value; return true }
        catch { errorMessage = "Couldn’t save your library: \(error.localizedDescription)"; return false }
    }

    private func makePreview(_ payload: ClipPayload, id: UUID) {
        guard let bytes = payload.imageData, let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 480,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary),
              let png = NSBitmapImageRep(cgImage: thumbnail).representation(using: .png, properties: [:]) else { return }
        try? writePrivate(png, to: previewURL(id))
        if let image = NSImage(data: png) { images.setObject(image, forKey: id.uuidString as NSString) }
    }

    @discardableResult public func add(_ payload: ClipPayload, sourceName: String, sourceBundle: String, now: Date = Date(), forceNew: Bool = false, board: UUID? = nil) -> UUID? {
        guard !payload.items.isEmpty, payload.byteCount > 0 else { return nil }
        if !forceNew, let existing = clips.firstIndex(where: { $0.digest == payload.digest }) {
            var next = index
            next.clips[existing].copiedAt = now
            next.clips[existing].sourceName = sourceName
            next.clips[existing].sourceBundle = sourceBundle
            if let board, !next.clips[existing].boards.contains(board) { next.clips[existing].boards.append(board) }
            let id = next.clips[existing].id
            next.clips.sort { $0.copiedAt > $1.copiedAt }
            return commit(next) ? id : nil
        }
        let id = UUID(), text = payload.plainText ?? ""
        let fileNames = payload.fileURLs.map(\.lastPathComponent).joined(separator: ", ")
        let title = !fileNames.isEmpty ? fileNames : text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "\(payload.kind.label) clip"
        let clip = Clip(id: id, digest: payload.digest, kind: payload.kind, title: String(title.prefix(160)), text: String(text.prefix(100_000)), sourceName: sourceName, sourceBundle: sourceBundle, createdAt: now, copiedAt: now, byteCount: payload.byteCount, boards: board.map { [$0] } ?? [])
        do { try writePrivate(encoder.encode(payload), to: payloadURL(id)) }
        catch { errorMessage = "Couldn’t save clipboard data: \(error.localizedDescription)"; return nil }
        var next = index; next.clips.insert(clip, at: 0)
        guard commit(next) else { try? FileManager.default.removeItem(at: payloadURL(id)); return nil }
        makePreview(payload, id: id)
        prune(now: now)
        return clips.contains(where: { $0.id == id }) ? id : nil
    }

    @discardableResult public func updatePreferences(_ preferences: ClipboardPreferences) -> Bool {
        var next = index; next.preferences = preferences
        guard commit(next) else { return false }
        prune(); return true
    }

    public func addBoard(_ name: String) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = boards.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) { return existing.id }
        let board = Pinboard(id: UUID(), name: String(trimmed.prefix(80)))
        var next = index; next.boards.append(board)
        return commit(next) ? board.id : nil
    }

    public func renameBoard(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = boards.firstIndex(where: { $0.id == id }) else { return }
        var next = index; next.boards[i].name = String(trimmed.prefix(80)); commit(next)
    }

    public func deleteBoard(_ id: UUID) {
        var next = index; next.boards.removeAll { $0.id == id }
        for i in next.clips.indices { next.clips[i].boards.removeAll { $0 == id } }
        if commit(next) { prune() }
    }

    public func togglePin(_ id: UUID, board: UUID) {
        guard boards.contains(where: { $0.id == board }), let i = clips.firstIndex(where: { $0.id == id }) else { return }
        var next = index
        if next.clips[i].boards.contains(board) { next.clips[i].boards.removeAll { $0 == board } }
        else { next.clips[i].boards.append(board) }
        commit(next)
    }

    public func rename(_ id: UUID, title: String) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        var next = index; next.clips[i].title = String(title.prefix(160)); commit(next)
    }

    @discardableResult public func editText(_ id: UUID, text: String) -> UUID? {
        guard let original = clips.first(where: { $0.id == id }) else { return nil }
        let newID = UUID(), payload = ClipPayload.text(text)
        guard !text.isEmpty else { return nil }
        do { try writePrivate(encoder.encode(payload), to: payloadURL(newID)) }
        catch { errorMessage = error.localizedDescription; return nil }
        var replacement = original
        replacement.id = newID; replacement.digest = payload.digest; replacement.kind = payload.kind
        replacement.text = String(text.prefix(100_000)); replacement.byteCount = payload.byteCount
        var next = index
        if let i = next.clips.firstIndex(where: { $0.id == id }) { next.clips[i] = replacement }
        if commit(next) {
            stack = stack.map { $0 == id ? newID : $0 }
            removeFiles(id); return newID
        }
        try? FileManager.default.removeItem(at: payloadURL(newID))
        return nil
    }

    public func duplicate(_ id: UUID) {
        perform { _ = add(try payload(for: id), sourceName: "Gary Tools", sourceBundle: "local.nicegary.GaryTools", forceNew: true) }
    }

    public func delete(_ ids: Set<UUID>) {
        var next = index; next.clips.removeAll { ids.contains($0.id) }
        if commit(next) { for id in ids { removeFiles(id) }; stack.removeAll { ids.contains($0) } }
    }

    public func clearHistory() { delete(Set(clips.filter { !$0.isPinned }.map(\.id))) }

    public func prune(now: Date = Date()) {
        let prefs = preferences
        let cutoff = prefs.retentionDays > 0 ? now.addingTimeInterval(-Double(prefs.retentionDays) * 86400) : .distantPast
        var count = 0, bytes = 0
        var remove = Set<UUID>()
        for clip in clips.sorted(by: { $0.copiedAt > $1.copiedAt }) where !clip.isPinned {
            count += 1; bytes += clip.byteCount
            if clip.copiedAt < cutoff || count > max(1, prefs.maxClips) || bytes > max(1, prefs.maxHistoryMB) * 1_048_576 { remove.insert(clip.id) }
        }
        if !remove.isEmpty { delete(remove) }
    }

    private func removeFiles(_ id: UUID) {
        try? FileManager.default.removeItem(at: payloadURL(id))
        try? FileManager.default.removeItem(at: previewURL(id))
        images.removeObject(forKey: id.uuidString as NSString)
    }

    private func collectOrphans() {
        let ids = Set(clips.map { $0.id.uuidString })
        for dir in [payloadDirectory, previewDirectory] {
            for file in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where !ids.contains(file.deletingPathExtension().lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    public func enqueue(_ id: UUID) { if !stack.contains(id) { stack.append(id) } }

    public func dragProvider(for id: UUID) -> NSItemProvider {
        guard let payload = try? payload(for: id) else { return NSItemProvider() }
        if let url = payload.fileURLs.first { return NSItemProvider(object: url as NSURL) }
        let provider = NSItemProvider()
        if let item = payload.items.first {
            for rep in item.representations where UTType(rep.type) != nil {
                provider.registerDataRepresentation(forTypeIdentifier: rep.type, visibility: .all) { completion in
                    completion(rep.data, nil); return nil
                }
            }
        }
        if let text = payload.plainText, !provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) {
            provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
                completion(Data(text.utf8), nil); return nil
            }
        }
        return provider
    }

    public func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }

    public func filtered(query: String, board: UUID?, kind: ClipKind?, source: String, days: Int, now: Date = Date()) -> [Clip] {
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let cutoff = days == 0 ? Date.distantPast : now.addingTimeInterval(-Double(days) * 86400)
        return clips.filter { clip in
            (board == nil || clip.boards.contains(board!)) && (kind == nil || clip.kind == kind!) &&
            (source.isEmpty || clip.sourceBundle == source) && clip.copiedAt >= cutoff &&
            tokens.allSatisfy { token in [clip.title, clip.text, clip.sourceName, clip.sourceBundle].contains { $0.localizedStandardContains(token) } }
        }
    }
}
