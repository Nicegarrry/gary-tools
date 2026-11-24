import SwiftUI

struct MainWindowView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(AppTheme.hairline).frame(width: 1).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch coordinator.activeSection {
                        case .overview:
                            DashboardView(coordinator: coordinator)
                        case .sleepGuard:
                            SleepGuardView(lidGuard: coordinator.lidGuard)
                        case .clipboard:
                            ClipboardHomeView(coordinator: coordinator)
                        case .menuBar:
                            MenuBarOrganizerView(model: coordinator.arrowBar)
                        case .repoSync:
                            RepoSyncView(lidGuard: coordinator.lidGuard)
                        case .macSettings:
                            MacSettingsView(model: coordinator.macSettings)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 28)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(AppTheme.text)
        .tint(AppTheme.rust)
        .background(GlassBackground(radius: 0))
        .preferredColorScheme(.dark)
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 820, idealWidth: 940, minHeight: 580, idealHeight: 650)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(coordinator.activeSection.rawValue)
                    .font(.system(size: 28, weight: .regular))
                Text(coordinator.activeSection.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.secondary)
            }
            Spacer(minLength: 16)
            headerAction
        }
        .padding(.top, 44)
        .padding(.horizontal, 32)
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private var headerAction: some View {
        switch coordinator.activeSection {
        case .overview:
            Button {
                coordinator.openClipboardBrowser()
            } label: {
                Label("Clipboard  ⌃⌥V", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(FlatButtonStyle(primary: true, compact: true))
        case .sleepGuard:
            Button {
                coordinator.lidGuard.keepAwake ? coordinator.lidGuard.stopKeepAwake() : coordinator.lidGuard.startKeepAwake(until: nil)
            } label: {
                Label(coordinator.lidGuard.keepAwake ? "Stop Keep Awake" : "Keep Awake",
                      systemImage: coordinator.lidGuard.keepAwake ? "cup.and.heat.waves.fill" : "cup.and.heat.waves")
            }
            .buttonStyle(FlatButtonStyle(primary: !coordinator.lidGuard.keepAwake, compact: true))
        case .clipboard:
            HStack(spacing: 8) {
                Button("New Snippet") { coordinator.editClip(nil) }
                    .buttonStyle(FlatButtonStyle(compact: true))
                Button("Open Browser  ⌃⌥V") { coordinator.openClipboardBrowser() }
                    .buttonStyle(FlatButtonStyle(primary: true, compact: true))
            }
        case .menuBar:
            Button(coordinator.arrowBar.visibility.isCollapsed ? "Show All Icons" : "Tuck Away Icons") {
                coordinator.arrowBar.toggle()
            }
            .buttonStyle(FlatButtonStyle(primary: !coordinator.arrowBar.visibility.isCollapsed, compact: true))
            .disabled(!coordinator.arrowBar.enabled || !coordinator.arrowBar.conflictingManagers.isEmpty || !coordinator.arrowBar.visibility.available || coordinator.arrowBar.visibility.isWorking)
        case .repoSync:
            Button(coordinator.lidGuard.pullingNow ? "Pulling…" : "Pull Repos Now") {
                coordinator.lidGuard.triggerPullNow()
            }
            .buttonStyle(FlatButtonStyle(primary: true, compact: true))
            .disabled(coordinator.lidGuard.pullingNow)
        case .macSettings:
            Button {
                coordinator.macSettings.restoreOriginals()
            } label: {
                Label("Undo All Changes", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(FlatButtonStyle(compact: true))
            .disabled(!coordinator.macSettings.hasChanges)
            .help("Puts back every setting as it was before Gary Tools first changed it.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 11) {
                GaryBrandMark(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Gary Tools").font(.system(size: 14, weight: .semibold))
                    Text("v\(coordinator.appVersion)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 52)
            .padding(.bottom, 26)

            ForEach(MainSection.allCases) { section in
                sidebarRow(section)
            }

            Spacer()

            Hairline().padding(.horizontal, 18).padding(.bottom, 10)

            Button {
                coordinator.openSettings(nil)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .frame(width: 18)
                        .foregroundStyle(AppTheme.secondary)
                    Text("Settings…")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.text)
                    Spacer()
                    Text("⌘,")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Image(systemName: "lock")
                    .font(.system(size: 9))
                Text("Local · On this Mac")
                    .font(.system(size: 10.5))
            }
            .foregroundStyle(AppTheme.muted)
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 18)
        }
        .frame(width: 210)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.deepNavy.opacity(0.35))
    }

    private func sidebarRow(_ section: MainSection) -> some View {
        let selected = coordinator.activeSection == section
        return Button {
            coordinator.activeSection = section
        } label: {
            HStack(spacing: 11) {
                Capsule()
                    .fill(selected ? AppTheme.rust : .clear)
                    .frame(width: 3, height: 18)
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                    .frame(width: 18)
                    .foregroundStyle(selected ? AppTheme.sky : AppTheme.muted)
                Text(section.rawValue)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? AppTheme.text : AppTheme.secondary)
                Spacer()
                sidebarBadge(for: section)
            }
            .padding(.vertical, 9)
            .padding(.trailing, 16)
            .background(selected ? Color.white.opacity(0.045) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func sidebarBadge(for section: MainSection) -> some View {
        switch section {
        case .sleepGuard:
            if coordinator.lidGuard.keepAwake {
                Circle().fill(AppTheme.rust).frame(width: 6, height: 6)
            } else if coordinator.lidGuard.daemonState == "awake" {
                Circle().fill(AppTheme.positive).frame(width: 6, height: 6)
            }
        case .clipboard:
            if coordinator.clipboardStore.paused {
                Image(systemName: "pause.fill").font(.system(size: 8)).foregroundStyle(AppTheme.warning)
            }
        case .menuBar:
            if coordinator.arrowBar.visibility.isCollapsed {
                Circle().fill(AppTheme.sky).frame(width: 6, height: 6)
            }
        case .repoSync:
            if coordinator.lidGuard.pullingNow {
                ProgressView().controlSize(.mini)
            }
        case .overview, .macSettings:
            EmptyView()
        }
    }
}
