import AppKit
import CryptoKit
import Foundation
import ImageIO

public enum ClipKind: String, Codable, CaseIterable {
    case text, link, image, files, color, other
    public var label: String { rawValue.capitalized }
    public var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .files: return "doc.on.doc"
        case .color: return "paintpalette"
        case .other: return "doc"
        }
    }
}

public struct Representation: Codable, Equatable, Sendable {
    public var type: String
    public var data: Data
    public init(type: String, data: Data) {
        self.type = type
        self.data = data
    }
}

public struct ClipboardItem: Codable, Equatable {
    public var representations: [Representation]
    public init(representations: [Representation]) {
        self.representations = representations
    }
}

public struct ClipPayload: Codable, Equatable {
    public var items: [ClipboardItem]
    public init(items: [ClipboardItem]) { self.items = items }

    public var byteCount: Int {
        items.reduce(0) { $0 + $1.representations.reduce(0) { $0 + $1.data.count } }
    }

    public var digest: String {
        var hash = SHA256()
        func feed(_ data: Data) {
            var length = UInt64(data.count).bigEndian
            withUnsafeBytes(of: &length) { hash.update(data: Data($0)) }
            hash.update(data: data)
        }
        for item in items {
            var count = UInt64(item.representations.count).bigEndian
            withUnsafeBytes(of: &count) { hash.update(data: Data($0)) }
            for rep in item.representations.sorted(by: { $0.type < $1.type }) {
                feed(Data(rep.type.utf8)); feed(rep.data)
            }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public var plainText: String? {
        let values = items.compactMap { item -> String? in
            for type in [NSPasteboard.PasteboardType.string.rawValue, "public.utf8-plain-text", "public.url", "public.file-url"] {
                if let rep = item.representations.first(where: { $0.type == type }),
                   let value = String(data: rep.data, encoding: .utf8) { return value }
            }
            if let rep = item.representations.first(where: { $0.type == NSPasteboard.PasteboardType.rtf.rawValue }),
               let rich = NSAttributedString(rtf: rep.data, documentAttributes: nil) { return rich.string }
            if let rep = item.representations.first(where: { $0.type == NSPasteboard.PasteboardType.html.rawValue }),
               let html = String(data: rep.data, encoding: .utf8) {
                return html.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "(?i)<(?:br\\s*/?|/p|/div)>", with: "\n", options: .regularExpression)
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&amp;", with: "&")
            }
            return nil
        }
        return values.isEmpty ? nil : values.joined(separator: "\n")
    }

    public var fileURLs: [URL] {
        items.flatMap { $0.representations }.filter { $0.type == "public.file-url" }
            .compactMap { String(data: $0.data, encoding: .utf8) }.compactMap(URL.init(string:))
    }

    public var imageData: Data? {
        for rep in items.flatMap(\.representations) where ["public.png", "public.tiff", "public.jpeg", "com.compuserve.gif", "public.heic"].contains(rep.type) {
            if CGImageSourceCreateWithData(rep.data as CFData, nil) != nil { return rep.data }
        }
        return nil
    }

    public var image: NSImage? { imageData.flatMap { NSImage(data: $0) } }

    public var kind: ClipKind {
        if !fileURLs.isEmpty { return .files }
        if imageData != nil { return .image }
        guard let text = plainText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return .other }
        if text.range(of: "^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$", options: .regularExpression) != nil { return .color }
        if !text.contains("\n"), let url = URL(string: text), ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") { return .link }
        return .text
    }

    public static func text(_ value: String) -> ClipPayload {
        ClipPayload(items: [ClipboardItem(representations: [Representation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(value.utf8))])])
    }
}

public struct Clip: Codable, Identifiable, Equatable {
    public var id: UUID
    public var digest: String
    public var kind: ClipKind
    public var title: String
    public var text: String
    public var sourceName: String
    public var sourceBundle: String
    public var createdAt: Date
    public var copiedAt: Date
    public var byteCount: Int
    public var boards: [UUID] = []
    public var isPinned: Bool { !boards.isEmpty }

