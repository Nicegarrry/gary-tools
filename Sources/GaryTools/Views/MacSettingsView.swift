import AppKit
import GaryCore
import SwiftUI

/// Common macOS settings that are hard to find or have no switch at all in System Settings.
struct MacSettingsView: View {
    @ObservedObject var model: MacSettingsModel
    /// The Repo Sync folder, used as the developer folder.
    let developerDir: String

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
            developerFolder
            Hairline().padding(.vertical, 20)
            browser
            Hairline().padding(.vertical, 20)
            chrome
            Hairline().padding(.vertical, 20)
            fileTypes
            Hairline().padding(.vertical, 20)
            finder
        }
        .onAppear {
            model.refresh()
            model.refreshDeveloperFolder(developerDir)
            model.refreshDeveloperTools()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
            model.refreshDeveloperFolder(developerDir)
            model.refreshDeveloperTools()
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

    // MARK: Developer folder

    private var developerFolder: some View {
        let display = ScreenshotLocation.display(DeveloperFolder.resolve(developerDir))
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Developer Setup",
                           detail: "One home for every repo (the folder Repo Sync keeps fresh) and the tools a new Mac needs.")
            HStack(spacing: 10) {
                Text(display)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(AppTheme.sky)
                StatusPill(text: model.developerFolderExists ? "Set up" : "Missing",
                           color: model.developerFolderExists ? AppTheme.positive : AppTheme.warning)
                Spacer()
                if model.developerFolderExists {
                    Button("Show") { NSWorkspace.shared.open(DeveloperFolder.resolve(developerDir)) }
                        .buttonStyle(FlatButtonStyle(compact: true))
                    Button("Add to Finder Sidebar") { model.addDeveloperFolderToSidebar(developerDir) }
                        .buttonStyle(FlatButtonStyle(primary: true, compact: true))
                        .help("Selects the folder in Finder and uses File > Add to Sidebar (⌃⌘T).")
                } else {
                    Button("Create \(display)") { model.createDeveloperFolder(developerDir) }
                        .buttonStyle(FlatButtonStyle(primary: true, compact: true))
                }
            }
            .padding(.vertical, 6)
            toolRow(name: "Command Line Tools", detail: "git, clang and make, from Apple", path: model.commandLineToolsPath,
                    action: "Install…", help: "Opens Apple's installer.") { model.installCommandLineTools() }
            toolRow(name: "Homebrew", detail: "The Mac package manager", path: model.homebrewPath,
                    action: "Install…", help: "Runs Homebrew's official install script in Terminal, where you can watch it.") { model.installHomebrew() }
        }
    }

    private func toolRow(name: String, detail: String, path: String?, action: String, help: String,
                         install: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: path == nil ? "circle.dashed" : "checkmark.circle.fill")
                .foregroundStyle(path == nil ? AppTheme.muted : AppTheme.positive)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: .medium))
                Text(path ?? detail).font(.system(size: 11, design: path == nil ? .default : .monospaced))
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
            if path == nil {
                Button(action, action: install)
                    .buttonStyle(FlatButtonStyle(compact: true))
                    .help(help)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Google Chrome",
                           detail: "Install Chrome, and choose where it saves downloads in every Chrome profile.")
            if model.chromeApp == nil {
                HStack(spacing: 10) {
                    switch model.chromeInstall {
                    case .working(let step):
                        ProgressView().controlSize(.small)
                        Text(step).font(.system(size: 12.5)).foregroundStyle(AppTheme.secondary)
                    case .failed(let reason):
                        Text(reason).font(.system(size: 12)).foregroundStyle(AppTheme.warning)
                    case .idle:
                        Text("Chrome isn't installed.").font(.system(size: 13))
                    }
                    Spacer()
                    Button("Install Chrome") { model.installChrome() }
                        .buttonStyle(FlatButtonStyle(primary: true, compact: true))
                        .disabled(model.isInstallingChrome)
                        .help("Downloads Chrome from Google, checks it is signed by Google, and copies it to /Applications.")
                }
                .padding(.vertical, 6)
            } else {
                HStack(spacing: 10) {
                    appLabel(model.chromeApp)
                    if model.chromeRunning {
                        StatusPill(text: "Running", color: AppTheme.sky)
                    }
                    Spacer()
                    if model.chromeRunning {
                        Button("Quit Chrome") { model.quitChrome() }
                            .buttonStyle(FlatButtonStyle(compact: true))
                            .help("Chrome rewrites its settings while it runs, so the download folder can only change while it is quit.")
                    }
                    Button("Change Download Folder…") { model.chooseChromeDownloadFolder() }
                        .buttonStyle(FlatButtonStyle(primary: true, compact: true))
                        .disabled(model.chromeRunning || model.chromeProfiles.isEmpty)
                }
                .padding(.vertical, 6)
                if model.chromeProfiles.isEmpty {
                    Text("Open Chrome once to create a profile, then come back.")
                        .font(.system(size: 12)).foregroundStyle(AppTheme.muted)
                }
                ForEach(model.chromeProfiles, id: \.profile.id) { item in
                    HStack {
                        Text(item.profile.name).font(.system(size: 12.5))
                        Spacer()
                        Text(item.folder.map { ScreenshotLocation.display(URL(fileURLWithPath: $0)) } ?? "~/Downloads")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(AppTheme.sky)
                    }
                    .padding(.vertical, 3)
                }
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
