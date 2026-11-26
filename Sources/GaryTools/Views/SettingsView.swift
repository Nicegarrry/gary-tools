import AppKit
import GaryCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @LocalState var pane: SettingsPane
    @LocalState private var clipPrefs: ClipboardPreferences
    @LocalState private var savedBanner = false

    init(coordinator: AppCoordinator, initialPane: SettingsPane = .general) {
        self.coordinator = coordinator
        _pane = LocalState(initialValue: initialPane)
        _clipPrefs = LocalState(initialValue: coordinator.clipboardStore.preferences)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(AppTheme.hairline).frame(width: 1).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(pane.rawValue).font(.system(size: 26, weight: .regular))
                    Text(pane.subtitle).font(.system(size: 12.5)).foregroundStyle(AppTheme.secondary)
                }
                .padding(.top, 42)
                .padding(.horizontal, 30)
                .padding(.bottom, 20)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch pane {
                        case .general: generalPane
                        case .sleepGuard: sleepGuardPane
                        case .clipboard: clipboardPane
                        case .menuBar: menuBarPane
                        case .permissions: permissionsPane
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 24)
                }

                Hairline().padding(.horizontal, 30)
                HStack {
                    if savedBanner {
                        Label("Clipboard preferences saved", systemImage: "checkmark").font(.system(size: 11)).foregroundStyle(AppTheme.positive)
                    } else {
                        Label("All settings stay local on this Mac", systemImage: "lock").font(.system(size: 11)).foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    if pane == .clipboard {
                        Button("Save Clipboard Settings") {
                            if coordinator.clipboardStore.updatePreferences(clipPrefs) {
                                coordinator.reconfigureHotKeys()
                                savedBanner = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedBanner = false }
                            }
                        }
                        .buttonStyle(FlatButtonStyle(primary: true, compact: true))
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 16)
            }
        }
        .foregroundStyle(AppTheme.text)
        .tint(AppTheme.rust)
        .background(GlassBackground(radius: 0))
        .preferredColorScheme(.dark)
        .ignoresSafeArea(.container, edges: .top)
        .frame(width: 820, height: 610)
        .onAppear { coordinator.refreshSystemState() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                GaryBrandMark(size: 24)
                Text("Settings").font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 20)
            .padding(.top, 50)
            .padding(.bottom, 24)

            ForEach(SettingsPane.allCases) { item in
                let selected = pane == item
                Button { pane = item } label: {
                    HStack(spacing: 11) {
                        Capsule().fill(selected ? AppTheme.rust : .clear).frame(width: 3, height: 18)
                        Image(systemName: item.symbol).font(.system(size: 13)).frame(width: 16)
                            .foregroundStyle(selected ? AppTheme.sky : AppTheme.muted)
                        Text(item.rawValue).font(.system(size: 13, weight: selected ? .medium : .regular))
                            .foregroundStyle(selected ? AppTheme.text : AppTheme.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 9)
                    .padding(.trailing, 16)
                    .background(selected ? Color.white.opacity(0.045) : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text(versionLabel)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(AppTheme.muted)
                .padding(20)
        }
        .frame(width: 195)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.deepNavy.opacity(0.35))
    }

    private var versionLabel: String {
        let shortCommit = String(coordinator.appBuildCommit.prefix(7))
        return shortCommit.isEmpty ? "Gary Tools \(coordinator.appVersion)" : "Gary Tools \(coordinator.appVersion) · \(shortCommit)"
    }

    // MARK: - General

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Updates & Setup", detail: "Check for new builds from GitHub or re-run the guided setup.")
            updatesCard
                .padding(.bottom, 12)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("First-Run Setup Wizard")
                        .font(.system(size: 13, weight: .medium))
                    Text("Walk through permissions, Git & GitHub setup, synced folders, and quick Mac defaults.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.secondary)
                }
                Spacer()
                Button("Run Setup Wizard…") {
                    coordinator.openSetupWizard()
                }
                .buttonStyle(FlatButtonStyle(compact: true))
            }
            .padding(.vertical, 6)

            Hairline().padding(.vertical, 20)

            SectionHeading(title: "Startup & Login", detail: "Keep Gary Tools ready whenever you sign in.")
            ToggleRow(
                title: "Launch Gary Tools at login",
                detail: "Registers Gary Tools as a macOS Login Item.",
                isOn: Binding(
                    get: { coordinator.loginEnabled || coordinator.loginNeedsApproval },
                    set: { coordinator.setLoginEnabled($0) }
                )
            )
            if coordinator.loginNeedsApproval {
                HStack {
                    Text("Allow Gary Tools in System Settings → General → Login Items.")
                        .font(.system(size: 11.5)).foregroundStyle(AppTheme.sky)
                    Spacer()
                    Button("Open Login Items…") { coordinator.openLoginItemsSettings() }
                        .buttonStyle(FlatButtonStyle(compact: true))
                }
                .padding(.top, 6)
            }
            if let error = coordinator.loginError {
                Text(error).font(.system(size: 11.5)).foregroundStyle(AppTheme.warning).padding(.top, 6)
            }

            ToggleRow(
                title: "Start Sleep Guard background daemon at login",
                detail: "Runs the lightweight background watcher and hourly repo sync LaunchAgent.",
                isOn: Binding(get: { coordinator.lidGuard.startAtLogin }, set: { coordinator.lidGuard.startAtLogin = $0 })
            )
            ToggleRow(
                title: "Turn Sleep Guard on automatically at login",
                detail: coordinator.lidGuard.turnOnAtLogin ? "Restores whatever on/off state it had." : "Starts switched off — toggle on when you need it.",
                isOn: Binding(get: { coordinator.lidGuard.turnOnAtLogin }, set: { coordinator.lidGuard.turnOnAtLogin = $0 })
            )
            .disabled(!coordinator.lidGuard.startAtLogin)

            Hairline().padding(.vertical, 20)

            SectionHeading(title: "Menu Bar", detail: "Gary Tools always provides a unified menu bar hub and Dock icon.")
            ToggleRow(
                title: "Enable Menu Bar Organizer (ArrowBar chevron)",
                detail: "Adds the dedicated « / » menu bar toggle to tuck away third-party icons.",
                isOn: Binding(get: { coordinator.arrowBar.enabled }, set: { coordinator.arrowBar.enabled = $0 })
            )
        }
    }

    private var updatesCard: some View {
        let updater = coordinator.updater
        let shortCommit = String(coordinator.appBuildCommit.prefix(7))
        let buildTitle = shortCommit.isEmpty ? "v\(coordinator.appVersion)" : "v\(coordinator.appVersion) · \(shortCommit)"

        return HStack(spacing: 12) {
            updateStatusIcon(for: updater.state)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(buildTitle)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                    updateStatusPill(for: updater.state)
                }
                Text(updateStatusDetail(for: updater.state))
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 10)
            HStack(spacing: 8) {
                Button("Check for Updates") {
                    updater.checkForUpdates(silent: false)
                }
                .buttonStyle(FlatButtonStyle(compact: true))
                .disabled(updater.isBusy)

                if case .available = updater.state {
                    Button("Update & Relaunch") {
                        updater.installUpdate()
                    }
                    .buttonStyle(FlatButtonStyle(primary: true, compact: true))
                    .disabled(updater.isBusy)
                }
            }
        }
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))
    }

    @ViewBuilder
    private func updateStatusIcon(for state: AppUpdater.State) -> some View {
        switch state {
        case .checking, .updating:
            ProgressView().controlSize(.small).frame(width: 18, height: 18)
        case .upToDate:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.positive)
        case .available:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.rust)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.warning)
        case .idle:
            Image(systemName: "arrow.triangle.2.circlepath.circle")
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.sky)
        }
    }

    @ViewBuilder
    private func updateStatusPill(for state: AppUpdater.State) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .checking:
            StatusPill(text: "Checking…", color: AppTheme.sky)
        case .upToDate:
            StatusPill(text: "Up to date", color: AppTheme.positive)
        case .available(let info):
            StatusPill(text: "\(info.commitsBehind) new", color: AppTheme.rust)
        case .updating:
            StatusPill(text: "Updating…", color: AppTheme.sky)
        case .failed:
            StatusPill(text: "Error", color: AppTheme.warning)
        }
    }

    private func updateStatusDetail(for state: AppUpdater.State) -> String {
        switch state {
        case .idle:
            if let last = coordinator.updater.lastChecked {
                return "Last checked \(last.formatted(date: .abbreviated, time: .shortened))."
            }
            return "Checks GitHub for newer Gary Tools builds."
        case .checking:
            return "Checking GitHub for the latest commit…"
        case .upToDate(let commit):
            return "Running the latest build (\(String(commit.prefix(7))))."
        case .available(let info):
            let count = "\(info.commitsBehind) new \(info.commitsBehind == 1 ? "commit" : "commits") available"
            if let first = info.summaryLines.first {
                return "\(count) — \(first)"
            }
            return "\(count) (\(info.currentCommit) → \(info.latestCommit))."
        case .updating(let step):
            return step
        case .failed(let message):
            return message
        }
    }

    // MARK: - Sleep Guard

    private var sleepGuardPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Daemon Timing", detail: "Changes save automatically and apply within seconds.")
            StepRow(title: coordinator.lidGuard.herdrInstalled ? "Check agents & lid every" : "Check status & lid every",
                    value: "\(coordinator.lidGuard.checkEvery) s",
                    number: Binding(get: { coordinator.lidGuard.checkEvery }, set: { coordinator.lidGuard.checkEvery = $0 }),
                    range: 1...60, step: 1)
            StepRow(title: "Wait after agents stop", value: "\(coordinator.lidGuard.waitBeforeSleep) s",
                    number: Binding(get: { coordinator.lidGuard.waitBeforeSleep }, set: { coordinator.lidGuard.waitBeforeSleep = $0 }),
                    range: 0...300, step: 5)
            StepRow(title: "Wait when an agent asks for input", value: coordinator.lidGuard.waitForInput == 0 ? "Don’t wait" : "\(coordinator.lidGuard.waitForInput) min",
                    number: Binding(get: { coordinator.lidGuard.waitForInput }, set: { coordinator.lidGuard.waitForInput = $0 }),
                    range: 0...10, step: 1)

            Hairline().padding(.vertical, 20)

            SectionHeading(title: "Safety Rules")
            StepRow(title: "Battery cut-off", value: "\(coordinator.lidGuard.minBattery)%",
                    number: Binding(get: { coordinator.lidGuard.minBattery }, set: { coordinator.lidGuard.minBattery = $0 }),
                    range: 5...90, step: 5)
            ToggleRow(title: "Let Mac sleep in Low Power Mode",
                      isOn: Binding(get: { coordinator.lidGuard.sleepInLowPower }, set: { coordinator.lidGuard.sleepInLowPower = $0 }))
            StepRow(title: "Lid-closed battery limit", value: "\(coordinator.lidGuard.hoursString) h",
                    number: Binding(get: { coordinator.lidGuard.batteryLimitHours }, set: { coordinator.lidGuard.batteryLimitHours = $0 }),
                    range: 0.5...24, step: 0.5)

            Hairline().padding(.vertical, 20)

            SectionHeading(title: "Repo Sync")
            ToggleRow(title: "Auto-pull git repos while awake",
                      isOn: Binding(get: { coordinator.lidGuard.autoPullRepos }, set: { coordinator.lidGuard.autoPullRepos = $0 }))
            StepRow(title: "Pull interval", value: coordinator.lidGuard.intervalLabel,
                    number: Binding(get: { coordinator.lidGuard.autoPullIntervalMinutes }, set: { coordinator.lidGuard.autoPullIntervalMinutes = $0 }),
                    range: 15...360, step: 15)
                .disabled(!coordinator.lidGuard.autoPullRepos)
        }
    }

    // MARK: - Clipboard

    private var clipboardPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "History & Storage", detail: "Pinned clips are always kept.")
            settingRow("Keep unpinned clips") {
                ChoiceMenu(label: "History age", selection: $clipPrefs.retentionDays,
                           options: [("1 day", 1), ("7 days", 7), ("30 days", 30), ("90 days", 90), ("Forever", 0)])
            }
            settingRow("Clip limit") {
                ChoiceMenu(label: "Clip limit", selection: $clipPrefs.maxClips,
                           options: [("100 clips", 100), ("500 clips", 500), ("1,000 clips", 1000), ("5,000 clips", 5000)])
            }
            settingRow("Storage limit") {
                ChoiceMenu(label: "Storage limit", selection: $clipPrefs.maxHistoryMB,
                           options: [("100 MB", 100), ("500 MB", 500), ("1 GB", 1000), ("2 GB", 2000)])
            }
            settingRow("Maximum capture size") {
                ChoiceMenu(label: "Maximum capture size", selection: $clipPrefs.maxCaptureMB,
                           options: [("5 MB", 5), ("20 MB", 20), ("50 MB", 50)])
            }

            Hairline().padding(.vertical, 20)

            SectionHeading(title: "Keyboard & Paste")
            HStack(spacing: 14) {
                Text("Clipboard browser shortcut").font(.system(size: 13))
                Spacer()
                ChoiceMenu(label: "Modifiers", selection: $clipPrefs.shortcutModifiers,
                           options: [("⌃⌥ Control Option", "controlOption"), ("⌘⇧ Command Shift", "commandShift"), ("⌘⌥ Command Option", "commandOption")])
                ChoiceMenu(label: "Key", selection: $clipPrefs.shortcutKey, options: [("V", "V"), ("Space", "Space"), ("B", "B")])
            }
            .padding(.vertical, 8)
            ToggleRow(title: "Paste directly into previous app", detail: "Requires macOS Accessibility access.", isOn: $clipPrefs.pasteDirectly)

            Hairline().padding(.vertical, 20)

            SectionHeading(title: "Privacy", detail: "Bundle IDs to exclude, one per line.")
            ToggleRow(title: "Skip confidential content", detail: "Respects concealed/password pasteboard markers.", isOn: $clipPrefs.ignoreConfidential)
            ToggleRow(title: "Skip transient content", detail: "Ignores temporary and auto-generated copies.", isOn: $clipPrefs.ignoreTransient)
            TextEditor(text: $clipPrefs.excludedApps)
                .font(.system(size: 11.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 110)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .padding(.top, 8)

            Hairline().padding(.vertical, 20)

            HStack {
                Text("\(coordinator.clipboardStore.clips.count) clips · \(ByteCountFormatter.string(fromByteCount: Int64(coordinator.clipboardStore.historyBytes), countStyle: .file))")
                    .font(.system(size: 12)).foregroundStyle(AppTheme.secondary)
                Spacer()
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: coordinator.clipboardStore.root.path)
                }
                .buttonStyle(FlatButtonStyle(compact: true))
                Button("Clear Unpinned…") { coordinator.eraseClipboardHistory() }
                    .buttonStyle(FlatButtonStyle(compact: true))
            }
        }
    }

    // MARK: - Menu Bar

    private var menuBarPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Organizer Behavior", detail: "Controls how the Menu Bar Organizer hides and reveals icons.")
            ToggleRow(
                title: "Enable Menu Bar Organizer",
                detail: "Shows the « / » chevron in the menu bar and enables tuck-away controls.",
                isOn: Binding(get: { coordinator.arrowBar.enabled }, set: { coordinator.arrowBar.enabled = $0 })
            )
            ToggleRow(
                title: "Start with icons tucked away",
                isOn: Binding(get: { coordinator.arrowBar.startCollapsed }, set: { coordinator.arrowBar.startCollapsed = $0 })
            )
            .disabled(!coordinator.arrowBar.enabled)
            ToggleRow(
                title: "Expand when hovering top-right menu bar",
                detail: "Briefly hover over the right side of the menu bar to reveal all icons.",
                isOn: Binding(get: { coordinator.arrowBar.expandOnHover }, set: { coordinator.arrowBar.expandOnHover = $0 })
            )
            .disabled(!coordinator.arrowBar.enabled)
            ToggleRow(
                title: "Show floating recovery pill while tucked",
                detail: "Keeps a small ‘Show icons’ pill accessible just below the menu bar.",
                isOn: Binding(get: { coordinator.arrowBar.showRecoveryButton }, set: { coordinator.arrowBar.showRecoveryButton = $0 })
            )
            .disabled(!coordinator.arrowBar.enabled)

            Hairline().padding(.vertical, 20)

            HStack {
                Text("Global reveal shortcut").font(.system(size: 13))
                Spacer()
                Text(coordinator.arrowBar.revealShortcutAvailable ? "⌃⌥⌘Space (Active)" : "Unavailable (in use)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(coordinator.arrowBar.revealShortcutAvailable ? AppTheme.sky : AppTheme.warning)
            }
            Text("Uses macOS Menu Bar visibility control for instant hide/reveal with automatic restore on quit. macOS pauses Live Activity pills while icons are tucked; click the arrow, hover the menu bar, or press ⌃⌥⌘Space to reveal anytime.")
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.muted)
                .lineSpacing(3)
                .padding(.top, 12)
        }
    }

    // MARK: - Permissions

    private var permissionsPane: some View {
        let perms = coordinator.permissions
        return VStack(alignment: .leading, spacing: 12) {
            if let message = perms.actionMessage, !message.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle").foregroundStyle(AppTheme.sky)
                    Text(message).font(.system(size: 12)).foregroundStyle(AppTheme.text)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.sky.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            permissionRow(
                title: "Accessibility",
                detail: "Enables direct paste into the previous app (Clipboard), window titles in Context Grab, and Finder sidebar helper.",
                ok: perms.accessibilityGranted,
                buttonTitle: "Grant Access…",
                action: { perms.requestAccessibility() }
            )
            permissionRow(
                title: "Screen Recording",
                detail: "Enables screenshots and on-device OCR in Context Grab.",
                ok: perms.screenRecordingGranted,
                buttonTitle: "Grant Access…",
                action: { perms.requestScreenRecording() }
            )
            permissionRow(
                title: "Menu Bar Control",
                detail: coordinator.arrowBar.visibility.available
                    ? "Uses native menu bar visibility control — hides unpinned third-party icons immediately and restores automatically on quit."
                    : "Native menu bar hiding requires macOS 27 or later. Other Gary Tools features work normally.",
                ok: coordinator.arrowBar.visibility.available,
                notReadyLabel: "macOS 27+ only",
                neutralWhenNotReady: true,
                buttonTitle: nil,
                action: nil
            )
            permissionRow(
                title: "Sleep Guard Daemon",
                detail: coordinator.lidGuard.statusMessage,
                ok: perms.daemonRunning,
                buttonTitle: "Install / Start Daemon",
                action: { perms.installOrRepairDaemon() }
            )
            permissionRow(
                title: "Passwordless pmset Rule",
                detail: "Allows Keep Awake and Sleep Guard to keep your Mac awake with the lid closed without prompting for sudo.",
                ok: perms.pmsetRuleInstalled,
                buttonTitle: "Allow pmset…",
                action: { perms.installPmsetRule() }
            )

            Hairline().padding(.vertical, 10)

            HStack {
                Button("Open Data Folder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: GaryToolsPaths.appSupportRoot.path)
                }
                .buttonStyle(FlatButtonStyle(compact: true))
                Button("Open Daemon Log") { coordinator.lidGuard.openLog() }
                    .buttonStyle(FlatButtonStyle(compact: true))
                Spacer()
                Button("Refresh Status") {
                    coordinator.refreshAll()
                    coordinator.permissions.refresh()
                    coordinator.lidGuard.checkEnvironment()
                    coordinator.arrowBar.refresh()
                }
                .buttonStyle(FlatButtonStyle(compact: true))
            }
        }
        .onAppear {
            coordinator.refreshAll()
            coordinator.refreshSystemState()
            coordinator.lidGuard.checkEnvironment()
            coordinator.permissions.startLivePolling()
        }
        .onDisappear {
            coordinator.permissions.stopLivePolling()
        }
    }

    private func permissionRow(
        title: String,
        detail: String,
        ok: Bool,
        notReadyLabel: String = "Not Installed",
        neutralWhenNotReady: Bool = false,
        buttonTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : (neutralWhenNotReady ? "minus.circle.fill" : "exclamationmark.circle.fill"))
                .foregroundStyle(ok ? AppTheme.positive : (neutralWhenNotReady ? AppTheme.muted : AppTheme.warning))
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let buttonTitle, let action, !ok {
                Button(buttonTitle, action: action).buttonStyle(FlatButtonStyle(primary: true, compact: true))
            } else {
                StatusPill(
                    text: ok ? "Ready" : notReadyLabel,
                    color: ok ? AppTheme.positive : (neutralWhenNotReady ? AppTheme.muted : AppTheme.warning)
                )
            }
        }
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))
    }

    private func settingRow<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer(minLength: 16)
            control()
        }
        .padding(.vertical, 8)
    }
}
