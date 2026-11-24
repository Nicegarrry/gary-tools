import GaryCore
import SwiftUI

struct RepoSyncView: View {
    @ObservedObject var lidGuard: LidGuardModel
    @ObservedObject var gitSetup: GitSetupModel
    var onOpenSetup: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sync status strip
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18))
                    .foregroundStyle(AppTheme.sky)
                VStack(alignment: .leading, spacing: 3) {
                    Text(lidGuard.lastGitSyncText)
                        .font(.system(size: 13.5, weight: .medium))
                    Text("\(folderSummary)  ·  \(lidGuard.repoCount) git \(lidGuard.repoCount == 1 ? "repo" : "repos")  ·  Fast-forward only (git pull --ff-only)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                StatusPill(
                    text: lidGuard.autoPullRepos ? "Auto · \(lidGuard.intervalLabel)" : "Manual",
                    color: lidGuard.autoPullRepos ? AppTheme.positive : AppTheme.muted
                )
            }
            .padding(14)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))
            .padding(.bottom, 14)

            // Compact Git & GitHub Status strip
            gitStatusStrip
                .padding(.bottom, 22)

            // Folders to Sync
            HStack(alignment: .top, spacing: 12) {
                SectionHeading(
                    title: "Folders to Sync",
                    detail: "Gary Tools scans each folder up to 2 levels deep for git repositories."
                )
                Spacer()
                HStack(spacing: 8) {
                    StatusPill(
                        text: "\(lidGuard.repoCount) \(lidGuard.repoCount == 1 ? "repo" : "repos")",
                        color: lidGuard.repoCount > 0 ? AppTheme.sky : AppTheme.muted
                    )
                    Button {
                        lidGuard.chooseAutoPullFolder()
                    } label: {
                        Label("Add Folder…", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(FlatButtonStyle(primary: lidGuard.autoPullDirs.isEmpty, compact: true))
                }
            }

            if lidGuard.autoPullDirs.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "folder.badge.questionmark")
                        .foregroundStyle(AppTheme.muted)
                    Text("No folders configured yet. Click “Add Folder…” to pick a directory containing git repos.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondary)
                    Spacer()
                }
                .padding(14)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))
            } else {
                VStack(spacing: 8) {
                    ForEach(lidGuard.autoPullDirs, id: \.self) { dir in
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.sky)
                            Text(dir)
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundStyle(AppTheme.text)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                lidGuard.removeAutoPullFolder(dir)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(AppTheme.muted)
                                    .frame(width: 26, height: 26)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Remove folder from Repo Sync")
                            .accessibilityLabel("Remove \(dir)")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))
                    }
                }
            }

            Hairline().padding(.vertical, 20)

            SectionHeading(
                title: "Background Auto-Pull",
                detail: "Keeps clean git repositories up to date while your Mac is awake, even when Sleep Guard is turned off."
            )
            ToggleRow(
                title: "Auto-pull git repos while awake",
                detail: "Runs in parallel with a lockfile so it never collides with agent hooks or overwrites uncommitted changes.",
                isOn: $lidGuard.autoPullRepos
            )
            StepRow(
                title: "Pull every",
                value: lidGuard.intervalLabel,
                number: $lidGuard.autoPullIntervalMinutes,
                range: 15...360,
                step: 15
            )
            .disabled(!lidGuard.autoPullRepos)

            Hairline().padding(.vertical, 20)

            SectionHeading(
                title: "Agent SessionStart Hooks",
                detail: "Automatically fast-forward repos when starting a new session inside your configured folders."
            )

            if let message = gitSetup.message, !message.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(AppTheme.sky)
                    Text(message).font(.system(size: 12)).foregroundStyle(AppTheme.text)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AppTheme.sky.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(.bottom, 10)
            }

            let visibleHooks = gitSetup.hooks.filter { $0.clientDetected || $0.installed }
            if visibleHooks.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "terminal")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.muted)
                    Text("No supported coding agent CLIs detected (Claude Code, Codex, Antigravity). Install one to enable automatic SessionStart pulls.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))
            } else {
                VStack(spacing: 8) {
                    ForEach(visibleHooks) { hook in
                        HStack(spacing: 12) {
                            Image(systemName: hook.installed ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(hook.installed ? AppTheme.positive : AppTheme.muted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hook.kind.displayName).font(.system(size: 13, weight: .medium))
                                Text(hook.path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(AppTheme.muted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            StatusPill(
                                text: hook.installed ? "Active" : "Not configured",
                                color: hook.installed ? AppTheme.positive : AppTheme.muted
                            )
                            if hook.installed {
                                Button("Remove") {
                                    gitSetup.uninstallHook(hook.kind)
                                }
                                .buttonStyle(FlatButtonStyle(compact: true))
                            } else {
                                Button("Install") {
                                    gitSetup.installHook(hook.kind, dirs: lidGuard.autoPullDirs)
                                }
                                .buttonStyle(FlatButtonStyle(primary: true, compact: true))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))
                    }
                }
            }
        }
        .onAppear {
            lidGuard.checkEnvironment()
            lidGuard.refreshRepoCount()
            gitSetup.refresh()
        }
    }

    private var folderSummary: String {
        let count = lidGuard.autoPullDirs.count
        if count == 1, let first = lidGuard.autoPullDirs.first {
            return "Folder: \(first)"
        }
        return "\(count) \(count == 1 ? "folder" : "folders")"
    }

    private var gitStatusStrip: some View {
        let status = gitSetup.status
        let identityText: String = status.hasIdentity
            ? "\(status.userName) <\(status.userEmail)>"
            : "Git identity not configured"
        let authText: String = {
            if let account = status.ghAccount, !account.isEmpty {
                return "GitHub @\(account)"
            }
            if !status.sshKeyNames.isEmpty {
                return "SSH keys ready"
            }
            return "GitHub not connected"
        }()

        return HStack(spacing: 12) {
            Image(systemName: status.isReady ? "checkmark.seal.fill" : "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 15))
                .foregroundStyle(status.isReady ? AppTheme.positive : AppTheme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(identityText)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(status.hasIdentity ? AppTheme.text : AppTheme.secondary)
                    .lineLimit(1)
                Text(authText)
                    .font(.system(size: 11))
                    .foregroundStyle(status.hasGitHubAuth ? AppTheme.positive : AppTheme.muted)
            }
            Spacer()
            if !status.hasGitHubAuth {
                Button("Sign in to GitHub…") {
                    gitSetup.launchGitHubLogin()
                }
                .buttonStyle(FlatButtonStyle(compact: true))
            }
            if !status.isReady, let onOpenSetup {
                Button("Open Setup…") {
                    onOpenSetup()
                }
                .buttonStyle(FlatButtonStyle(primary: !status.hasIdentity, compact: true))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))
    }
}
