import AppKit
import GaryCore
import SwiftUI

/// Common macOS settings that are hard to find or have no switch at all in System Settings.
struct MacSettingsView: View {
    @ObservedObject var model: MacSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = model.message {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle").foregroundStyle(AppTheme.sky)
                    Text(message).font(.system(size: 12)).foregroundStyle(AppTheme.text)
                    Spacer()
                    Button { model.message = nil } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.sky.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.bottom, 18)
            }

            screenshots
            Hairline().padding(.vertical, 20)
            browser
            Hairline().padding(.vertical, 20)
            fileTypes
            Hairline().padding(.vertical, 20)
            finder
        }
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }

    // MARK: Screenshots

    private var screenshots: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Screenshots", detail: "Where ⌘⇧3, ⌘⇧4 and ⌘⇧5 save, and how the files look.")
            HStack(spacing: 10) {
                Text("Save to").font(.system(size: 13))
                Spacer()
                Text(ScreenshotLocation.display(model.screenshotFolder))
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(AppTheme.sky)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Show") { model.revealScreenshotFolder() }
                    .buttonStyle(FlatButtonStyle(compact: true))
                Button("Change…") { model.chooseScreenshotFolder() }
                    .buttonStyle(FlatButtonStyle(primary: true, compact: true))
            }
            .padding(.vertical, 6)
            HStack {
                Text("File format").font(.system(size: 13))
                Spacer()
                ChoiceMenu(
                    label: "Screenshot format",
                    selection: Binding(get: { model.screenshotFormat }, set: { model.setScreenshotFormat($0) }),
                    options: ScreenshotFormat.allCases.map { ($0.label, $0) }
                )
            }
            .padding(.vertical, 6)
            ForEach(MacSettingsCatalog.screenshotToggles) { toggle in
                toggleRow(toggle)
            }
        }
    }

    // MARK: Browser

    private var browser: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Default Browser", detail: "Opens every web link. macOS asks you to confirm the switch.")
            HStack(spacing: 10) {
                appLabel(model.currentBrowser)
                Spacer()
                appMenu(
                    label: "Change Browser",
                    choices: model.browsers,
                    current: model.currentBrowser,
                    pick: { model.setDefaultBrowser($0) },
                    other: { model.chooseOtherBrowser() }
                )
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: File types

    private var fileTypes: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Default Apps for File Types",
                           detail: "What opens when you double-click a file. Set a whole group at once, or one extension at a time.")
            ForEach(FileTypeCatalog.groups) { group in
                let items = model.fileTypes.filter { item in group.entries.contains(item.entry) }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(group.name.uppercased())
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(AppTheme.muted)
                        Spacer()
                        appMenu(
                            label: "Set All",
                            choices: uniqueChoices(items),
                            current: nil,
                            pick: { model.setDefault($0, for: items) },
                            other: { model.chooseOtherApp(for: items) }
                        )
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                    ForEach(items) { item in
                        fileTypeRow(item)
                    }
                }
            }
        }
    }

    private func fileTypeRow(_ item: FileTypeDefault) -> some View {
        HStack(spacing: 12) {
            Text(".\(item.entry.ext)")
                .font(.system(size: 12.5, design: .monospaced))
                .frame(width: 84, alignment: .leading)
            appLabel(item.current, small: true)
            if let caution = item.entry.caution {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.warning)
                    .help(caution)
            }
            Spacer()
            appMenu(
                label: "Change",
                choices: model.choices(for: item),
                current: item.current,
                pick: { model.setDefault($0, for: [item]) },
                other: { model.chooseOtherApp(for: [item]) }
            )
            .disabled(item.type == nil)
        }
        .padding(.vertical, 3)
    }

    private func uniqueChoices(_ items: [FileTypeDefault]) -> [AppChoice] {
        var seen = Set<String>()
        return items.flatMap { model.choices(for: $0) }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Finder

    private var finder: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                SectionHeading(title: "Finder", detail: "Developer-friendly Finder settings that have no switch in System Settings.")
                Spacer()
                if model.finderNeedsRelaunch {
                    Button("Relaunch Finder") { model.relaunchFinder() }
                        .buttonStyle(FlatButtonStyle(primary: true, compact: true))
                        .help("Finder reads these settings when it starts. Open Finder windows come back.")
                }
            }
            ForEach(MacSettingsCatalog.finderToggles) { toggle in
                toggleRow(toggle)
            }
        }
    }

    // MARK: Pieces

    private func toggleRow(_ toggle: MacToggle) -> some View {
        ToggleRow(
            title: toggle.title,
            detail: toggle.detail,
            isOn: Binding(get: { model.value(of: toggle) }, set: { model.set(toggle, $0) })
        )
    }

    @ViewBuilder
    private func appLabel(_ app: AppChoice?, small: Bool = false) -> some View {
        if let app {
            HStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: small ? 16 : 22, height: small ? 16 : 22)
                Text(app.name).font(.system(size: small ? 12.5 : 13.5, weight: small ? .regular : .medium))
            }
        } else {
            Text("No app set").font(.system(size: 12.5)).foregroundStyle(AppTheme.muted)
        }
    }

    private func appMenu(label: String, choices: [AppChoice], current: AppChoice?,
                         pick: @escaping (AppChoice) -> Void, other: @escaping () -> Void) -> some View {
        Menu {
            ForEach(choices) { app in
                Button { pick(app) } label: {
                    if app == current { Label(app.name, systemImage: "checkmark") } else { Text(app.name) }
                }
            }
            if !choices.isEmpty { Divider() }
            Button("Other App…") { other() }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(AppTheme.muted)
            }
            .font(.system(size: 12))
            .foregroundStyle(AppTheme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(label)
    }
}
