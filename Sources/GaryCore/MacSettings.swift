import Foundation

// MARK: - Hidden macOS preferences

/// When a changed macOS preference is picked up.
public enum MacSettingTakesEffect: Equatable, Sendable {
    /// The next screenshot, file open or Finder window sees it.
    case immediately
    /// Finder reads it at launch, so Finder must be relaunched.
    case afterFinderRelaunch
}

/// A boolean macOS preference that lives in `defaults` but has no switch in System Settings.
public struct MacToggle: Identifiable, Equatable, Sendable {
    public let id: String
    public let domain: String
    public let key: String
    /// The value macOS uses when the key is absent.
    public let appleDefault: Bool
    public let title: String
    public let detail: String
    public let takesEffect: MacSettingTakesEffect

    public init(id: String, domain: String, key: String, appleDefault: Bool, title: String, detail: String, takesEffect: MacSettingTakesEffect) {
        self.id = id
        self.domain = domain
        self.key = key
        self.appleDefault = appleDefault
        self.title = title
        self.detail = detail
        self.takesEffect = takesEffect
    }
}

public enum MacDomains {
    public static let screenCapture = "com.apple.screencapture"
    public static let finder = "com.apple.finder"
    public static let desktopServices = "com.apple.desktopservices"
    /// `NSGlobalDomain`; the preferences backend maps it to "any application".
    public static let global = "NSGlobalDomain"
}

public enum ScreenshotFormat: String, CaseIterable, Identifiable, Sendable {
    case png, jpg, heic, pdf, tiff
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .png: return "PNG"
        case .jpg: return "JPEG"
        case .heic: return "HEIC"
        case .pdf: return "PDF"
        case .tiff: return "TIFF"
        }
    }
    /// Reads `com.apple.screencapture type`, which macOS also accepts as "jpeg" or upper case.
    public init(preference: Any?) {
        let raw = (preference as? String)?.lowercased() ?? "png"
        self = raw == "jpeg" ? .jpg : ScreenshotFormat(rawValue: raw) ?? .png
    }
}

public enum MacSettingsCatalog {
    public static let screenshotLocationKey = "location"
    public static let screenshotTypeKey = "type"

    public static let screenshotToggles: [MacToggle] = [
        MacToggle(id: "screenshot.shadow", domain: MacDomains.screenCapture, key: "disable-shadow", appleDefault: false,
                  title: "No shadow on window screenshots",
                  detail: "Window captures (⌘⇧4, then Space) skip the big drop shadow and transparent margin.",
                  takesEffect: .immediately),
        MacToggle(id: "screenshot.thumbnail", domain: MacDomains.screenCapture, key: "show-thumbnail", appleDefault: true,
                  title: "Show the floating thumbnail",
                  detail: "Off saves the file straight away instead of waiting about five seconds in the corner.",
                  takesEffect: .immediately),
        MacToggle(id: "screenshot.date", domain: MacDomains.screenCapture, key: "include-date", appleDefault: true,
                  title: "Put the date and time in the file name",
                  detail: "Off names files \"Screenshot\", \"Screenshot 1\" and so on.",
                  takesEffect: .immediately),
    ]

    public static let finderToggles: [MacToggle] = [
        MacToggle(id: "finder.hidden", domain: MacDomains.finder, key: "AppleShowAllFiles", appleDefault: false,
                  title: "Show hidden files",
                  detail: "Dotfiles like .env, .git and .claude appear in Finder. ⌘⇧. toggles it per window.",
                  takesEffect: .afterFinderRelaunch),
        MacToggle(id: "finder.extensions", domain: MacDomains.global, key: "AppleShowAllExtensions", appleDefault: false,
                  title: "Always show file extensions",
                  detail: "Shows .md, .ts and .json everywhere, including in save dialogs.",
                  takesEffect: .afterFinderRelaunch),
        MacToggle(id: "finder.pathbar", domain: MacDomains.finder, key: "ShowPathbar", appleDefault: false,
                  title: "Show the path bar",
                  detail: "The full folder path along the bottom of every Finder window.",
                  takesEffect: .afterFinderRelaunch),
        MacToggle(id: "finder.posixTitle", domain: MacDomains.finder, key: "_FXShowPosixPathInTitle", appleDefault: false,
                  title: "Full path in the window title",
                  detail: "Titles read ~/Developer/gary-tools instead of gary-tools.",
                  takesEffect: .afterFinderRelaunch),
        MacToggle(id: "finder.dsstoreNetwork", domain: MacDomains.desktopServices, key: "DSDontWriteNetworkStores", appleDefault: false,
                  title: "No .DS_Store files on network drives",
                  detail: "Finder stops leaving .DS_Store files on SMB and AFP shares.",
                  takesEffect: .afterFinderRelaunch),
        MacToggle(id: "finder.dsstoreUSB", domain: MacDomains.desktopServices, key: "DSDontWriteUSBStores", appleDefault: false,
                  title: "No .DS_Store files on USB drives",
                  detail: "Finder stops leaving .DS_Store files on external disks.",
                  takesEffect: .afterFinderRelaunch),
    ]

    /// Reads a `defaults` boolean the way macOS does: Bool, 0/1 numbers and "YES"/"true" strings.
    public static func boolValue(_ raw: Any?, default fallback: Bool) -> Bool {
        switch raw {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String:
            switch s.lowercased() {
            case "1", "yes", "true": return true
            case "0", "no", "false": return false
            default: return fallback
            }
        default: return fallback
        }
    }
}

// MARK: - Default apps for file types

