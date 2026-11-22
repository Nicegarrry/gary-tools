import SwiftUI

struct MenuBarOrganizerView: View {
    @ObservedObject var model: ArrowBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !model.conflictingManagers.isEmpty {
                notice("Quit \(model.conflictingManagers.joined(separator: ", ")) to let Gary Tools manage your menu bar icons.", icon: "pause.circle")
            }
            if let error = model.visibility.errorMessage {
                notice(error, icon: "exclamationmark.triangle")
            } else if !model.visibility.available {
                notice("Menu bar visibility control is unavailable on this macOS version.", icon: "exclamationmark.triangle")
            }
            if let error = model.nativeVisibility.lastError {
                notice(error, icon: "exclamationmark.triangle")
            }

            if !model.nativeVisibility.hasAccess {
                HStack(spacing: 14) {
                    Image(systemName: "lock.shield").font(.system(size: 18)).foregroundStyle(AppTheme.sky)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Allow per-app menu bar control").font(.system(size: 13, weight: .medium))
                        Text("Select group.com.apple.controlcenter.plist once so Gary Tools can hide third-party icons while keeping Live Activities intact.")
                            .font(.system(size: 11.5)).foregroundStyle(AppTheme.secondary)
                    }
                    Spacer()
                    Button("Allow Access…") {
                        model.nativeVisibility.requestAccess()
                        if model.nativeVisibility.hasAccess { model.revealAll() }
                    }
                    .buttonStyle(FlatButtonStyle(primary: true, compact: true))
                }
                .padding(14)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.sky.opacity(0.3), lineWidth: 1))
            }

            // Toolbar: search + refresh + edit layout
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.muted)
                    TextField("Find an app", text: $model.search).textFieldStyle(.plain).font(.system(size: 13))
                    if !model.search.isEmpty {
                        Button { model.search = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.muted)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))

                if model.catalog.scanning { ProgressView().controlSize(.small) }
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(FlatButtonStyle(compact: true))
                    .help("Refresh apps")
                Button(model.editing ? "Done Editing" : "Edit Layout") {
                    if model.editing { model.finishEditing() } else { model.beginEditing() }
                }
                .buttonStyle(FlatButtonStyle(primary: model.editing, compact: true))
                .keyboardShortcut("e", modifiers: .command)
            }

            if model.editing {
                Text("Drag apps between columns. All icons stay revealed while you edit.")
                    .font(.system(size: 12)).foregroundStyle(AppTheme.secondary)
                HStack(alignment: .top, spacing: 14) {
                    column(pinned: true, title: "Always visible", symbol: "pin")
                    column(pinned: false, title: "Tucked away", symbol: "chevron.left")
                }
                .frame(minHeight: 280)
            } else {
                VStack(spacing: 0) {
                    if model.displayedApps.isEmpty {
                        emptyState
                    } else {
                        ForEach(model.displayedApps) { app in
                            HStack(spacing: 12) {
                                appIdentity(app)
                                Spacer()
                                Toggle("Always visible", isOn: Binding(
                                    get: { model.policy.isPinned(app.id) },
                                    set: { model.setPinned(app.id, $0) }
                                ))
                                .toggleStyle(.switch).controlSize(.small).tint(AppTheme.rust)
                                .accessibilityLabel("Keep \(app.name) always visible")
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            if app.id != model.displayedApps.last?.id {
                                Hairline().padding(.horizontal, 14)
                            }
                        }
                    }
                }
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))
            }

            // Footer controls
            HStack(spacing: 12) {
                if !model.catalog.accessibilityGranted {
                    Text("Showing running apps. Grant Accessibility to filter to apps with menu bar icons.")
                        .font(.system(size: 11.5)).foregroundStyle(AppTheme.muted)
                    Spacer()
                    Button("Enable Icon Detection…") { model.catalog.requestAccessibility() }
                        .buttonStyle(FlatButtonStyle(compact: true))
                } else {
                    Toggle("Include other running apps", isOn: $model.showAllRunningApps)
                        .toggleStyle(.switch).controlSize(.small).tint(AppTheme.rust)
                        .font(.system(size: 12))
                    Spacer()
                }
                Button("Add App…") { model.catalog.addApplication() }
                    .buttonStyle(FlatButtonStyle(compact: true))
            }
            .padding(.top, 4)
        }
    }

    private func column(pinned: Bool, title: String, symbol: String) -> some View {
        let apps = model.displayedApps.filter { model.policy.isPinned($0.id) == pinned }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: symbol).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(AppTheme.sky)
                Spacer()
                Text("\(apps.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(AppTheme.muted)
            }
            VStack(spacing: 7) {
                ForEach(apps) { app in
                    HStack(spacing: 9) {
                        Image(systemName: "line.3.horizontal").font(.caption).foregroundStyle(AppTheme.muted)
                        appIdentity(app)
                        Spacer(minLength: 0)
                        Button { model.setPinned(app.id, !pinned) } label: {
                            Image(systemName: pinned ? "arrow.right" : "arrow.left").foregroundStyle(AppTheme.sky)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(9)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .contentShape(Rectangle())
                    .draggable(app.id)
                }
                if apps.isEmpty {
                    Text("Drop apps here")
                        .font(.system(size: 12)).foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 100)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))
        .dropDestination(for: String.self) { ids, _ in
            let valid = ids.filter { id in model.catalog.apps.contains(where: { $0.id == id }) }
            for id in valid { model.setPinned(id, pinned) }
            return !valid.isEmpty
        }
    }

    private func appIdentity(_ app: CatalogApp) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if !app.isRunning {
                    Text("Not running").font(.system(size: 10.5)).foregroundStyle(AppTheme.muted)
                }
            }
        }
        .help(app.id)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "menubar.rectangle").font(.system(size: 26, weight: .ultraLight)).foregroundStyle(AppTheme.sky)
            Text(model.search.isEmpty ? "No menu bar apps found yet" : "No matching apps").font(.system(size: 14, weight: .medium))
            Text("Refresh while your icons are revealed, or add an app below.")
                .font(.system(size: 12)).foregroundStyle(AppTheme.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private func notice(_ text: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(AppTheme.warning)
            Text(text).font(.system(size: 12)).foregroundStyle(AppTheme.text)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(AppTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
