import Foundation

/// Reads and changes Google Chrome's per-profile download folder.
///
/// Chrome keeps it in each profile's `Preferences` JSON (`download.default_directory`) and rewrites that
/// file while it runs, so Gary Tools only edits it while Chrome is quit, keeps a backup, and leaves
/// every other key as it was. This avoids the policy route (`DefaultDownloadDirectory`), which makes
/// Chrome say it is "managed by your organization".
public enum ChromeSettings {
    public static let bundleID = "com.google.Chrome"
    /// Google LLC's Apple Developer Team ID, checked on a downloaded Chrome before it is installed.
    public static let googleTeamID = "EQHXZ8M8AV"
    public static let downloadURL = URL(string: "https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg")!

    public static var userDataDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
    }

    public struct Profile: Identifiable, Equatable, Sendable {
        /// Folder name, such as "Default" or "Profile 1".
        public let id: String
        /// The name shown in Chrome's profile menu, when known.
        public let name: String
        public let preferencesURL: URL
    }

    /// Lists profiles that have a `Preferences` file, named from `Local State` when possible.
    public static func profiles(in dataDir: URL = userDataDir) -> [Profile] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(atPath: dataDir.path) else { return [] }
        let names = profileNames(localState: try? Data(contentsOf: dataDir.appendingPathComponent("Local State")))
        return folders
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .compactMap { folder -> Profile? in
                let prefs = dataDir.appendingPathComponent(folder).appendingPathComponent("Preferences")
                guard fm.fileExists(atPath: prefs.path) else { return nil }
                return Profile(id: folder, name: names[folder] ?? folder, preferencesURL: prefs)
            }
            .sorted { lhs, rhs in
                if lhs.id == "Default" { return true }
                if rhs.id == "Default" { return false }
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
    }

    /// Maps profile folders to display names from `Local State` (`profile.info_cache.<folder>.name`).
    public static func profileNames(localState: Data?) -> [String: String] {
        guard let data = localState,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else { return [:] }
        var names: [String: String] = [:]
        for (folder, info) in cache {
            if let name = (info as? [String: Any])?["name"] as? String, !name.isEmpty { names[folder] = name }
        }
        return names
    }

    public enum EditError: Error, LocalizedError, Equatable {
        case notJSONObject
        public var errorDescription: String? {
            "Chrome's Preferences file isn't in the expected format, so it was left alone."
        }
    }

    /// The download folder a profile's Preferences sets, or nil when Chrome uses its default (~/Downloads).
    public static func downloadDirectory(preferences data: Data) throws -> String? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw EditError.notJSONObject }
        let dir = (root["download"] as? [String: Any])?["default_directory"] as? String
        return (dir?.isEmpty ?? true) ? nil : dir
    }

    /// Returns `data` with `download.default_directory` set to `path` (or removed when nil).
    /// Every other key is kept.
    public static func settingDownloadDirectory(_ path: String?, in data: Data) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw EditError.notJSONObject }
        var download = root["download"] as? [String: Any] ?? [:]
        if let path {
            download["default_directory"] = path
        } else {
            download.removeValue(forKey: "default_directory")
        }
        root["download"] = download
        return try JSONSerialization.data(withJSONObject: root, options: [.withoutEscapingSlashes])
    }

    /// Reads `TeamIdentifier=` from `codesign -dv` output.
    public static func teamIdentifier(fromCodesignOutput output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) where line.hasPrefix("TeamIdentifier=") {
            let value = line.dropFirst("TeamIdentifier=".count).trimmingCharacters(in: .whitespaces)
            return value.isEmpty || value == "not set" ? nil : value
        }
        return nil
    }
}

/// The developer folder Gary Tools sets up (the same folder Repo Sync pulls).
public enum DeveloperFolder {
    public static func resolve(_ raw: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        ScreenshotLocation.resolve(raw.isEmpty ? "~/Developer" : raw, home: home)
    }
}