/// A file extension whose default app Gary Tools lets you choose.
public struct FileTypeEntry: Identifiable, Equatable, Sendable {
    public let ext: String
    /// Shown when the extension's system type is shared with an unrelated format,
    /// so changing it changes that format too.
    public let caution: String?
    public var id: String { ext }

    public init(_ ext: String, caution: String? = nil) {
        self.ext = ext
        self.caution = caution
    }
}

public struct FileTypeGroup: Identifiable, Equatable, Sendable {
    public let name: String
    public let entries: [FileTypeEntry]
    public var id: String { name }
}

public enum FileTypeCatalog {
    public static let groups: [FileTypeGroup] = [
        FileTypeGroup(name: "Markdown & text", entries: [
            FileTypeEntry("md"), FileTypeEntry("markdown"), FileTypeEntry("txt"), FileTypeEntry("log"),
        ]),
        FileTypeGroup(name: "Data & config", entries: [
            FileTypeEntry("json"), FileTypeEntry("yaml"), FileTypeEntry("yml"), FileTypeEntry("toml"),
            FileTypeEntry("csv"), FileTypeEntry("xml"),
        ]),
        FileTypeGroup(name: "Code", entries: [
            FileTypeEntry("ts", caution: "macOS also uses .ts for MPEG-2 video, so those open in this app too."),
            FileTypeEntry("tsx"), FileTypeEntry("js"), FileTypeEntry("jsx"), FileTypeEntry("mjs"),
            FileTypeEntry("py"), FileTypeEntry("swift"), FileTypeEntry("go"), FileTypeEntry("rs"),
            FileTypeEntry("rb"), FileTypeEntry("sh"), FileTypeEntry("zsh"), FileTypeEntry("css"),
            FileTypeEntry("sql"),
        ]),
    ]

    public static var allExtensions: [String] { groups.flatMap { $0.entries.map(\.ext) } }
}

// MARK: - Originals journal (fail-safe undo)

/// Remembers what each setting was before Gary Tools first changed it, so every change can be undone.
/// A key is recorded once: later changes never overwrite the true original.
public struct OriginalsJournal: Equatable {
    public enum Original: Equatable {
        /// The key was not set (macOS used its built-in default).
        case absent
        case value(String)
    }

    public private(set) var entries: [String: Original]

    public init(entries: [String: Original] = [:]) {
        self.entries = entries
    }

    public var isEmpty: Bool { entries.isEmpty }

    public static func preferenceKey(domain: String, key: String) -> String { "defaults|\(domain)|\(key)" }
    public static func contentTypeKey(_ identifier: String) -> String { "type|\(identifier)" }
    public static func schemeKey(_ scheme: String) -> String { "scheme|\(scheme)" }

    /// Records `current` as the original for `key` unless one is already recorded. Returns true if it recorded.
    @discardableResult
    public mutating func recordIfNeeded(_ key: String, current: Original) -> Bool {
        guard entries[key] == nil else { return false }
        entries[key] = current
        return true
    }

    public mutating func forget(_ key: String) {
        entries.removeValue(forKey: key)
    }

    // Plist form: ["key": ["absent": true]] or ["key": ["value": "..."]].
    public init(plist data: Data) throws {
        guard let raw = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String: Any]] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        var parsed: [String: Original] = [:]
        for (key, item) in raw {
            if let value = item["value"] as? String { parsed[key] = .value(value) }
            else if item["absent"] as? Bool == true { parsed[key] = .absent }
        }
        entries = parsed
    }

    public func plistData() throws -> Data {
        var raw: [String: [String: Any]] = [:]
        for (key, original) in entries {
            switch original {
            case .absent: raw[key] = ["absent": true]
            case .value(let v): raw[key] = ["value": v]
            }
        }
        return try PropertyListSerialization.data(fromPropertyList: raw, format: .xml, options: 0)
    }

    public static var defaultURL: URL {
        GaryToolsPaths.appSupportRoot.appendingPathComponent("mac-settings-originals.plist")
    }

    public static func load(from url: URL = defaultURL) -> OriginalsJournal {
        guard let data = try? Data(contentsOf: url), let journal = try? OriginalsJournal(plist: data) else {
            return OriginalsJournal()
        }
        return journal
    }

    public func save(to url: URL = defaultURL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if isEmpty {
            try? fm.removeItem(at: url)
            return
        }
        try plistData().write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Encodes a `defaults` value for the journal. Only the value types Gary Tools writes are supported.
public enum PreferenceCoding {
    public static func encode(_ value: Any?) -> OriginalsJournal.Original {
        switch value {
        case nil: return .absent
        case let b as Bool: return .value(b ? "bool:1" : "bool:0")
        case let n as NSNumber: return .value(n.boolValue ? "bool:1" : "bool:0")
        case let s as String: return .value("string:" + s)
        default: return .absent
        }
    }

    public static func decode(_ original: OriginalsJournal.Original) -> Any? {
        guard case .value(let raw) = original else { return nil }
        if raw == "bool:1" { return true }
        if raw == "bool:0" { return false }
        if raw.hasPrefix("string:") { return String(raw.dropFirst("string:".count)) }
        return nil
    }
}

/// Turns a screenshot folder setting into an absolute path, expanding `~`.
public enum ScreenshotLocation {
    public static func resolve(_ raw: Any?, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        guard let s = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return home.appendingPathComponent("Desktop", isDirectory: true)
        }
        if s == "~" { return home }
        if s.hasPrefix("~/") { return home.appendingPathComponent(String(s.dropFirst(2)), isDirectory: true) }
        return URL(fileURLWithPath: s, isDirectory: true)
    }

    /// Shortens a path under home to `~/…` for display.
    public static func display(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }
}
