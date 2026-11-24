import GaryCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var coordinator: AppCoordinator
    @LocalState private var dismissedUpdateBanner = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !dismissedUpdateBanner, case .available(let info) = coordinator.updater.state {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.rust)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update available — \(info.commitsBehind) new \(info.commitsBehind == 1 ? "commit" : "commits")")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(AppTheme.text)
                        if let summary = info.summaryLines.first {
                            Text(summary)
                                .font(.system(size: 11.5))
                                .foregroundStyle(AppTheme.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button("Update & Relaunch") {
                        coordinator.updater.installUpdate()
                    }
                    .buttonStyle(FlatButtonStyle(primary: true, compact: true))
                    .disabled(coordinator.updater.isBusy)

                    Button {
                        dismissedUpdateBanner = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.muted)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss update banner")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.rust.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.rust.opacity(0.32), lineWidth: 1))
            }

            if !coordinator.migratedItems.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.positive)
                    Text("Imported \(coordinator.migratedItems.joined(separator: ", ")).")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.text)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.positive.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // 2x2 Module Grid
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                sleepGuardCard
                clipboardCard
                menuBarCard
                repoSyncCard
            }

            // Permissions & System Health
            systemHealthStrip
        }
    }

    private var sleepGuardCard: some View {
        let lg = coordinator.lidGuard
        let pillColor: Color = lg.keepAwake ? AppTheme.rust
            : lg.daemonState == "awake" ? AppTheme.positive
            : lg.daemonRunning ? AppTheme.sky : AppTheme.warning
        let pillText = lg.keepAwake ? "Keep Awake"
            : lg.daemonState == "awake" ? "Holding Awake"
            : lg.enabled ? "Watching Agents"
            : lg.daemonRunning ? "Standby" : "Daemon Stopped"

        return moduleCard(
            title: "Sleep Guard",
            symbol: lg.keepAwake ? "cup.and.heat.waves.fill" : "cup.and.saucer",
            pill: (pillText, pillColor),
            destination: .sleepGuard
        ) {
            Text(lg.statusMessage)
                .font(.system(size: 12.5))
                .foregroundStyle(AppTheme.secondary)
                .lineLimit(2)
            Spacer(minLength: 10)
            HStack(spacing: 8) {
                if !lg.herdrInstalled && !lg.enabled {
                    Button(lg.keepAwake ? "Stop Keep Awake" : "Keep Awake 1h") {
                        if lg.keepAwake { lg.stopKeepAwake() }
                        else { lg.startKeepAwake(until: Date().addingTimeInterval(3600)) }
                    }
                    .buttonStyle(FlatButtonStyle(primary: !lg.keepAwake, compact: true))

                    Button("3h") {
                        lg.startKeepAwake(until: Date().addingTimeInterval(3 * 3600))
                    }
                    .buttonStyle(FlatButtonStyle(compact: true))
                } else {
                    Button(lg.enabled ? "Turn Off" : "Watch Agents") {
                        lg.enabled.toggle()
                    }
                    .buttonStyle(FlatButtonStyle(primary: !lg.enabled && !lg.keepAwake, compact: true))

                    Button(lg.keepAwake ? "Stop Keep Awake" : "Keep Awake 1h") {
                        if lg.keepAwake { lg.stopKeepAwake() }
                        else { lg.startKeepAwake(until: Date().addingTimeInterval(3600)) }
                    }
                    .buttonStyle(FlatButtonStyle(compact: true))
                }
            }
        }
    }

    private var clipboardCard: some View {
        let store = coordinator.clipboardStore
        let sizeText = ByteCountFormatter.string(fromByteCount: Int64(store.historyBytes), countStyle: .file)
        let latest = store.clips.first?.title ?? "Copy anything to start building history."

        return moduleCard(
            title: "Clipboard",
            symbol: "doc.on.clipboard",
            pill: (store.paused ? "Paused" : "\(store.clips.count) clips", store.paused ? AppTheme.warning : AppTheme.sky),
            destination: .clipboard
        ) {
            Text(latest)
                .font(.system(size: 12.5))
                .foregroundStyle(AppTheme.secondary)
                .lineLimit(2)
            Text("\(sizeText) stored locally\(store.stack.isEmpty ? "" : " · \(store.stack.count) in stack")")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.muted)
            Spacer(minLength: 10)
            HStack(spacing: 8) {
                Button("Open Browser") { coordinator.openClipboardBrowser() }
                    .buttonStyle(FlatButtonStyle(primary: true, compact: true))
                Button(store.paused ? "Resume" : "Pause") { coordinator.toggleClipboardPause() }
                    .buttonStyle(FlatButtonStyle(compact: true))
            }
        }
    }

    private var menuBarCard: some View {
        let ab = coordinator.arrowBar
        let pillText = !ab.enabled ? "Disabled"
            : !ab.visibility.available ? "Unavailable"
            : ab.visibility.isCollapsed ? "Icons Tucked" : "All Revealed"
        let pillColor: Color = !ab.enabled ? AppTheme.muted
            : !ab.visibility.available ? AppTheme.warning
            : ab.visibility.isCollapsed ? AppTheme.sky : AppTheme.positive

        return moduleCard(
            title: "Menu Bar",
            symbol: ab.visibility.isCollapsed ? "chevron.left.2" : "chevron.right.2",
            pill: (pillText, pillColor),
            destination: .menuBar
        ) {
            Text("\(ab.pinnedCount) pinned app\(ab.pinnedCount == 1 ? "" : "s") · Hover reveal \(ab.expandOnHover ? "on" : "off")")
                .font(.system(size: 12.5))
                .foregroundStyle(AppTheme.secondary)
                .lineLimit(2)
            Spacer(minLength: 10)
            HStack(spacing: 8) {
                Button(ab.visibility.isCollapsed ? "Show All Icons" : "Tuck Away") {
                    ab.toggle()
                }
                .buttonStyle(FlatButtonStyle(primary: !ab.visibility.isCollapsed, compact: true))
                .disabled(!ab.enabled || !ab.visibility.available || !ab.conflictingManagers.isEmpty)
                Button("Edit Layout") {
                    coordinator.activeSection = .menuBar
                    ab.beginEditing()
                }
                .buttonStyle(FlatButtonStyle(compact: true))
            }
        }
    }

    private var repoSyncCard: some View {
        let lg = coordinator.lidGuard
        let detectedHooks = coordinator.gitSetup.detectedHooks()
        let activeHooks = detectedHooks.filter(\.installed).count
        let folderText: String = {
            if lg.autoPullDirs.count == 1, let only = lg.autoPullDirs.first {
                return only
            }
            return "\(lg.autoPullDirs.count) \(lg.autoPullDirs.count == 1 ? "folder" : "folders")"
        }()
        let repoText = "\(lg.repoCount) \(lg.repoCount == 1 ? "repo" : "repos")"
        let hookSuffix = detectedHooks.isEmpty ? "" : " · \(activeHooks)/\(detectedHooks.count) hooks"

        return moduleCard(
            title: "Repo Sync",
            symbol: "arrow.triangle.2.circlepath",
            pill: (lg.autoPullRepos ? "Every \(lg.intervalLabel)" : "Manual", lg.autoPullRepos ? AppTheme.positive : AppTheme.muted),
            destination: .repoSync
        ) {
            Text(lg.lastGitSyncText)
                .font(.system(size: 12.5))
                .foregroundStyle(AppTheme.secondary)
                .lineLimit(2)
            Text("\(folderText) · \(repoText)\(hookSuffix)")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
            Spacer(minLength: 10)
            HStack(spacing: 8) {
                Button(lg.pullingNow ? "Pulling…" : "Pull Now") { lg.triggerPullNow() }
                    .buttonStyle(FlatButtonStyle(primary: true, compact: true))
                    .disabled(lg.pullingNow)
                Button(lg.autoPullRepos ? "Pause Auto" : "Enable Auto") {
                    lg.autoPullRepos.toggle()
                }
                .buttonStyle(FlatButtonStyle(compact: true))
            }
        }
    }

    private func moduleCard<Content: View>(
        title: String,
        symbol: String,
        pill: (String, Color),
        destination: MainSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.sky)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                StatusPill(text: pill.0, color: pill.1)
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(count: 2) { coordinator.activeSection = destination }
    }

    private var systemHealthStrip: some View {
        let perms = coordinator.permissions
        let menuBarAvailable = coordinator.arrowBar.visibility.available
        let menuBarWarn = coordinator.arrowBar.enabled && !menuBarAvailable

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SYSTEM & PERMISSIONS")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(AppTheme.muted)
                Spacer()
                Button("Manage in Settings…") { coordinator.openSettings(.permissions) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.sky)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                healthBadge(
                    title: "Accessibility",
                    status: perms.accessibilityGranted ? .ok : .warning,
                    detail: perms.accessibilityGranted ? "Direct paste ready" : "Needed for direct paste",
                    action: perms.accessibilityGranted ? nil : { perms.requestAccessibility() }
                )
                healthBadge(
                    title: "Screen Recording",
                    status: perms.screenRecordingGranted ? .ok : .warning,
                    detail: perms.screenRecordingGranted ? "Context Grab ready" : "Needed for screenshots & OCR",
                    action: perms.screenRecordingGranted ? nil : { perms.requestScreenRecording() }
                )
                healthBadge(
                    title: "Daemon",
                    status: perms.daemonRunning ? .ok : .warning,
                    detail: perms.daemonRunning ? "Running in background" : "Stopped",
                    action: perms.daemonRunning ? nil : { perms.installOrRepairDaemon() }
                )
                healthBadge(
                    title: "Menu Bar",
                    status: menuBarAvailable ? .ok : (menuBarWarn ? .warning : .neutral),
                    detail: menuBarAvailable ? "Native control ready" : "Requires macOS 27+",
                    action: nil
                )
            }
        }
    }

    private enum HealthStatus {
        case ok, warning, neutral
    }

    private func healthBadge(title: String, status: HealthStatus, detail: String, action: (() -> Void)?) -> some View {
        let symbol: String
        let color: Color
        switch status {
        case .ok:
            symbol = "checkmark.circle.fill"
            color = AppTheme.positive
        case .warning:
            symbol = "exclamationmark.circle.fill"
            color = AppTheme.warning
        case .neutral:
            symbol = "minus.circle.fill"
            color = AppTheme.muted
        }

        return HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(AppTheme.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let action {
                Button("Fix") { action() }
                    .buttonStyle(FlatButtonStyle(compact: true))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))
    }
}
