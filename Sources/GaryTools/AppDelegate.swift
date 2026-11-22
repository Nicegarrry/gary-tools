import AppKit
import Combine
import GaryCore
import SwiftUI

final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum ClipboardError: LocalizedError {
    case writeFailed, nonTextStack
    var errorDescription: String? {
        switch self {
        case .writeFailed: return "Couldn’t restore this clip to the clipboard. It may not contain the requested text format."
        case .nonTextStack: return "Paste All Text needs text in every stack item. Use Paste Next for images and files."
        }
    }
}

enum HubStatusIcon {
    /// Monochrome template "G" monogram for the macOS menu bar.
    static func image(activeAwake: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            let frame = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 15, height: 15), xRadius: 3.5, yRadius: 3.5)
            frame.lineWidth = 1.4
            frame.stroke()

            // Crisp inner G bars
            NSBezierPath(roundedRect: NSRect(x: 4.5, y: 11.8, width: 8.8, height: 1.9), xRadius: 0.9, yRadius: 0.9).fill()
            NSBezierPath(roundedRect: NSRect(x: 4.5, y: 4.3, width: 1.9, height: 9.4), xRadius: 0.9, yRadius: 0.9).fill()
            NSBezierPath(roundedRect: NSRect(x: 4.5, y: 4.3, width: 8.8, height: 1.9), xRadius: 0.9, yRadius: 0.9).fill()
            NSBezierPath(roundedRect: NSRect(x: 11.4, y: 4.3, width: 1.9, height: 5.2), xRadius: 0.9, yRadius: 0.9).fill()
            NSBezierPath(roundedRect: NSRect(x: 8.6, y: 7.6, width: 4.7, height: 1.9), xRadius: 0.9, yRadius: 0.9).fill()

            if activeAwake {
                // Small active dot at top-right corner when actively keeping Mac awake
                NSBezierPath(ovalIn: NSRect(x: 13.4, y: 13.4, width: 3.6, height: 3.6)).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var coordinator: AppCoordinator!
    private let hotKeys = GlobalHotKeys()
    private let deliveryQueue = DeliveryQueue()
    private let ownRegistration = ApplicationRegistration()
    private var clipboardMonitor: ClipboardMonitor?

    private var hubItem: NSStatusItem!
    private var arrowItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var clipboardPanel: ClipboardPanel!
    private var recoveryPanel: NSPanel?
    private var auxiliaryWindows: [NSWindow] = []

    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?
    private var statusTimer: Timer?
    private var hoverTimer: Timer?
    private var hoverGate = HoverRevealGate()
    private var pauseGeneration = 0
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == ArrowBarModel.bundleID && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        if let other = others.first {
            other.activate()
            NSApp.terminate(nil)
            return
        }

        // Proper macOS application: always in Dock with full top menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        ownRegistration.register(Bundle.main.bundleURL, bundleID: ArrowBarModel.bundleID)

        // Non-destructively migrate data from standalone Paste Local, LidGuard, and ArrowBar.
        let migrated = DataMigration.migrateIfNeeded()

        let store: LibraryStore
        do {
            store = try LibraryStore(root: GaryToolsPaths.clipboardRoot)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t open Gary Tools’ clipboard library"
            alert.informativeText = "Your existing library was left untouched. \(error.localizedDescription)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        coordinator = AppCoordinator(clipboardStore: store, migratedItems: migrated)
        wireCoordinatorActions()
        coordinator.lidGuard.ensureDaemonRunning()

        setupMainMenu()
        setupHubStatusItem()
        syncArrowStatusItem()
        setupClipboardPanel()
        setupHotKeys()
        setupSubscriptions()
        setupTimers()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleClipboardKey(event) == nil }
            return handled ? nil : event
        }

        clipboardMonitor = ClipboardMonitor(store: store, clipboard: SystemClipboardSource())
        clipboardMonitor?.start()

        if !ProcessInfo.processInfo.arguments.contains("--background") {
            openMainWindow()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            if self.coordinator.arrowBar.enabled && self.coordinator.arrowBar.visibility.available && self.coordinator.arrowBar.startCollapsed {
                self.coordinator.arrowBar.applyCollapsed()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stop()
        hotKeys.unregister()
        statusTimer?.invalidate()
        hoverTimer?.invalidate()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        coordinator?.arrowBar.revealAll()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow { settingsWindow = nil }
        if window === mainWindow && coordinator.arrowBar.editing {
            coordinator.arrowBar.finishEditing()
        }
        auxiliaryWindows.removeAll { $0 === window }
    }

    // MARK: - Wiring

    private func wireCoordinatorActions() {
        coordinator.openClipboardBrowser = { [weak self] in self?.toggleClipboardBrowser() }
        coordinator.openSettings = { [weak self] pane in self?.openSettingsWindow(pane: pane ?? .general) }
        coordinator.pasteClip = { [weak self] id, plain in self?.pasteClip(id, plain: plain) }
        coordinator.copyClip = { [weak self] id, plain in self?.copyClip(id, plain: plain) }
        coordinator.previewClip = { [weak self] id in self?.previewClip(id) }
        coordinator.editClip = { [weak self] id in self?.editSnippet(id) }
        coordinator.renameClip = { [weak self] id in self?.renameClip(id) }
        coordinator.deleteClip = { [weak self] id in self?.deleteClip(id) }
        coordinator.newBoard = { [weak self] in self?.newBoard() }
        coordinator.renameBoard = { [weak self] id in self?.renameBoard(id) }
        coordinator.deleteBoard = { [weak self] id in self?.deleteBoard(id) }
        coordinator.pasteStack = { [weak self] allText in self?.pasteStack(allText: allText) }
        coordinator.toggleClipboardPause = { [weak self] in self?.toggleClipboardPause() }
        coordinator.eraseClipboardHistory = { [weak self] in self?.eraseClipboardHistory() }
        coordinator.reconfigureHotKeys = { [weak self] in self?.configureHotKeys() }
        coordinator.requestAccessibility = { [weak self] in self?.requestAccessibility() }
    }

    private func setupHotKeys() {
        hotKeys.onToggleClipboard = { [weak self] in self?.toggleClipboardBrowser() }
        hotKeys.onPasteStack = { [weak self] in self?.pasteStack(allText: false) }
        hotKeys.onRevealMenuBar = { [weak self] in self?.coordinator.arrowBar.revealAll() }
        configureHotKeys()
    }

    private func configureHotKeys() {
        let ok = hotKeys.register(
            clipboardPrefs: coordinator.clipboardStore.preferences,
            enableRevealShortcut: coordinator.arrowBar.enabled
        )
        coordinator.arrowBar.revealShortcutAvailable = hotKeys.revealRegistered
        if !ok {
            coordinator.clipboardStore.notice = "A clipboard shortcut is already in use. Change it in Settings."
        }
    }

    private func setupSubscriptions() {
        coordinator.clipboardStore.$errorMessage.compactMap { $0 }.receive(on: RunLoop.main).sink { [weak self] message in
            self?.showAlert("Gary Tools — Clipboard", detail: message)
            self?.coordinator.clipboardStore.errorMessage = nil
        }.store(in: &subscriptions)

        coordinator.clipboardStore.$stack.map { !$0.isEmpty }.removeDuplicates().sink { [weak self] hasStack in
            guard let self, self.clipboardPanel.isVisible else { return }
            var frame = self.clipboardPanel.frame
            frame.size.height = hasStack ? AppTheme.stackHeight : AppTheme.browserHeight
            if let visible = self.clipboardPanel.screen?.visibleFrame {
                frame.size.height = min(frame.height, visible.height - 24)
                frame.origin.y = max(visible.minY + 12, min(frame.minY, visible.maxY - frame.height - 12))
            }
            self.clipboardPanel.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }.store(in: &subscriptions)

        coordinator.arrowBar.$enabled.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.syncArrowStatusItem()
                self?.configureHotKeys()
            }
        }.store(in: &subscriptions)

        coordinator.arrowBar.visibility.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateArrowStatusItem() }
        }.store(in: &subscriptions)

        coordinator.arrowBar.$conflictingManagers.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateArrowStatusItem() }
        }.store(in: &subscriptions)

        coordinator.arrowBar.$showRecoveryButton.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateRecoveryButton() }
        }.store(in: &subscriptions)

        NotificationCenter.default.addObserver(forName: .settingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshUI() }
        }
    }

    private func setupTimers() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshUI() }
        }
        let hover = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkMenuBarHover() }
        }
        hoverTimer = hover
        RunLoop.main.add(hover, forMode: .common)
    }

    private func refreshUI() {
        coordinator.refreshAll()
        updateHubStatusIcon()
        updateArrowStatusItem()
    }

    // MARK: - Main macOS Menu Bar (App Menu)

    private func setupMainMenu() {
        let main = NSMenu()

        // Gary Tools app menu
        let appRoot = NSMenuItem()
        let appMenu = NSMenu(title: "Gary Tools")
        appMenu.addItem(withTitle: "About Gary Tools", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("Settings…", #selector(menuOpenSettings), ","))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Gary Tools", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(menuItem("Quit Gary Tools", #selector(quitApp), "q"))
        appRoot.submenu = appMenu
        main.addItem(appRoot)

        // Tools menu
        let toolsRoot = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        let toolsMenu = NSMenu(title: "Tools")
        toolsMenu.addItem(menuItem("Overview", #selector(showOverview), "1"))
        toolsMenu.addItem(menuItem("Sleep Guard", #selector(showSleepGuard), "2"))
        toolsMenu.addItem(menuItem("Clipboard", #selector(showClipboardTab), "3"))
        toolsMenu.addItem(menuItem("Menu Bar Organizer", #selector(showMenuBarTab), "4"))
        toolsMenu.addItem(menuItem("Repo Sync", #selector(showRepoSyncTab), "5"))
        toolsMenu.addItem(.separator())
        toolsMenu.addItem(menuItem("Open Clipboard Browser", #selector(menuToggleClipboard), "v", modifiers: [.control, .option]))
        toolsMenu.addItem(menuItem("New Text Snippet…", #selector(menuNewSnippet), "n"))
        toolsMenu.addItem(menuItem("Pull Repos Now", #selector(menuPullReposNow), "r", modifiers: [.command, .shift]))
        toolsMenu.addItem(menuItem("Show All Menu Bar Icons", #selector(menuRevealIcons), ""))
        toolsRoot.submenu = toolsMenu
        main.addItem(toolsRoot)

        // Edit menu
        let editRoot = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, sel, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(sel), keyEquivalent: key))
        }
        editRoot.submenu = editMenu
        main.addItem(editRoot)

        // Window menu
        let winRoot = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let winMenu = NSMenu(title: "Window")
        winMenu.addItem(menuItem("Gary Tools", #selector(menuOpenMainWindow), "0"))
        winMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winRoot.submenu = winMenu
        main.addItem(winRoot)
        NSApp.windowsMenu = winMenu

        NSApp.mainMenu = main
    }

    private func menuItem(_ title: String, _ action: Selector, _ key: String, modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if !key.isEmpty { item.keyEquivalentModifierMask = modifiers }
        return item
    }

    // MARK: - Menu Bar Hub + ArrowBar Chevron

    private func setupHubStatusItem() {
        hubItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        hubItem.autosaveName = "GaryTools.Hub"
        hubItem.isVisible = true
        hubItem.button?.target = self
        hubItem.button?.action = #selector(hubClicked)
        hubItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateHubStatusIcon()
    }

    private func updateHubStatusIcon() {
        let lg = coordinator.lidGuard
        let activeAwake = lg.keepAwake || lg.daemonState == "awake"
        hubItem.button?.image = HubStatusIcon.image(activeAwake: activeAwake)
        hubItem.button?.toolTip = "Gary Tools\nSleep Guard: \(lg.statusMessage)\nClipboard: \(coordinator.clipboardStore.clips.count) clips"
    }

    @objc private func hubClicked() {
        let lg = coordinator.lidGuard
        let store = coordinator.clipboardStore
        let ab = coordinator.arrowBar
        let menu = NSMenu()

        let header = NSMenuItem(title: "Gary Tools — \(lg.statusMessage)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(menuItem("Open Gary Tools", #selector(menuOpenMainWindow), ""))
        menu.addItem(.separator())

        // Clipboard quick actions
        menu.addItem(menuItem("Show Clipboard  ⌃⌥V", #selector(menuToggleClipboard), ""))
        let pauseClip = menuItem(store.paused ? "Resume Clipboard Capture" : "Pause Clipboard Capture", #selector(menuToggleClipPause), "")
        menu.addItem(pauseClip)
        if !store.stack.isEmpty {
            menu.addItem(menuItem("Paste Next Stack Item (\(store.stack.count))", #selector(menuPasteStack), ""))
        }
        menu.addItem(.separator())

        // Sleep Guard quick actions
        let sleepToggle = menuItem("Sleep Guard (Watch Agents)", #selector(menuToggleSleepGuard), "")
        sleepToggle.state = lg.enabled ? .on : .off
        menu.addItem(sleepToggle)

        let keepAwakeItem = NSMenuItem(
            title: lg.keepAwake ? "Keep Awake (\(lg.keepAwakeStatus))" : "Keep Awake",
            action: nil,
            keyEquivalent: ""
        )
        keepAwakeItem.state = lg.keepAwake ? .on : .off
        let kaSub = NSMenu()
        kaSub.addItem(menuItem("Until I turn it off", #selector(keepAwakeIndef), ""))
        kaSub.addItem(menuItem("For 1 hour", #selector(keepAwake1h), ""))
        kaSub.addItem(menuItem("For 3 hours", #selector(keepAwake3h), ""))
        kaSub.addItem(menuItem("Until 7am", #selector(keepAwake7am), ""))
        kaSub.addItem(.separator())
        kaSub.addItem(menuItem("Turn off", #selector(keepAwakeOff), ""))
        keepAwakeItem.submenu = kaSub
        menu.addItem(keepAwakeItem)

        // ArrowBar quick toggle
        if ab.enabled {
            menu.addItem(.separator())
            menu.addItem(menuItem(ab.visibility.isCollapsed ? "Show All Menu Bar Icons" : "Tuck Away Menu Bar Icons", #selector(menuToggleIcons), ""))
        }

        // Repo Sync
        menu.addItem(.separator())
        menu.addItem(menuItem(lg.pullingNow ? "Pulling Repos…" : "Pull Repos Now", #selector(menuPullReposNow), ""))
        let syncInfo = NSMenuItem(title: "  \(lg.lastGitSyncText)", action: nil, keyEquivalent: "")
        syncInfo.isEnabled = false
        menu.addItem(syncInfo)

        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…", #selector(menuOpenSettings), ","))
        menu.addItem(menuItem("Open Log", #selector(menuOpenLog), ""))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Gary Tools", #selector(quitApp), "q"))

        hubItem.menu = menu
        hubItem.button?.performClick(nil)
        hubItem.menu = nil
    }

    private func syncArrowStatusItem() {
        if coordinator.arrowBar.enabled {
            if arrowItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: 26)
                item.autosaveName = "GaryTools.Arrow"
                item.isVisible = true
                item.behavior = []
                item.button?.target = self
                item.button?.action = #selector(arrowClicked)
                item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
                arrowItem = item
            }
            updateArrowStatusItem()
        } else {
            if let arrowItem {
                NSStatusBar.system.removeStatusItem(arrowItem)
                self.arrowItem = nil
            }
            recoveryPanel?.orderOut(nil)
        }
    }

    private func updateArrowStatusItem() {
        guard let button = arrowItem?.button else { return }
        let ab = coordinator.arrowBar
        let warning = !ab.visibility.available || ab.visibility.errorMessage != nil || !ab.conflictingManagers.isEmpty
        let symbol = ab.visibility.isCollapsed ? "chevron.left.2" : "chevron.right.2"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Menu Bar Organizer")
        button.image?.isTemplate = true
        button.toolTip = warning
            ? "Menu Bar Organizer needs attention — click to open Gary Tools"
            : (ab.visibility.isCollapsed ? "Show tucked-away icons · Right-click for options" : "Tuck away icons · Right-click for options")
        updateRecoveryButton()
    }

    @objc private func arrowClicked() {
        let ab = coordinator.arrowBar
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            let menu = NSMenu()
            menu.addItem(menuItem(ab.visibility.isCollapsed ? "Show all app icons" : "Tuck away app icons", #selector(menuToggleIcons), ""))
            menu.addItem(menuItem("Show all icons  ⌃⌥⌘Space", #selector(menuRevealIcons), ""))
            menu.addItem(menuItem("Edit menu bar layout…", #selector(menuEditMenuBarLayout), ""))
            menu.addItem(.separator())
            let hover = menuItem("Expand on menu bar hover", #selector(menuToggleHover), "")
            hover.state = ab.expandOnHover ? .on : .off
            menu.addItem(hover)
            menu.addItem(.separator())
            menu.addItem(menuItem("Open Gary Tools", #selector(menuOpenMainWindow), ""))
            arrowItem?.menu = menu
            arrowItem?.button?.performClick(nil)
            arrowItem?.menu = nil
        } else if !ab.conflictingManagers.isEmpty || !ab.visibility.available || ab.visibility.errorMessage != nil {
            coordinator.activeSection = .menuBar
            openMainWindow()
        } else {
            ab.toggle()
        }
    }

    private func updateRecoveryButton() {
        let ab = coordinator.arrowBar
        guard ab.enabled, ab.showRecoveryButton, ab.visibility.isCollapsed else {
            recoveryPanel?.orderOut(nil)
            return
        }
        if recoveryPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 126, height: 34),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView:
                Button { [weak self] in self?.coordinator.arrowBar.revealAll() } label: {
                    Label("Show icons", systemImage: "chevron.right.2")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.text)
                        .frame(width: 126, height: 34)
                        .background(GlassBackground(radius: 17))
                        .overlay(Capsule().strokeBorder(AppTheme.sky.opacity(0.35), lineWidth: 1))
                }.buttonStyle(.plain).accessibilityLabel("Show all menu bar icons")
            )
            recoveryPanel = panel
        }
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            recoveryPanel?.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 142, y: screen.visibleFrame.maxY - 44))
        }
        recoveryPanel?.orderFrontRegardless()
    }

    private func checkMenuBarHover() {
        let ab = coordinator.arrowBar
        guard ab.enabled, ab.expandOnHover, ab.visibility.isCollapsed, !ab.editing else {
            _ = hoverGate.update(inside: false, collapsed: false, enabled: false, now: 0)
            return
        }
        let point = NSEvent.mouseLocation
        let inside = NSScreen.screens.contains { screen in
            let frame = screen.frame
            let width = min(550, frame.width * 0.45)
            let height = max(24, NSStatusBar.system.thickness, screen.safeAreaInsets.top)
            let zone = NSRect(x: frame.maxX - width, y: frame.maxY - height, width: width, height: height)
            return zone.contains(point)
        }
        if hoverGate.update(inside: inside, collapsed: ab.visibility.isCollapsed,
                            enabled: ab.expandOnHover && !ab.editing,
                            now: ProcessInfo.processInfo.systemUptime) {
            ab.revealAll()
        }
    }

    // MARK: - Windows

    private func openMainWindow() {
        if mainWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 940, height: 650),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "Gary Tools"
            w.minSize = NSSize(width: 820, height: 580)
            AppTheme.prepare(w)
            w.contentView = NSHostingView(rootView: MainWindowView(coordinator: coordinator))
            w.setContentSize(NSSize(width: 940, height: 650))
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("GaryTools.MainWindow")
            w.delegate = self
            w.center()
            mainWindow = w
        }
        coordinator.refreshAll()
        coordinator.arrowBar.refresh()
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    private func openSettingsWindow(pane: SettingsPane = .general) {
        hideClipboardBrowser()
        if let settingsWindow {
            settingsWindow.contentView = NSHostingView(rootView: SettingsView(coordinator: coordinator, initialPane: pane))
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 610),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = "Gary Tools Settings"
        AppTheme.prepare(w)
        w.contentView = NSHostingView(rootView: SettingsView(coordinator: coordinator, initialPane: pane))
        w.setContentSize(NSSize(width: 820, height: 610))
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        settingsWindow = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    // MARK: - Clipboard Floating Browser & Delivery

    private func setupClipboardPanel() {
        clipboardPanel = ClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: AppTheme.browserHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        clipboardPanel.title = "Gary Tools Clipboard"
        clipboardPanel.isReleasedWhenClosed = false
        clipboardPanel.isOpaque = false
        clipboardPanel.backgroundColor = .clear
        clipboardPanel.hasShadow = true
        clipboardPanel.level = .floating
        clipboardPanel.hidesOnDeactivate = true
        clipboardPanel.isMovableByWindowBackground = true
        clipboardPanel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let actions = BrowserActions(
            paste: { [weak self] in self?.pasteClip($0, plain: $1) },
            copy: { [weak self] in self?.copyClip($0, plain: $1) },
            preview: { [weak self] in self?.previewClip($0) },
            edit: { [weak self] in self?.editSnippet($0) },
            rename: { [weak self] in self?.renameClip($0) },
            newText: { [weak self] in self?.editSnippet(nil) },
            newBoard: { [weak self] in self?.newBoard() },
            renameBoard: { [weak self] in self?.renameBoard($0) },
            deleteBoard: { [weak self] in self?.deleteBoard($0) },
            deleteClip: { [weak self] in self?.deleteClip($0) },
            pasteStack: { [weak self] in self?.pasteStack(allText: $0) },
            settings: { [weak self] in self?.openSettingsWindow(pane: .clipboard) },
            togglePause: { [weak self] in self?.toggleClipboardPause() },
            hide: { [weak self] in self?.hideClipboardBrowser() }
        )
        clipboardPanel.contentView = NSHostingView(
            rootView: ClipboardBrowserView(store: coordinator.clipboardStore, state: coordinator.clipboardState, actions: actions)
        )
    }

    private func capturePreviousApp() {
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = app
        }
    }

    private func toggleClipboardBrowser() {
        if clipboardPanel.isVisible && clipboardPanel.isKeyWindow { hideClipboardBrowser() }
        else { showClipboardBrowser() }
    }

    private func showClipboardBrowser() {
        capturePreviousApp()
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.visibleFrame
        let height = coordinator.clipboardStore.stack.isEmpty ? AppTheme.browserHeight : AppTheme.stackHeight
        let width = min(1320, frame.width - 24)
        clipboardPanel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.minY + 12, width: width, height: min(height, frame.height - 24)), display: true)
        let state = coordinator.clipboardState
        let store = coordinator.clipboardStore
        if state.board != nil && !store.boards.contains(where: { $0.id == state.board }) { state.board = nil }
        if !state.results(store).contains(where: { $0.id == state.selected }) { state.selected = state.results(store).first?.id }
        NSApp.activate(ignoringOtherApps: true)
        clipboardPanel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .focusPasteSearch, object: nil)
    }

    private func hideClipboardBrowser() {
        clipboardPanel.orderOut(nil)
    }

    private func toggleClipboardPause() {
        pauseGeneration += 1
        coordinator.clipboardStore.paused.toggle()
    }

    private func copyClip(_ id: UUID, plain: Bool) {
        deliveryQueue.enqueue { [weak self] done in
            guard let self else { done(); return }
            self.coordinator.clipboardStore.perform {
                guard try self.coordinator.clipboardStore.payload(for: id).write(to: .general, plain: plain) else { throw ClipboardError.writeFailed }
                self.coordinator.clipboardStore.notice = "Copied\(plain ? " as plain text" : "")"
            }
            done()
        }
    }

    private func pasteClip(_ id: UUID, plain: Bool) {
        capturePreviousApp()
        let target = previousApp
        deliveryQueue.enqueue { [weak self] done in
            guard let self else { done(); return }
            do { try self.deliver(self.coordinator.clipboardStore.payload(for: id), plain: plain, target: target) { _ in done() } }
            catch { self.coordinator.clipboardStore.errorMessage = error.localizedDescription; done() }
        }
    }

    private func deliver(_ payload: ClipPayload, plain: Bool = false, target: NSRunningApplication?, completion: @escaping (Bool) -> Void) throws {
        guard payload.write(to: .general, plain: plain) else { throw ClipboardError.writeFailed }
        let change = NSPasteboard.general.changeCount
        hideClipboardBrowser()
        let store = coordinator.clipboardStore
        guard store.preferences.pasteDirectly else { store.notice = "Copied to clipboard"; completion(true); return }
        guard AXIsProcessTrusted() else {
            store.notice = "Copied. Enable Accessibility in Settings for direct paste."
            target?.activate(options: [])
            completion(true)
            return
        }
        guard let target, !target.isTerminated, target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            store.notice = "Copied. Switch to your app and press ⌘V."
            completion(true)
            return
        }
        guard target.activate(options: []) else {
            store.notice = "Copied. Couldn’t activate the previous app."
            completion(true)
            return
        }
        sendPaste(whenActive: target, expectedClipboardChange: change, attempt: 0, completion: completion)
    }

    private func sendPaste(whenActive target: NSRunningApplication, expectedClipboardChange: Int, attempt: Int, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { completion(false); return }
            let store = self.coordinator.clipboardStore
            guard NSPasteboard.general.changeCount == expectedClipboardChange else {
                store.notice = "Paste cancelled because the clipboard changed. Stack item kept."
                completion(false)
                return
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                if attempt < 5 && !target.isTerminated {
                    self.sendPaste(whenActive: target, expectedClipboardChange: expectedClipboardChange, attempt: attempt + 1, completion: completion)
                } else {
                    store.notice = "Copied. Press ⌘V in your target app."
                    completion(true)
                }
                return
            }
            guard let source = CGEventSource(stateID: .combinedSessionState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
                store.notice = "Copied. Press ⌘V in your target app."
                completion(true)
                return
            }
            down.flags = .maskCommand; up.flags = .maskCommand
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
            store.notice = "Pasted"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { completion(true) }
        }
    }

    private func pasteStack(allText: Bool) {
        capturePreviousApp()
        let target = previousApp
        deliveryQueue.enqueue { [weak self] done in
            guard let self else { done(); return }
            let store = self.coordinator.clipboardStore
            guard !store.stack.isEmpty else { store.notice = "Your paste stack is empty"; done(); return }
            do {
                let ids = allText ? store.stack : Array(store.stack.prefix(1))
                let payloads = try ids.map { try store.payload(for: $0) }
                if allText && !payloads.allSatisfy({ $0.plainText != nil }) { throw ClipboardError.nonTextStack }
                let payload = allText ? ClipPayload.text(payloads.compactMap(\.plainText).joined(separator: "\n")) : payloads[0]
                try self.deliver(payload, target: target) { success in
                    if success { store.stack.removeAll { ids.contains($0) } }
                    done()
                }
            } catch {
                store.errorMessage = error.localizedDescription
                done()
            }
        }
    }

    private func handleClipboardKey(_ event: NSEvent) -> NSEvent? {
        guard clipboardPanel.isKeyWindow else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isEditing = clipboardPanel.firstResponder is NSTextView
        let textSelected = (clipboardPanel.firstResponder as? NSTextView)?.selectedRange().length ?? 0 > 0
        let state = coordinator.clipboardState
        let store = coordinator.clipboardStore
        let result = state.results(store)
        let id = state.selected ?? result.first?.id
        let command = flags.contains(.command)
        if event.keyCode == 53 { hideClipboardBrowser(); return nil }
        if command && event.charactersIgnoringModifiers == "," { openSettingsWindow(pane: .clipboard); return nil }
        if command && event.charactersIgnoringModifiers?.lowercased() == "n" { editSnippet(nil); return nil }
        if command && event.charactersIgnoringModifiers?.lowercased() == "v" && flags.contains(.shift), let id { pasteClip(id, plain: true); return nil }
        if command, let n = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(n), result.count >= n {
            pasteClip(result[n - 1].id, plain: flags.contains(.shift)); return nil
        }
        if command && event.charactersIgnoringModifiers?.lowercased() == "c" && (!isEditing || !textSelected), let id {
            copyClip(id, plain: flags.contains(.shift)); return nil
        }
        if event.keyCode == 36 || event.keyCode == 76 { if let id { pasteClip(id, plain: flags.contains(.shift)) }; return nil }
        if [123, 124, 125, 126].contains(event.keyCode), !command, !isEditing || [125, 126].contains(event.keyCode) || state.query.isEmpty {
            guard !result.isEmpty else { return nil }
            clipboardPanel.makeFirstResponder(clipboardPanel.contentView)
            let offset = result.firstIndex(where: { $0.id == id }) ?? 0
            let direction = [123, 126].contains(event.keyCode) ? -1 : 1
            state.selected = result[min(max(0, offset + direction), result.count - 1)].id
            return nil
        }
        if event.keyCode == 49, !isEditing, let id { previewClip(id); return nil }
        if event.keyCode == 51, !isEditing, let id { deleteClip(id); return nil }
        if command && event.charactersIgnoringModifiers?.lowercased() == "f" {
            NotificationCenter.default.post(name: .focusPasteSearch, object: nil); return nil
        }
        return event
    }

    // MARK: - Auxiliary Clipboard Dialogs

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func previewClip(_ id: UUID) {
        let store = coordinator.clipboardStore
        guard let clip = store.clips.first(where: { $0.id == id }) else { return }
        store.perform {
            let view = ClipPreviewView(clip: clip, payload: try store.payload(for: id), copy: { [weak self] in self?.copyClip(id, plain: false) })
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 500),
                             styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            AppTheme.prepare(w)
            w.title = "Clip Preview"
            w.contentView = NSHostingView(rootView: view)
            w.center(); w.isReleasedWhenClosed = false; w.delegate = self
            auxiliaryWindows.append(w); w.makeKeyAndOrderFront(nil)
        }
    }

    private func editSnippet(_ id: UUID?) {
        let store = coordinator.clipboardStore
        var initial = ""
        if let id {
            do { initial = try store.payload(for: id).plainText ?? "" }
            catch { store.errorMessage = error.localizedDescription; return }
        }
        let editor = SnippetEditorView(text: initial, title: id == nil ? "New Text Snippet" : "Edit Text", save: { [weak self] text in
            guard let self else { return false }
            let saved: UUID?
            if let id { saved = self.coordinator.clipboardStore.editText(id, text: text) }
            else {
                saved = self.coordinator.clipboardStore.add(
                    .text(text), sourceName: "Gary Tools", sourceBundle: ArrowBarModel.bundleID, forceNew: true, board: self.coordinator.clipboardState.board
                )
            }
            self.coordinator.clipboardState.selected = saved
            return saved != nil
        })
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 440),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        AppTheme.prepare(w)
        w.title = id == nil ? "New Text Snippet" : "Edit Text"
        w.contentView = NSHostingView(rootView: editor)
        w.center(); w.isReleasedWhenClosed = false; w.delegate = self
        auxiliaryWindows.append(w); w.makeKeyAndOrderFront(nil)
    }

    private func newBoard() {
        if let name = prompt("New Pinboard", value: "", detail: "Give this collection a name.") {
            coordinator.clipboardState.board = coordinator.clipboardStore.addBoard(name)
        }
    }

    private func renameBoard(_ id: UUID) {
        guard let board = coordinator.clipboardStore.boards.first(where: { $0.id == id }),
              let name = prompt("Rename Pinboard", value: board.name) else { return }
        coordinator.clipboardStore.renameBoard(id, to: name)
    }

    private func deleteBoard(_ id: UUID) {
        if confirm("Delete this pinboard?", detail: "Clips will stay in history. Clips with no remaining pinboard become subject to your history limits.") {
            coordinator.clipboardStore.deleteBoard(id)
            if coordinator.clipboardState.board == id { coordinator.clipboardState.board = nil }
        }
    }

    private func renameClip(_ id: UUID) {
        guard let clip = coordinator.clipboardStore.clips.first(where: { $0.id == id }),
              let title = prompt("Rename Clip", value: clip.title) else { return }
        coordinator.clipboardStore.rename(id, title: title)
    }

    private func deleteClip(_ id: UUID) {
        if confirm("Delete this clip?", detail: "This removes it from history, all pinboards, and the paste stack.") {
            coordinator.clipboardStore.delete([id])
        }
    }

    private func eraseClipboardHistory() {
        if confirm("Clear unpinned clipboard history?", detail: "Your pinned clips and pinboards will be kept.") {
            coordinator.clipboardStore.clearHistory()
        }
    }

    private func prompt(_ title: String, value: String, detail: String = "") -> String? {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        let field = NSTextField(string: value); field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    private func confirm(_ title: String, detail: String) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.alertStyle = .warning; alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showAlert(_ title: String, detail: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail; alert.runModal()
    }

    // MARK: - Menu Selectors

    @objc private func menuOpenMainWindow() { openMainWindow() }
    @objc private func menuOpenSettings() { openSettingsWindow(pane: .general) }
    @objc private func menuOpenLog() { coordinator.lidGuard.openLog() }
    @objc private func menuToggleClipboard() { toggleClipboardBrowser() }
    @objc private func menuToggleClipPause() { toggleClipboardPause() }
    @objc private func menuPasteStack() { pasteStack(allText: false) }
    @objc private func menuNewSnippet() { editSnippet(nil) }
    @objc private func menuToggleSleepGuard() { coordinator.lidGuard.enabled.toggle() }
    @objc private func keepAwakeIndef() { coordinator.lidGuard.startKeepAwake(until: nil) }
    @objc private func keepAwake1h() { coordinator.lidGuard.startKeepAwake(until: Date().addingTimeInterval(3600)) }
    @objc private func keepAwake3h() { coordinator.lidGuard.startKeepAwake(until: Date().addingTimeInterval(3 * 3600)) }
    @objc private func keepAwake7am() { coordinator.lidGuard.startKeepAwake(until: next7am()) }
    @objc private func keepAwakeOff() { coordinator.lidGuard.stopKeepAwake() }
    @objc private func menuToggleIcons() { coordinator.arrowBar.toggle() }
    @objc private func menuRevealIcons() { coordinator.arrowBar.revealAll() }
    @objc private func menuToggleHover() { coordinator.arrowBar.expandOnHover.toggle() }
    @objc private func menuPullReposNow() { coordinator.lidGuard.triggerPullNow() }
    @objc private func menuEditMenuBarLayout() {
        coordinator.activeSection = .menuBar
        coordinator.arrowBar.beginEditing()
        openMainWindow()
    }
    @objc private func showOverview() { coordinator.activeSection = .overview; openMainWindow() }
    @objc private func showSleepGuard() { coordinator.activeSection = .sleepGuard; openMainWindow() }
    @objc private func showClipboardTab() { coordinator.activeSection = .clipboard; openMainWindow() }
    @objc private func showMenuBarTab() { coordinator.activeSection = .menuBar; openMainWindow() }
    @objc private func showRepoSyncTab() { coordinator.activeSection = .repoSync; openMainWindow() }
    @objc private func quitApp() { NSApp.terminate(nil) }
}
