import AppKit
import GaryCore
import SwiftUI

struct SetupWizardView: View {
    @ObservedObject var coordinator: AppCoordinator
    let onFinish: () -> Void

    @LocalState private var step: WizardStep = .welcome
    @LocalState private var gitName = ""
    @LocalState private var gitEmail = ""
    @LocalState private var didSeedGitFields = false

    init(coordinator: AppCoordinator, onFinish: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onFinish = onFinish
    }

    private enum WizardStep: Int, CaseIterable, Identifiable {
        case welcome = 0
        case permissions = 1
        case gitAndSync = 2
        case macSetup = 3
        case finish = 4

        var id: Int { rawValue }

        var shortTitle: String {
            switch self {
            case .welcome: return "Welcome"
            case .permissions: return "Permissions"
            case .gitAndSync: return "Git & Sync"
            case .macSetup: return "Mac Setup"
            case .finish: return "All Set"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progressHeader
            Hairline().padding(.horizontal, 32)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch step {
                    case .welcome: welcomeStep
                    case .permissions: permissionsStep
                    case .gitAndSync: gitAndSyncStep
                    case .macSetup: macSetupStep
                    case .finish: finishStep
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 22)
                .padding(.bottom, 24)
            }

            Hairline().padding(.horizontal, 32)
            footer
        }
        .foregroundStyle(AppTheme.text)
        .tint(AppTheme.rust)
        .background(GlassBackground(radius: 0))
        .preferredColorScheme(.dark)
        .ignoresSafeArea(.container, edges: .top)
        .frame(width: 720, height: 590)
        .onAppear {
            coordinator.refreshSystemState()
            coordinator.permissions.refresh()
        }
        .onDisappear {
            coordinator.permissions.stopLivePolling()
        }
    }

