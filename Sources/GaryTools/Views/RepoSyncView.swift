import SwiftUI

struct RepoSyncView: View {
    @ObservedObject var lidGuard: LidGuardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status strip
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18))
                    .foregroundStyle(AppTheme.sky)
                VStack(alignment: .leading, spacing: 3) {
                    Text(lidGuard.lastGitSyncText)
                        .font(.system(size: 13.5, weight: .medium))
                    Text("Folder: \(lidGuard.autoPullDir)  ·  Fast-forward only (git pull --ff-only)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                StatusPill(text: lidGuard.autoPullRepos ? "Auto · \(lidGuard.intervalLabel)" : "Manual",
                           color: lidGuard.autoPullRepos ? AppTheme.positive : AppTheme.muted)
            }
            .padding(14)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))
            .padding(.bottom, 22)

            SectionHeading(title: "Background Auto-Pull", detail: "Keeps clean git repositories up to date while your Mac is awake, even when Sleep Guard is turned off.")
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

            HStack {
                Text("Target folder").font(.system(size: 13))
                Spacer()
                Text(lidGuard.autoPullDir)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(AppTheme.sky)
            }
            .padding(.vertical, 8)

            Hairline().padding(.vertical, 20)

            SectionHeading(title: "Agent SessionStart Hooks", detail: "Automatically fast-forward repos when starting a new session inside ~/Developer.")
            VStack(spacing: 8) {
                ForEach(lidGuard.sessionHooks) { hook in
                    HStack(spacing: 12) {
                        Image(systemName: hook.installed ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(hook.installed ? AppTheme.positive : AppTheme.muted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hook.name).font(.system(size: 13, weight: .medium))
                            Text(hook.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                        StatusPill(text: hook.installed ? "Active" : "Not configured", color: hook.installed ? AppTheme.positive : AppTheme.muted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))
                }
            }
            .onAppear { lidGuard.checkEnvironment() }
        }
    }
}