    public init(id: UUID, digest: String, kind: ClipKind, title: String, text: String, sourceName: String,
                sourceBundle: String, createdAt: Date, copiedAt: Date, byteCount: Int, boards: [UUID] = []) {
        self.id = id; self.digest = digest; self.kind = kind; self.title = title; self.text = text
        self.sourceName = sourceName; self.sourceBundle = sourceBundle; self.createdAt = createdAt
        self.copiedAt = copiedAt; self.byteCount = byteCount; self.boards = boards
    }
}

public struct Pinboard: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public init(id: UUID, name: String) { self.id = id; self.name = name }
}

public struct ClipboardPreferences: Codable, Equatable {
    public var maxClips = 1000
    public var retentionDays = 30
    public var maxCaptureMB = 20
    public var maxHistoryMB = 500
    public var ignoreConfidential = true
    public var ignoreTransient = true
    public var excludedApps = "com.agilebits.onepassword7\ncom.1password.1password\ncom.bitwarden.desktop\norg.keepassxc.keepassxc\ncom.apple.keychainaccess"
    public var pasteDirectly = true
    public var shortcutKey = "V"
    public var shortcutModifiers = "controlOption"
    public init() {}
}

public struct LibraryIndex: Codable {
    public var version = 1
    public var clips: [Clip] = []
    public var boards = [Pinboard(id: UUID(), name: "Favorites")]
    public var preferences = ClipboardPreferences()
    public init() {}
}

public enum CapturePolicy {
    public static let ownMarker = "local.nicegary.garytools.restored"
    public static let legacyMarker = "local.pastelocal.restored"
    public static let confidential = Set(["org.nspasteboard.ConcealedType", "org.nspasteboard.AutoGeneratedType.Password", "com.agilebits.onepassword", "com.typeit4me.clipping"])
    public static let transient = Set(["org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"])

    public static func shouldIgnore(types: Set<String>, sourceBundle: String, preferences: ClipboardPreferences) -> Bool {
        if types.contains(ownMarker) || types.contains(legacyMarker) { return true }
        if preferences.ignoreConfidential && !types.isDisjoint(with: confidential) { return true }
        if preferences.ignoreTransient && !types.isDisjoint(with: transient) { return true }
        let exclusions = Set(preferences.excludedApps.split(whereSeparator: { $0.isNewline || $0 == "," }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
        return exclusions.contains(sourceBundle.lowercased())
    }
}

public extension ClipPayload {
    static func read(from pasteboard: NSPasteboard, limit: Int) -> ClipPayload? {
        guard let sourceItems = pasteboard.pasteboardItems, !sourceItems.isEmpty else { return nil }
        var size = 0
        var items: [ClipboardItem] = []
        for source in sourceItems {
            var reps: [Representation] = []
            for type in source.types where type.rawValue != CapturePolicy.ownMarker && type.rawValue != CapturePolicy.legacyMarker {
                guard let data = source.data(forType: type) else { continue }
                size += data.count
                guard size <= limit else { return nil }
                reps.append(Representation(type: type.rawValue, data: data))
            }
            if !reps.isEmpty { items.append(ClipboardItem(representations: reps)) }
        }
        return items.isEmpty ? nil : ClipPayload(items: items)
    }

    @discardableResult func write(to pasteboard: NSPasteboard, plain: Bool = false) -> Bool {
        let output: [NSPasteboardItem]
        if plain {
            guard let text = plainText else { return false }
            let item = NSPasteboardItem(); item.setString(text, forType: .string); output = [item]
        } else {
            output = items.map { item in
                let object = NSPasteboardItem()
                for rep in item.representations { object.setData(rep.data, forType: .init(rep.type)) }
                return object
            }
        }
        guard !output.isEmpty else { return false }
        output[0].setString("1", forType: .init(CapturePolicy.ownMarker))
        pasteboard.clearContents()
        return pasteboard.writeObjects(output)
    }
}