    // MARK: - Progress Bar

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                GaryBrandMark(size: 22)
                Text("Gary Tools Setup")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Step \(step.rawValue + 1) of \(WizardStep.allCases.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppTheme.muted)
            }

            HStack(spacing: 0) {
                ForEach(WizardStep.allCases) { item in
                    let isCurrent = item == step
                    let isDone = item.rawValue < step.rawValue
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            step = item
                        }
                    } label: {
                        HStack(spacing: 7) {
                            ZStack {
                                Circle()
                                    .fill(isCurrent ? AppTheme.rust : isDone ? AppTheme.positive.opacity(0.22) : Color.white.opacity(0.06))
                                    .frame(width: 20, height: 20)
                                if isDone {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundStyle(AppTheme.positive)
                                } else {
                                    Text("\(item.rawValue + 1)")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(isCurrent ? Color.white : AppTheme.muted)
                                }
                            }
                            Text(item.shortTitle)
                                .font(.system(size: 11.5, weight: isCurrent ? .semibold : .regular))
                                .foregroundStyle(isCurrent ? AppTheme.text : isDone ? AppTheme.secondary : AppTheme.muted)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if item != WizardStep.allCases.last {
                        Rectangle()
                            .fill(item.rawValue < step.rawValue ? AppTheme.positive.opacity(0.45) : AppTheme.hairline)
                            .frame(height: 1)
                            .padding(.horizontal, 8)
                    }
                }
            }
        }
        .padding(.top, 38)
        .padding(.horizontal, 32)
        .padding(.bottom, 16)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if step != .welcome {
                Button("Back") {
                    if let prev = WizardStep(rawValue: step.rawValue - 1) {
                        withAnimation(.easeInOut(duration: 0.18)) { step = prev }
                    }
                }
                .buttonStyle(FlatButtonStyle(compact: true))
            } else {
                Label("All data stays local on this Mac", systemImage: "lock")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.muted)
            }

            Spacer()

            if step != .finish {
                if step != .welcome {
                    Button("Skip") {
                        advanceStep()
                    }
                    .buttonStyle(FlatButtonStyle(compact: true))
                }
                Button("Next") {
                    advanceStep()
                }
                .buttonStyle(FlatButtonStyle(primary: true, compact: true))
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Open Gary Tools") {
                    coordinator.permissions.stopLivePolling()
                    onFinish()
                }
                .buttonStyle(FlatButtonStyle(primary: true, compact: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
    }

    private func advanceStep() {
        if let next = WizardStep(rawValue: step.rawValue + 1) {
            withAnimation(.easeInOut(duration: 0.18)) { step = next }
        }
    }

    // MARK: - Step 1: Welcome & Utilities

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                GaryBrandMark(size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Gary Tools")
                        .font(.system(size: 24, weight: .regular))
                    Text("Local utilities for your Mac, private by default.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("CHOOSE YOUR UTILITIES")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(AppTheme.muted)
                    .padding(.bottom, 6)

                ToggleRow(
                    title: "Launch Gary Tools at login",
                    detail: "Keep clipboard history, global shortcuts, and menu bar controls ready when you sign in.",
                    isOn: Binding(
                        get: { coordinator.loginEnabled || coordinator.loginNeedsApproval },
                        set: { coordinator.setLoginEnabled($0) }
                    )
                )
                if coordinator.loginNeedsApproval {
                    HStack {
                        Text("Approve Gary Tools in System Settings → General → Login Items.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.sky)
                        Spacer()
                        Button("Open Login Items…") { coordinator.openLoginItemsSettings() }
                            .buttonStyle(FlatButtonStyle(compact: true))
                    }
                    .padding(.bottom, 6)
                }
                if let error = coordinator.loginError {
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.warning)
                        .padding(.bottom, 6)
                }

                Hairline().padding(.vertical, 6)

                ToggleRow(
                    title: "Menu Bar Organizer",
                    detail: coordinator.arrowBar.visibility.available
                        ? "Adds a clean « / » chevron to tuck away third-party menu bar icons."
                        : "Requires macOS 27+. Other Gary Tools features work normally on your current macOS.",
                    isOn: Binding(
                        get: { coordinator.arrowBar.visibility.available && coordinator.arrowBar.enabled },
                        set: { coordinator.arrowBar.enabled = $0 }
                    )
                )
                .disabled(!coordinator.arrowBar.visibility.available)

                Hairline().padding(.vertical, 6)

                ToggleRow(
                    title: "Background Repo Sync",
                    detail: "Fast-forward pulls clean git repositories hourly while your Mac is awake.",
                    isOn: Binding(
                        get: { coordinator.lidGuard.autoPullRepos },
                        set: { coordinator.lidGuard.autoPullRepos = $0 }
                    )
                )

                if coordinator.lidGuard.herdrInstalled {
                    Hairline().padding(.vertical, 6)
                    ToggleRow(
                        title: "Sleep Guard (Herdr agent watcher)",
                        detail: "Keeps your Mac awake with the lid closed while coding agents work.",
                        isOn: Binding(
                            get: { coordinator.lidGuard.enabled },
                            set: { coordinator.lidGuard.enabled = $0 }
                        )
                    )
                }
            }
            .padding(18)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))

            if !coordinator.lidGuard.herdrInstalled {
                HStack(spacing: 10) {
                    Image(systemName: "cup.and.heat.waves")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.sky)
                    Text("Keep Awake is ready anytime from the menu bar to hold your Mac awake for 1 hour, 3 hours, or overnight.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(AppTheme.sky.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppTheme.sky.opacity(0.18), lineWidth: 1))
            }
        }
    }

    // MARK: - Step 2: Permissions

    private var permissionsStep: some View {
        let perms = coordinator.permissions
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "macOS Permissions",
                detail: "Grant access as needed — status updates live as soon as macOS approves each item."
            )

            if let message = perms.actionMessage, !message.isEmpty {
                infoCallout(symbol: "info.circle", color: AppTheme.sky, text: message)
            }

            permissionCard(
                title: "Accessibility",
                detail: "Direct paste from Clipboard, window titles in Context Grab, and Finder sidebar helper.",
                ok: perms.accessibilityGranted,
                readyLabel: "Granted",
                missingLabel: "Needed",
                buttonTitle: "Grant Access…",
                action: { perms.requestAccessibility() }
            )

            permissionCard(
                title: "Screen Recording",
                detail: "Screenshots and on-device OCR in Context Grab.",
                ok: perms.screenRecordingGranted,
                readyLabel: "Granted",
                missingLabel: "Needed",
                buttonTitle: "Grant Access…",
                action: { perms.requestScreenRecording() }
            )

            permissionCard(
                title: "Background Daemon",
                detail: "Runs Sleep Guard and hourly Repo Sync even when the main window is closed.",
                ok: perms.daemonRunning,
                readyLabel: "Running",
                missingLabel: perms.daemonInstalled ? "Stopped" : "Not Installed",
                buttonTitle: "Install Daemon",
                action: { perms.installOrRepairDaemon() }
            )

            permissionCard(
                title: "Lid-Close Sleep Control (Optional)",
                detail: "Lets Keep Awake and Sleep Guard keep your Mac awake with the lid closed (macOS admin prompt).",
                ok: perms.pmsetRuleInstalled,
                readyLabel: "Allowed",
                missingLabel: "Optional",
                buttonTitle: "Allow pmset…",
                isOptional: true,
                action: { perms.installPmsetRule() }
            )

            HStack(spacing: 12) {
                Image(systemName: coordinator.arrowBar.visibility.available ? "checkmark.circle.fill" : "minus.circle.fill")
                    .foregroundStyle(coordinator.arrowBar.visibility.available ? AppTheme.positive : AppTheme.muted)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Menu Bar Control").font(.system(size: 13, weight: .medium))
                    Text(coordinator.arrowBar.visibility.available
                         ? "Native macOS menu bar visibility control is available."
                         : "Native icon hiding requires macOS 27 or later. Everything else works normally.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                StatusPill(
                    text: coordinator.arrowBar.visibility.available ? "Ready" : "macOS 27+ only",
                    color: coordinator.arrowBar.visibility.available ? AppTheme.positive : AppTheme.muted
                )
            }
            .padding(13)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))

            if !perms.isStablySigned {
                infoCallout(
                    symbol: "signature",
                    color: AppTheme.warning,
                    text: "This build uses an ad-hoc signature, so macOS resets permissions after rebuilding. Run ./scripts/setup-signing.sh once to create a stable local certificate."
                )
            }
        }
        .onAppear {
            coordinator.permissions.startLivePolling()
        }
        .onDisappear {
            coordinator.permissions.stopLivePolling()
        }
    }

    private func permissionCard(
        title: String,
        detail: String,
        ok: Bool,
        readyLabel: String,
        missingLabel: String,
        buttonTitle: String,
        isOptional: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : (isOptional ? "circle.dashed" : "exclamationmark.circle.fill"))
                .foregroundStyle(ok ? AppTheme.positive : (isOptional ? AppTheme.muted : AppTheme.warning))
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            if ok {
                StatusPill(text: readyLabel, color: AppTheme.positive)
            } else {
                HStack(spacing: 8) {
                    StatusPill(text: missingLabel, color: isOptional ? AppTheme.muted : AppTheme.warning)
                    Button(buttonTitle, action: action)
                        .buttonStyle(FlatButtonStyle(primary: !isOptional, compact: true))
                }
            }
        }
        .padding(13)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))
    }

    // MARK: - Step 3: Git & Repo Sync

    private var gitAndSyncStep: some View {
        let gitStatus = coordinator.gitSetup.status
        let lg = coordinator.lidGuard
        let detectedHooks = coordinator.gitSetup.detectedHooks()

        return VStack(alignment: .leading, spacing: 16) {
            SectionHeading(
                title: "Git & Repo Sync",
                detail: "Confirm your Git identity, connect GitHub, and choose which repository folders to keep fresh."
            )

            if let message = coordinator.gitSetup.message, !message.isEmpty {
                infoCallout(symbol: "info.circle", color: AppTheme.sky, text: message)
            }

            // Card 1: Git Identity & GitHub Auth
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("GIT IDENTITY & GITHUB AUTH")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.9)
                        .foregroundStyle(AppTheme.muted)
                    Spacer()
                    StatusPill(
                        text: gitStatus.hasIdentity ? "Identity set" : "Identity needed",
                        color: gitStatus.hasIdentity ? AppTheme.positive : AppTheme.warning
                    )
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name").font(.system(size: 11)).foregroundStyle(AppTheme.secondary)
                        TextField("Your Name", text: $gitName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email").font(.system(size: 11)).foregroundStyle(AppTheme.secondary)
                        TextField("you@example.com", text: $gitEmail)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(" ").font(.system(size: 11))
                        Button("Save Git Identity") {
                            coordinator.gitSetup.saveIdentity(name: gitName, email: gitEmail)
                        }
                        .buttonStyle(FlatButtonStyle(primary: !gitStatus.hasIdentity, compact: true))
                        .disabled(
                            gitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || gitEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                }

                Hairline().padding(.vertical, 2)

                HStack(spacing: 10) {
                    Text("GitHub Access")
                        .font(.system(size: 12.5, weight: .medium))
                    if let account = gitStatus.ghAccount, !account.isEmpty {
                        StatusPill(text: "Signed in as @\(account)", color: AppTheme.positive)
                    } else if !gitStatus.sshKeyNames.isEmpty {
                        StatusPill(text: "SSH keys ready", color: AppTheme.positive)
                    } else {
                        StatusPill(text: "Not connected", color: AppTheme.warning)
                    }
                    Spacer()
                    Button("Refresh") {
                        coordinator.gitSetup.refresh()
                    }
                    .buttonStyle(FlatButtonStyle(compact: true))
                    .disabled(coordinator.gitSetup.isRefreshing)

                    Button("Sign in to GitHub…") {
                        coordinator.gitSetup.launchGitHubLogin()
                    }
                    .buttonStyle(FlatButtonStyle(primary: !gitStatus.hasGitHubAuth, compact: true))
                }
            }
            .padding(16)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))

            // Card 2: Folders to Sync
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("FOLDERS TO SYNC")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.9)
                        .foregroundStyle(AppTheme.muted)
                    Spacer()
                    Button {
                        lg.chooseAutoPullFolder()
                    } label: {
                        Label("Add Folder…", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(FlatButtonStyle(compact: true))
                }

                if lg.autoPullDirs.isEmpty {
                    Text("No folders selected yet. Add a folder that holds your git repositories.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.muted)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 6) {
                        ForEach(lg.autoPullDirs, id: \.self) { dir in
                            HStack(spacing: 10) {
                                Image(systemName: "folder")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.sky)
                                Text(dir)
                                    .font(.system(size: 12.5, design: .monospaced))
                                    .foregroundStyle(AppTheme.text)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    lg.removeAutoPullFolder(dir)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppTheme.muted)
                                        .frame(width: 24, height: 24)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Remove folder from Repo Sync")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }

                Text("Found \(lg.repoCount) git \(lg.repoCount == 1 ? "repo" : "repos") (fast-forward pull only — never overwrites uncommitted work)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondary)
            }
            .padding(16)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))

            // Card 3: Agent Session Hooks (Optional)
            VStack(alignment: .leading, spacing: 10) {
                Text("AGENT SESSION HOOKS (OPTIONAL)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(AppTheme.muted)

                if detectedHooks.isEmpty {
                    Text("No supported agent CLIs detected (Claude Code, Codex, Antigravity) — you can enable hooks later in Repo Sync.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.muted)
                } else {
                    VStack(spacing: 8) {
                        ForEach(detectedHooks) { hook in
                            HStack(spacing: 10) {
                                Image(systemName: hook.installed ? "checkmark.circle.fill" : "circle.dashed")
                                    .foregroundStyle(hook.installed ? AppTheme.positive : AppTheme.muted)
                                Text(hook.kind.displayName)
                                    .font(.system(size: 12.5, weight: .medium))
                                Spacer()
                                StatusPill(
                                    text: hook.installed ? "Installed" : "Off",
                                    color: hook.installed ? AppTheme.positive : AppTheme.muted
                                )
                                if hook.installed {
                                    Button("Remove") {
                                        coordinator.gitSetup.uninstallHook(hook.kind)
                                    }
                                    .buttonStyle(FlatButtonStyle(compact: true))
                                } else {
                                    Button("Install Hook") {
                                        coordinator.gitSetup.installHook(hook.kind, dirs: lg.autoPullDirs)
                                    }
                                    .buttonStyle(FlatButtonStyle(primary: true, compact: true))
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))
        }
        .onAppear {
            coordinator.gitSetup.refresh()
            coordinator.lidGuard.refreshRepoCount()
            seedGitFieldsIfNeeded()
        }
        .onChange(of: coordinator.gitSetup.status) {
            seedGitFieldsIfNeeded()
        }
    }

    private func seedGitFieldsIfNeeded() {
        let status = coordinator.gitSetup.status
        if !didSeedGitFields || (gitName.isEmpty && !status.userName.isEmpty) {
            gitName = status.userName
        }
        if !didSeedGitFields || (gitEmail.isEmpty && !status.userEmail.isEmpty) {
            gitEmail = status.userEmail
        }
        if !status.userName.isEmpty || !status.userEmail.isEmpty {
            didSeedGitFields = true
        }
    }

    // MARK: - Step 4: Quick Mac Setup

    private var macSetupStep: some View {
        let ms = coordinator.macSettings
        let quickFinderToggles = resolvedQuickFinderToggles()

        return VStack(alignment: .leading, spacing: 16) {
            SectionHeading(
                title: "Quick Mac Setup (Optional)",
                detail: "A few helpful developer defaults that are buried or missing in System Settings."
            )

            if let message = ms.message, !message.isEmpty {
                infoCallout(symbol: "info.circle", color: AppTheme.sky, text: message)
            }

            // Screenshots folder card
            VStack(alignment: .leading, spacing: 10) {
                Text("SCREENSHOTS")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(AppTheme.muted)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Screenshot folder")
                            .font(.system(size: 13, weight: .medium))
                        Text(ScreenshotLocation.display(ms.screenshotFolder))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(AppTheme.sky)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Choose Folder…") {
                        ms.chooseScreenshotFolder()
                    }
                    .buttonStyle(FlatButtonStyle(compact: true))
                }
            }
            .padding(16)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))

            // Quick Finder toggles card
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("FINDER")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.9)
                        .foregroundStyle(AppTheme.muted)
                    Spacer()
                    if ms.finderNeedsRelaunch {
                        Button("Relaunch Finder") {
                            ms.relaunchFinder()
                        }
                        .buttonStyle(FlatButtonStyle(primary: true, compact: true))
                    }
                }
                .padding(.bottom, 4)

                ForEach(quickFinderToggles) { toggle in
                    ToggleRow(
                        title: toggle.title,
                        detail: toggle.detail,
                        isOn: Binding(
                            get: { ms.value(of: toggle) },
                            set: { ms.set(toggle, $0) }
                        )
                    )
                }
            }
            .padding(16)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))

            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.muted)
                Text("Every change can be undone in Mac Settings → Undo All Changes.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondary)
            }
        }
        .onAppear {
            coordinator.macSettings.refresh()
            let firstDir = coordinator.lidGuard.autoPullDirs.first ?? coordinator.lidGuard.autoPullDir
            coordinator.macSettings.refreshDeveloperFolder(firstDir)
        }
    }

    private func resolvedQuickFinderToggles() -> [MacToggle] {
        let preferredKeys = ["AppleShowAllFiles", "AppleShowAllExtensions"]
        let matched = preferredKeys.compactMap { key in
            MacSettingsCatalog.finderToggles.first { $0.key == key }
        }
        return matched.isEmpty ? Array(MacSettingsCatalog.finderToggles.prefix(2)) : matched
    }

    // MARK: - Step 5: All Set

    private var finishStep: some View {
        let perms = coordinator.permissions
        let coreGranted = (perms.accessibilityGranted ? 1 : 0) + (perms.screenRecordingGranted ? 1 : 0)
        let folderCount = coordinator.lidGuard.autoPullDirs.count
        let repoCount = coordinator.lidGuard.repoCount

        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppTheme.positive.opacity(0.16))
                        .frame(width: 42, height: 42)
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.positive)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("You’re all set")
                        .font(.system(size: 24, weight: .regular))
                    Text("Gary Tools is configured and ready in your menu bar.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondary)
                }
            }

            // Summary card
            VStack(spacing: 10) {
                summaryRow(
                    symbol: "checkmark.shield",
                    title: "Permissions",
                    value: "\(coreGranted) of 2 core granted · Daemon \(perms.daemonRunning ? "running" : "standby")",
                    color: perms.allCorePermissionsGranted ? AppTheme.positive : AppTheme.sky
                )
                Hairline()
                summaryRow(
                    symbol: "arrow.triangle.2.circlepath",
                    title: "Repo Sync",
                    value: "\(folderCount) \(folderCount == 1 ? "folder" : "folders") · \(repoCount) git \(repoCount == 1 ? "repo" : "repos")",
                    color: AppTheme.sky
                )
                Hairline()
                summaryRow(
                    symbol: "arrow.down.circle",
                    title: "Updates",
                    value: updateStatusSummary,
                    color: coordinator.updater.hasUpdate ? AppTheme.rust : AppTheme.positive
                )
            }
            .padding(16)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))

            // Keyboard Shortcuts Grid
            VStack(alignment: .leading, spacing: 10) {
                Text("GLOBAL SHORTCUTS")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(AppTheme.muted)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 10) {
                    shortcutTile(keys: "⌃⌥V", title: "Clipboard Browser", detail: "Search clips & snippets")
                    shortcutTile(keys: "⌃⌥P", title: "Paste Stack", detail: "Queue items to paste in order")
                    shortcutTile(keys: "⌃⌥G", title: "Context Grab", detail: "Capture window, screenshot & OCR")
                    shortcutTile(keys: "⌃⌥⌘Space", title: "Reveal Menu Bar", detail: "Show tucked menu bar icons")
                }
            }
        }
    }

    private var updateStatusSummary: String {
        switch coordinator.updater.state {
        case .idle:
            let commitSuffix = coordinator.appBuildCommit.isEmpty ? "" : " (\(String(coordinator.appBuildCommit.prefix(7))))"
            return "v\(coordinator.appVersion)\(commitSuffix)"
        case .checking:
            return "Checking for updates…"
        case .upToDate(let commit):
            return "Up to date (\(String(commit.prefix(7))))"
        case .available(let info):
            return "\(info.commitsBehind) new \(info.commitsBehind == 1 ? "commit" : "commits") available"
        case .updating(let status):
            return status
        case .failed:
            return "v\(coordinator.appVersion) · Check in Settings"
        }
    }

    private func summaryRow(symbol: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondary)
        }
    }

    private func shortcutTile(keys: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.sky)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(AppTheme.deepNavy.opacity(0.8), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(AppTheme.sky.opacity(0.25), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(AppTheme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))
    }

    private func infoCallout(symbol: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color.opacity(0.22), lineWidth: 1))
    }
}
