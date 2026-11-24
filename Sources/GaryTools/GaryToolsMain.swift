import AppKit
import GaryCore
import MenuBarBridge
import SwiftUI

@main
struct GaryToolsMain {
    @MainActor static func main() {
        let args = CommandLine.arguments

        if args.contains("--diagnose") {
            print("Gary Tools diagnostics")
            print("  Bundle ID:         \(Bundle.main.bundleIdentifier ?? ArrowBarModel.bundleID)")
            print("  Data Dir:          \(GaryToolsPaths.appSupportRoot.path)")
            print("  Accessibility:     \(AXIsProcessTrusted() ? "granted" : "not granted")")
            print("  MenuBarControl:    \(GTAssessmentRestriction.isAvailable() ? "available (MenuBarClientCore)" : "unavailable")")
            print("  SystemItems:       \(GTAssessmentRestriction.allSystemItems().count) allowed")
            exit(0)
        }

        if let idx = args.firstIndex(of: "--render"), args.count > idx + 1 {
            do {
                try renderPreviews(to: URL(fileURLWithPath: args[idx + 1], isDirectory: true))
                exit(0)
            } catch {
                fputs("Render failed: \(error)\n", stderr)
                exit(1)
            }
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor
    private static func renderPreviews(to out: URL) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("garytools-render-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = try LibraryStore(root: tmp)
        _ = store.add(.text("swift build -c release\n\nKeep it native. Keep it local."), sourceName: "Terminal", sourceBundle: "com.apple.Terminal")
        _ = store.add(.text("https://github.com/Nicegarrry/gary-tools"), sourceName: "Safari", sourceBundle: "com.apple.Safari")
        _ = store.add(.text("#B0552E"), sourceName: "Design", sourceBundle: "local.design")
        let coordinator = AppCoordinator(clipboardStore: store, migratedItems: [])

        func capture<V: View>(_ view: V, size: NSSize, name: String) throws {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = NSColor(srgbRed: 19.0/255, green: 42.0/255, blue: 69.0/255, alpha: 1)
            let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(AppTheme.navy))
            hosting.frame = NSRect(origin: .zero, size: size)
            w.contentView = hosting
            w.layoutIfNeeded()
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name))
        }

        for section in [MainSection.overview, .sleepGuard, .clipboard, .menuBar, .repoSync, .macSettings] {
            coordinator.activeSection = section
            let slug = section.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
            try capture(MainWindowView(coordinator: coordinator), size: NSSize(width: 940, height: 650), name: "main-\(slug).png")
        }

        try capture(SettingsView(coordinator: coordinator, initialPane: .general), size: NSSize(width: 820, height: 610), name: "settings-general.png")
        print("Rendered previews to \(out.path)")
    }
}
