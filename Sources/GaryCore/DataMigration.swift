import Foundation

public enum GaryToolsPaths {
    public static var appSupportRoot: URL {
        if let override = ProcessInfo.processInfo.environment["GARY_TOOLS_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Gary Tools", isDirectory: true)
    }

    public static var clipboardRoot: URL {
        appSupportRoot.appendingPathComponent("Clipboard", isDirectory: true)
    }

    public static var settingsConfURL: URL {
        appSupportRoot.appendingPathComponent("settings.conf")
    }

    public static var statusURL: URL {
        appSupportRoot.appendingPathComponent(".status")
    }

    public static var lastSleepURL: URL {
        appSupportRoot.appendingPathComponent(".last_sleep")
    }

    public static var lastGitSyncURL: URL {
        appSupportRoot.appendingPathComponent(".last_git_sync")
    }

    public static var pullNowURL: URL {
        appSupportRoot.appendingPathComponent(".pull_now")
    }

    public static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/gary-tools.log")
    }
}

public enum DataMigration {
    /// Non-destructively migrates existing Paste Local, LidGuard, and ArrowBar data on first launch.
    @discardableResult
    public static func migrateIfNeeded(
        appSupportRoot: URL = GaryToolsPaths.appSupportRoot,
        pasteLocalSource: URL? = nil,
        lidguardSources: [URL]? = nil,
        defaults: UserDefaults = .standard,
        arrowBarDefaults: UserDefaults? = UserDefaults(suiteName: "local.np.ArrowBar")
    ) -> [String] {
        var migrated: [String] = []
        let fm = FileManager.default
        try? fm.createDirectory(at: appSupportRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        // 1. Paste Local clipboard library -> Gary Tools/Clipboard
        let clipboardDest = appSupportRoot.appendingPathComponent("Clipboard", isDirectory: true)
        let destLibrary = clipboardDest.appendingPathComponent("library.json")
        let pasteSource = pasteLocalSource ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Paste Local", isDirectory: true))
        if !fm.fileExists(atPath: destLibrary.path), let pasteSource,
           fm.fileExists(atPath: pasteSource.appendingPathComponent("library.json").path) {
            try? fm.createDirectory(at: clipboardDest, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for name in ["library.json", "clips", "previews"] {
                let src = pasteSource.appendingPathComponent(name)
                let dst = clipboardDest.appendingPathComponent(name)
                if fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path) {
                    try? fm.copyItem(at: src, to: dst)
                }
            }
            if fm.fileExists(atPath: destLibrary.path) {
                migrated.append("Clipboard history from Paste Local")
            }
        }

        // 2. LidGuard settings.conf & .last_git_sync -> Gary Tools/
        let destSettings = appSupportRoot.appendingPathComponent("settings.conf")
        let home = fm.homeDirectoryForCurrentUser
        let candidates = lidguardSources ?? [
            home.appendingPathComponent("Developer/local/gary-tools"),
            home.appendingPathComponent("Developer/local/lidguard"),
            home.appendingPathComponent(".lidguard")
        ]
        if !fm.fileExists(atPath: destSettings.path) {
            for folder in candidates {
                let src = folder.appendingPathComponent("settings.conf")
                if fm.fileExists(atPath: src.path) {
                    try? fm.copyItem(at: src, to: destSettings)
                    let syncSrc = folder.appendingPathComponent(".last_git_sync")
                    let syncDst = appSupportRoot.appendingPathComponent(".last_git_sync")
                    if fm.fileExists(atPath: syncSrc.path), !fm.fileExists(atPath: syncDst.path) {
                        try? fm.copyItem(at: syncSrc, to: syncDst)
                    }
                    migrated.append("Sleep Guard settings from LidGuard")
                    break
                }
            }
        }

        // 3. ArrowBar pinned apps & preferences -> UserDefaults.standard
        if !defaults.bool(forKey: "migratedFromArrowBar.v1"), let legacy = arrowBarDefaults {
            var copiedAny = false
            for key in ["policy", "knownMenuBarApps"] {
                if defaults.data(forKey: key) == nil, let data = legacy.data(forKey: key) {
                    defaults.set(data, forKey: key)
                    copiedAny = true
                }
            }
            for key in ["startCollapsed", "expandOnHover", "showRecoveryButton"] {
                if defaults.object(forKey: key) == nil, let val = legacy.object(forKey: key) {
                    defaults.set(val, forKey: key)
                    copiedAny = true
                }
            }
            defaults.set(true, forKey: "migratedFromArrowBar.v1")
            if copiedAny {
                migrated.append("Menu bar layout from ArrowBar")
            }
        }

        return migrated
    }
}
