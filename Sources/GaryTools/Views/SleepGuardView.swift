import SwiftUI

struct SleepGuardView: View {
    @ObservedObject var lidGuard: LidGuardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Live status strip
            HStack(spacing: 12) {
                Image(systemName: lidGuard.keepAwake ? "cup.and.heat.waves.fill"
                      : lidGuard.daemonState == "awake" ? "cup.and.saucer.fill"
                      : lidGuard.daemonRunning ? "cup.and.saucer" : "exclamationmark.triangle")
                    .font(.system(size: 18))
                    .foregroundStyle(lidGuard.daemonRunning ? AppTheme.sky : AppTheme.warning)
                VStack(alignment: .leading, spacing: 3) {
                    Text(lidGuard.statusMessage).font(.system(size: 13.5, weight: .medium))
                    if !lidGuard.lastSleepMessage.isEmpty {
                        Text(lidGuard.lastSleepMessage).font(.system(size: 11.5)).foregroundStyle(AppTheme.muted)
                    }
                }
                Spacer()
                Button("Open Log") { lidGuard.openLog() }
                    .buttonStyle(FlatButtonStyle(compact: true))
            }
            .padding(14)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))
            .padding(.bottom, 22)

            SectionHeading(title: "Herdr Agents", detail: "Keep the Mac awake even with the lid closed while agents are working.")
            ToggleRow(
                title: "Keep Mac awake while agents are working",
                detail: "Screen locks when the lid closes; Mac sleeps automatically once agents finish.",
                isOn: $lidGuard.enabled
            )
            StepRow(
                title: "Stay awake while waiting for your input",
                value: lidGuard.waitForInput == 0 ? "Don’t wait" : "\(lidGuard.waitForInput) min",
                number: $lidGuard.waitForInput,
                range: 0...10,
                step: 1
            )

            Hairline().padding(.vertical, 20)

            SectionHeading(title: "Keep Awake", detail: "Like caffeinate — keeps the Mac and screen awake regardless of agent activity. Heat cut-off still applies.")
            ToggleRow(
                title: "Keep the Mac on no matter what",
                detail: lidGuard.keepAwakeStatus,
                isOn: Binding(
                    get: { lidGuard.keepAwake },
                    set: { $0 ? lidGuard.startKeepAwake(until: nil) : lidGuard.stopKeepAwake() }
                )
            )
            HStack(spacing: 8) {
                Button("1 hour") { lidGuard.startKeepAwake(until: Date().addingTimeInterval(3600)) }
                    .buttonStyle(FlatButtonStyle(compact: true))
                Button("3 hours") { lidGuard.startKeepAwake(until: Date().addingTimeInterval(3 * 3600)) }
                    .buttonStyle(FlatButtonStyle(compact: true))
                Button("Until 7am") { lidGuard.startKeepAwake(until: next7am()) }
                    .buttonStyle(FlatButtonStyle(compact: true))
                Button("Until turned off") { lidGuard.startKeepAwake(until: nil) }
                    .buttonStyle(FlatButtonStyle(compact: true))
                Spacer()
            }
            .padding(.top, 10)

            Hairline().padding(.vertical, 20)

            SectionHeading(title: "Safety Cut-Offs", detail: "Allow the Mac to sleep anyway if any safety threshold is reached.")
            StepRow(title: "Battery below", value: "\(lidGuard.minBattery)%", number: $lidGuard.minBattery, range: 5...90, step: 5)
            ToggleRow(title: "Low Power Mode is on", isOn: $lidGuard.sleepInLowPower)
            HStack {
                Text("Thermal cut-off with lid closed").font(.system(size: 13))
                Spacer()
                ChoiceMenu(label: "Thermal cut-off", selection: $lidGuard.heatLimit, options: [
                    ("Fair", "fair"), ("Serious (Recommended)", "serious"), ("Critical", "critical"), ("Never", "off")
                ])
            }
            .padding(.vertical, 8)
            StepRow(
                title: "Lid closed on battery for over",
                value: "\(lidGuard.hoursString) h",
                number: $lidGuard.batteryLimitHours,
                range: 0.5...24,
                step: 0.5
            )

            Hairline().padding(.vertical, 20)

            SectionHeading(title: "Lid & Notifications")
            ToggleRow(title: "Lock screen when the lid closes", isOn: $lidGuard.lockOnLidClose)
            ToggleRow(title: "Leave alone with external monitor", detail: "Desk setup with lid shut: never lock or force sleep.", isOn: $lidGuard.leaveAloneWithMonitor)
            ToggleRow(title: "Notify when put to sleep", isOn: $lidGuard.notifyOnSleep)
        }
    }
}
