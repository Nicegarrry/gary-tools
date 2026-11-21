// lidguard menu bar app (native Swift / SwiftUI).
//   Click         → turn lidguard on / off
//   Option-click  → Keep Awake on / off (until you turn it off)
//   Right-click   → status, Keep Awake for…, Settings…, Open Log, Quit
// Reads/writes ../settings.conf (keeps all the notes in that file intact).
// Built by build.sh into ../Lidguard.app
import Cocoa
import SwiftUI

let folder = Bundle.main.bundleURL.deletingLastPathComponent()
let settingsURL = folder.appendingPathComponent("settings.conf")
let statusURL = folder.appendingPathComponent(".status")
let lastSleepURL = folder.appendingPathComponent(".last_sleep")
let lastGitSyncURL = folder.appendingPathComponent(".last_git_sync")
let pullNowURL = folder.appendingPathComponent(".pull_now")
let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/lidguard.log")
let label = "com.\(NSUserName()).lidguard"   // must match install.sh

// MARK: - settings.conf

enum SettingsFile {
  static func read() -> [String: String] {
    guard let text = try? String(contentsOf: settingsURL, encoding: .utf8) else { return [:] }
    var out: [String: String] = [:]
    for line in text.components(separatedBy: "\n") {
      let t = line.trimmingCharacters(in: .whitespaces)
      guard !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { continue }
      let key = t[..<eq].trimmingCharacters(in: .whitespaces)
      let value = t[t.index(after: eq)...].split(separator: "#").first.map(String.init) ?? ""
      out[key] = value.trimmingCharacters(in: .whitespaces)
    }
    return out
  }

  /// Replace the KEY=… line (or append it), leaving every comment untouched.
  static func write(_ key: String, _ value: String) {
    let text = (try? String(contentsOf: settingsURL, encoding: .utf8)) ?? ""
    var lines = text.components(separatedBy: "\n")
    let isLine: (String) -> Bool = { l in
      let t = l.trimmingCharacters(in: .whitespaces)
      return !t.hasPrefix("#") && t.hasPrefix(key) &&
        t.dropFirst(key.count).trimmingCharacters(in: .whitespaces).hasPrefix("=")
    }
    if let i = lines.firstIndex(where: isLine) { lines[i] = "\(key)=\(value)" }
    else { lines.append("\(key)=\(value)") }
    try? lines.joined(separator: "\n").write(to: settingsURL, atomically: true, encoding: .utf8)
  }
}

let untilFormat: DateFormatter = {
  let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"; return f
}()

// MARK: - Settings model (every change saves immediately; lidguard picks it up within seconds)

final class Settings: ObservableObject {
  @Published var enabled = true                { didSet { save("ENABLED", enabled) } }
  @Published var keepAwake = false             { didSet { save("KEEP_AWAKE_ALWAYS", keepAwake) } }
  @Published var keepAwakeUntil = ""           { didSet { save("KEEP_AWAKE_UNTIL", keepAwakeUntil) } }
  @Published var waitForInput = 3              { didSet { save("WAIT_FOR_INPUT_MINUTES", waitForInput) } }
  @Published var minBattery = 20               { didSet { save("MIN_BATTERY_PERCENT", minBattery) } }
  @Published var sleepInLowPower = true        { didSet { save("SLEEP_IN_LOW_POWER_MODE", sleepInLowPower) } }
  @Published var heatLimit = "serious"         { didSet { save("HEAT_LIMIT", heatLimit) } }
  @Published var batteryLimitHours = 4.0       { didSet { save("BATTERY_LID_CLOSED_LIMIT_HOURS", hoursString) } }
  @Published var leaveAloneWithMonitor = true  { didSet { save("LEAVE_ALONE_WITH_EXTERNAL_MONITOR", leaveAloneWithMonitor) } }
  @Published var lockOnLidClose = true         { didSet { save("LOCK_SCREEN_WHEN_LID_CLOSES", lockOnLidClose) } }
  @Published var notifyOnSleep = true          { didSet { save("NOTIFY_ON_SLEEP", notifyOnSleep) } }
  @Published var startAtLogin = true           { didSet { save("START_AT_LOGIN", startAtLogin) } }
  @Published var turnOnAtLogin = false         { didSet { save("TURN_ON_AT_LOGIN", turnOnAtLogin) } }
  @Published var checkEvery = 2                { didSet { save("CHECK_EVERY_SECONDS", checkEvery) } }
  @Published var waitBeforeSleep = 20          { didSet { save("WAIT_BEFORE_SLEEP_SECONDS", waitBeforeSleep) } }
  @Published var autoPullRepos = true          { didSet { save("AUTO_PULL_REPOS", autoPullRepos) } }
  @Published var autoPullIntervalMinutes = 60  { didSet { save("AUTO_PULL_INTERVAL_MINUTES", autoPullIntervalMinutes) } }
  @Published var autoPullDir = "~/Developer"   { didSet { save("AUTO_PULL_DIR", autoPullDir) } }
  @Published var lastGitSyncText = "Not synced yet"
  @Published var pullingNow = false

  private var loading = false

  var hoursString: String {
    batteryLimitHours == batteryLimitHours.rounded() ? String(Int(batteryLimitHours)) : String(batteryLimitHours)
  }

  init() { reload() }

  func reload() {
    loading = true; defer { loading = false }
    let s = SettingsFile.read()
    func bool(_ k: String, _ d: Bool) -> Bool { s[k].map { $0.lowercased() == "yes" } ?? d }
    func int(_ k: String, _ d: Int) -> Int { s[k].flatMap(Int.init) ?? d }
    enabled                 = bool("ENABLED", true)
    keepAwake               = bool("KEEP_AWAKE_ALWAYS", false)
    keepAwakeUntil          = s["KEEP_AWAKE_UNTIL"] ?? ""
    waitForInput            = int("WAIT_FOR_INPUT_MINUTES", 3)
    minBattery              = int("MIN_BATTERY_PERCENT", 20)
    sleepInLowPower         = bool("SLEEP_IN_LOW_POWER_MODE", true)
    heatLimit               = (s["HEAT_LIMIT"] ?? "serious").lowercased()
    batteryLimitHours       = s["BATTERY_LID_CLOSED_LIMIT_HOURS"].flatMap(Double.init) ?? 4
    leaveAloneWithMonitor   = bool("LEAVE_ALONE_WITH_EXTERNAL_MONITOR", true)
    lockOnLidClose          = bool("LOCK_SCREEN_WHEN_LID_CLOSES", true)
    notifyOnSleep           = bool("NOTIFY_ON_SLEEP", true)
    startAtLogin            = bool("START_AT_LOGIN", true)
    turnOnAtLogin           = bool("TURN_ON_AT_LOGIN", false)
    checkEvery              = int("CHECK_EVERY_SECONDS", 2)
    waitBeforeSleep         = int("WAIT_BEFORE_SLEEP_SECONDS", 20)
    autoPullRepos           = bool("AUTO_PULL_REPOS", true)
    autoPullIntervalMinutes = int("AUTO_PULL_INTERVAL_MINUTES", 60)
    autoPullDir             = s["AUTO_PULL_DIR"] ?? "~/Developer"
    refreshGitSync()
  }

  func refreshGitSync() {
    if let raw = try? String(contentsOf: lastGitSyncURL, encoding: .utf8) {
      let p = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", maxSplits: 2).map(String.init)
      if p.count == 3 {
        lastGitSyncText = "\(p[1]) — \(p[2])"
        if pullingNow, let ts = Double(p[0]), Date().timeIntervalSince1970 - ts < 15 {
          pullingNow = false
        }
        return
      }
    }
    lastGitSyncText = "Not synced yet"
  }

  func triggerPullNow() {
    pullingNow = true
    try? "".write(to: pullNowURL, atomically: true, encoding: .utf8)
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
      self?.pullingNow = false
      self?.refreshGitSync()
    }
  }

  /// Keep Awake on, optionally until a time (nil = until turned off)
  func startKeepAwake(until: Date?) {
    reload()
    keepAwakeUntil = until.map { untilFormat.string(from: $0) } ?? ""
    keepAwake = true
  }

  func stopKeepAwake() {
    reload()
    keepAwake = false
    keepAwakeUntil = ""
  }

  var keepAwakeUntilDate: Date? { untilFormat.date(from: keepAwakeUntil) }

  private func save(_ key: String, _ v: Bool) { save(key, v ? "yes" : "no") }
  private func save(_ key: String, _ v: Int) { save(key, String(v)) }
  private func save(_ key: String, _ v: String) {
    guard !loading else { return }
    SettingsFile.write(key, v)
    NotificationCenter.default.post(name: .settingsChanged, object: nil)
  }
}

extension Notification.Name { static let settingsChanged = Notification.Name("lidguardSettingsChanged") }

func next7am() -> Date {
  let cal = Calendar.current
  return cal.nextDate(after: Date(), matching: DateComponents(hour: 7, minute: 0), matchingPolicy: .nextTime)!
}

let timeOnly: DateFormatter = { let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short; return f }()

// MARK: - Settings window (CubeBit navy / sky / rust)

enum SettingsTab: String, CaseIterable, Identifiable {
  case agents = "Agents", keepAwake = "Keep Awake", safety = "Safety", lid = "Lid & Login", repos = "Repos"
  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .agents: return "cpu"
    case .keepAwake: return "cup.and.heat.waves"
    case .safety: return "shield.lefthalf.filled"
    case .lid: return "laptopcomputer"
    case .repos: return "arrow.triangle.2.circlepath"
    }
  }
  var subtitle: String {
    switch self {
    case .agents: return "Give your agents room to finish."
    case .keepAwake: return "A little more time, on your terms."
    case .safety: return "Keep an eye on the things that matter."
    case .lid: return "Settle into the way you work."
    case .repos: return "Keep your projects close to their latest."
    }
  }
}

struct SettingsSection<Content: View>: View {
  let title: String
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text)
      VStack(alignment: .leading, spacing: 18) { content }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct SwitchRow: View {
  let title: String
  var note: String? = nil
  @Binding var isOn: Bool
  var body: some View {
    HStack(spacing: 24) {
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
        if let note { Text(note).font(.system(size: 12)).lineSpacing(3).foregroundStyle(Theme.secondary) }
      }
      Spacer(minLength: 0)
      Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(Theme.rust)
    }.padding(.vertical, 3)
  }
}

struct StepRow<V: Strideable & Comparable>: View where V.Stride: SignedNumeric {
  let title: String
  let value: String
  @Binding var number: V
  let range: ClosedRange<V>
  let step: V.Stride
  @Environment(\.isEnabled) private var enabled
  var body: some View {
    HStack(spacing: 16) {
      Text(title).font(.system(size: 13)).foregroundStyle(Theme.text)
      Spacer(minLength: 12)
      Text(value).font(.system(size: 13)).monospacedDigit().foregroundStyle(Theme.sky)
      HStack(spacing: 6) {
        stepButton("minus", label: "Decrease", enabled: number > range.lowerBound) {
          number = max(range.lowerBound, number.advanced(by: -step))
        }
        stepButton("plus", label: "Increase", enabled: number < range.upperBound) {
          number = min(range.upperBound, number.advanced(by: step))
        }
      }
    }.padding(.vertical, 3).opacity(enabled ? 1 : 0.4)
  }
  private func stepButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 9, weight: .medium))
        .foregroundStyle(Theme.text).frame(width: 24, height: 24)
        .background(.white.opacity(0.06), in: Circle()).contentShape(Circle())
    }
    .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.35)
    .accessibilityLabel("\(label) \(title.lowercased())")
  }
}

struct Note: View {
  let text: String
  var body: some View {
    Text(text).font(.system(size: 12)).foregroundStyle(Theme.secondary)
      .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
  }
}

struct SettingsView: View {
  @ObservedObject var s: Settings
  @LocalState var tab: SettingsTab = .agents

  var keepAwakeStatus: String {
    guard s.keepAwake else { return "Off" }
    if let d = s.keepAwakeUntilDate { return "On until \(timeOnly.string(from: d))" }
    return "On until you turn it off"
  }

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 8) {
          Text(tab.rawValue).font(.system(size: 28, weight: .regular))
          Text(tab.subtitle).font(.system(size: 13)).foregroundStyle(Theme.secondary)
        }.padding(.horizontal, 32).padding(.top, 48).padding(.bottom, 28)
        ScrollView {
          VStack(alignment: .leading, spacing: 26) {
            switch tab {
            case .agents: agents
            case .keepAwake: keepAwakeTab
            case .safety: safety
            case .lid: lidAndLogin
            case .repos: reposTab
            }
          }.padding(.horizontal, 32).padding(.bottom, 28)
        }
        Hairline().padding(.horizontal, 32)
        HStack(spacing: 8) {
          Image(systemName: "checkmark").foregroundStyle(Theme.sky).font(.system(size: 9, weight: .medium))
          Text("Changes save automatically").font(.system(size: 11)).foregroundStyle(Theme.muted)
          Spacer()
          Text("Applied within a few seconds").font(.system(size: 10)).foregroundStyle(Theme.muted)
        }.padding(.horizontal, 32).padding(.vertical, 20)
      }
    }
    .foregroundStyle(Theme.text).tint(Theme.rust)
    // One full-window material, including the native traffic-light/title-bar area.
    // AppKit supplies the outer window corners; a second rounded panel leaves a seam.
    .background(GlassBackground(radius: 0)).preferredColorScheme(.dark)
    .ignoresSafeArea(.container, edges: .top)
    .frame(width: 800, height: 610)
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 9) {
        Image(systemName: "cup.and.saucer").font(.system(size: 16, weight: .regular)).foregroundStyle(Theme.sky)
        Text("Lidguard").font(.system(size: 14, weight: .medium))
      }.padding(.horizontal, 22).padding(.top, 55).padding(.bottom, 34)
      ForEach(SettingsTab.allCases) { item in
        Button { tab = item } label: {
          HStack(spacing: 11) {
            Capsule().fill(tab == item ? Theme.rust : .clear).frame(width: 3, height: 18)
            Image(systemName: item.symbol).font(.system(size: 13)).frame(width: 16)
              .foregroundStyle(tab == item ? Theme.sky : Theme.muted)
            Text(item.rawValue).font(.system(size: 13, weight: tab == item ? .medium : .regular))
              .foregroundStyle(tab == item ? Theme.text : Theme.secondary)
            Spacer()
          }.padding(.vertical, 10).padding(.trailing, 18).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(tab == item ? .isSelected : [])
      }
      Spacer()
      VStack(alignment: .leading, spacing: 7) {
        Label(s.keepAwake ? "Keep Awake on" : s.enabled ? "Watching agents" : "Switched off",
              systemImage: s.keepAwake ? "cup.and.heat.waves" : s.enabled ? "cpu" : "moon")
          .font(.system(size: 10)).foregroundStyle(Theme.sky)
        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1")")
          .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
      }.padding(22)
    }.frame(width: 190).frame(maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder var agents: some View {
    SettingsSection(title: "Herdr agents") {
      SwitchRow(title: "Keep Mac awake while agents are working",
                note: "Click the menu bar icon to switch this on or off.", isOn: $s.enabled)
    }
    Hairline()
    SettingsSection(title: "When an agent asks you something") {
      StepRow(title: "Stay awake for", value: s.waitForInput == 0 ? "Don't wait" : "\(s.waitForInput) min",
              number: $s.waitForInput, range: 0...5, step: 1)
      Note(text: "Gives you time to answer remotely before the Mac sleeps.")
    }
    Hairline()
    SettingsSection(title: "Timing") {
      StepRow(title: "Check every", value: "\(s.checkEvery) s", number: $s.checkEvery, range: 1...60, step: 1)
      StepRow(title: "Wait after agents stop", value: "\(s.waitBeforeSleep) s",
              number: $s.waitBeforeSleep, range: 0...300, step: 5)
    }
  }

  @ViewBuilder var keepAwakeTab: some View {
    SettingsSection(title: "Keep Awake") {
      SwitchRow(title: "Keep the Mac on no matter what", note: keepAwakeStatus, isOn: Binding(
        get: { s.keepAwake }, set: { $0 ? s.startKeepAwake(until: nil) : s.stopKeepAwake() }))
      Note(text: "Like caffeinate: the screen stays on and the lid can be closed. Ignores the battery and time rules; the heat cut-off still applies.")
    }
    Hairline()
    SettingsSection(title: "Turn on for") {
      HStack(spacing: 10) {
        durationButton("1 hour") { s.startKeepAwake(until: Date().addingTimeInterval(3600)) }
        durationButton("3 hours") { s.startKeepAwake(until: Date().addingTimeInterval(3 * 3600)) }
        durationButton("Until 7am") { s.startKeepAwake(until: next7am()) }
        durationButton("Until off") { s.startKeepAwake(until: nil) }
      }
      Note(text: "Option-click the menu bar icon to toggle Keep Awake.")
    }
  }

  func durationButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Text(title).frame(maxWidth: .infinity) }.buttonStyle(FlatButtonStyle())
  }

  @ViewBuilder var safety: some View {
    SettingsSection(title: "Let the Mac sleep anyway when") {
      StepRow(title: "Battery is below", value: "\(s.minBattery)%", number: $s.minBattery, range: 5...90, step: 5)
      SwitchRow(title: "Low Power Mode is on", isOn: $s.sleepInLowPower)
      HStack {
        Text("Running hot with the lid closed").font(.system(size: 13))
        Spacer(minLength: 12)
        ChoiceMenu(label: "Heat cut-off", selection: $s.heatLimit,
                   options: [("Fair", "fair"), ("Serious", "serious"), ("Critical", "critical"), ("Never", "off")])
      }.padding(.vertical, 3)
      StepRow(title: "Lid closed on battery for over", value: "\(s.hoursString) h",
              number: $s.batteryLimitHours, range: 0.5...24, step: 0.5)
      Note(text: "Plugged in, there's no time limit. Heat: Serious is recommended.")
    }
  }

  @ViewBuilder var lidAndLogin: some View {
    SettingsSection(title: "Lid") {
      SwitchRow(title: "Lock screen when the lid closes", isOn: $s.lockOnLidClose)
      SwitchRow(title: "Leave alone when a monitor is connected",
                note: "Desk setup with the lid shut: never lock or force sleep.", isOn: $s.leaveAloneWithMonitor)
      SwitchRow(title: "Notify me when it puts the Mac to sleep", isOn: $s.notifyOnSleep)
    }
    Hairline()
    SettingsSection(title: "Login") {
      SwitchRow(title: "Start at login", isOn: $s.startAtLogin)
      SwitchRow(title: "Turn on automatically at login",
                note: s.turnOnAtLogin ? "Keeps whatever on/off state it had."
                                      : "Starts switched off — click the icon to turn it on.",
                isOn: $s.turnOnAtLogin)
        .disabled(!s.startAtLogin)
    }
  }

  var intervalLabel: String {
    let m = s.autoPullIntervalMinutes
    let h = m / 60, rem = m % 60
    if h > 0 && rem > 0 { return "\(h)h \(rem)m" }
    if h > 0 { return "\(h) h" }
    return "\(m) min"
  }

  @ViewBuilder var reposTab: some View {
    SettingsSection(title: "Git auto-pull") {
      SwitchRow(title: "Auto-pull git repos while awake",
                note: "Runs git pull --ff-only in the background. Never overwrites uncommitted work.",
                isOn: $s.autoPullRepos)
      StepRow(title: "Pull every", value: intervalLabel,
              number: $s.autoPullIntervalMinutes, range: 15...360, step: 15)
        .disabled(!s.autoPullRepos)
      Note(text: "Runs even when sleep-blocking is off, as long as the Mac is awake.")
    }
    Hairline()
    SettingsSection(title: "Status") {
      HStack(alignment: .firstTextBaseline, spacing: 18) {
        Text("Folder").font(.system(size: 13))
        Spacer(minLength: 0)
        Text(s.autoPullDir).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.sky)
          .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
      }
      HStack(alignment: .top, spacing: 18) {
        Text("Last sync").font(.system(size: 13))
        Spacer(minLength: 0)
        Text(s.lastGitSyncText).font(.system(size: 12)).foregroundStyle(Theme.secondary)
          .lineSpacing(3).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        Spacer()
        Button(s.pullingNow ? "Pulling…" : "Pull Now") { s.triggerPullNow() }
          .buttonStyle(FlatButtonStyle(primary: true)).disabled(s.pullingNow)
      }
    }
  }
}

// MARK: - Menu bar

final class App: NSObject, NSApplicationDelegate {
  let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  let settings = Settings()
  let menu = NSMenu()
  let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  let lastSleepLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  let toggleItem = NSMenuItem(title: "Enabled", action: #selector(toggle), keyEquivalent: "")
  let caffeineItem = NSMenuItem(title: "Keep Awake", action: nil, keyEquivalent: "")
  let caffeineMenu = NSMenu()
  var window: NSWindow?

  func applicationDidFinishLaunching(_ n: Notification) {
    NSApp.appearance = NSAppearance(named: .darkAqua)
    ensureLidguardRunning()

    statusLine.isEnabled = false
    lastSleepLine.isEnabled = false
    toggleItem.target = self
    menu.addItem(statusLine)
    menu.addItem(lastSleepLine)
    menu.addItem(.separator())
    menu.addItem(toggleItem)

    for (title, sel) in [("Until I turn it off", #selector(keepAwakeIndefinitely)),
                         ("For 1 hour", #selector(keepAwake1h)),
                         ("For 3 hours", #selector(keepAwake3h)),
                         ("Until 7am", #selector(keepAwakeUntil7))] {
      caffeineMenu.addItem(withTitle: title, action: sel, keyEquivalent: "").target = self
    }
    caffeineMenu.addItem(.separator())
    caffeineMenu.addItem(withTitle: "Turn off", action: #selector(keepAwakeOff), keyEquivalent: "").target = self
    caffeineItem.submenu = caffeineMenu
    menu.addItem(caffeineItem)

    menu.addItem(.separator())
    menu.addItem(withTitle: "Pull Repos Now", action: #selector(pullReposNow), keyEquivalent: "").target = self
    menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
    menu.addItem(withTitle: "Open Log", action: #selector(openLog), keyEquivalent: "").target = self
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit Menu Icon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    item.button?.target = self
    item.button?.action = #selector(clicked)
    item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

    NotificationCenter.default.addObserver(forName: .settingsChanged, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
    refresh()
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
  }

  /// If start-at-login is off and you open the app yourself, start the background script too.
  func ensureLidguardRunning() {
    let uid = getuid()
    if run("/bin/launchctl", ["print", "gui/\(uid)/\(label)"]) == 0 { return }
    let plist = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents/\(label).plist").path
    guard FileManager.default.fileExists(atPath: plist) else { return }
    _ = run("/bin/launchctl", ["enable", "gui/\(uid)/\(label)"])
    _ = run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plist])
    // lidguard re-applies the Start-at-login setting itself once it's running
  }

  @discardableResult
  func run(_ path: String, _ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run(); p.waitUntilExit(); return p.terminationStatus } catch { return -1 }
  }

  @objc func clicked() {
    let e = NSApp.currentEvent
    if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true {
      refresh()
      item.menu = menu
      item.button?.performClick(nil)
      item.menu = nil            // so the next left-click toggles again
    } else if e?.modifierFlags.contains(.option) == true {
      settings.reload()
      settings.keepAwake ? settings.stopKeepAwake() : settings.startKeepAwake(until: nil)
    } else {
      toggle()
    }
  }

  @objc func toggle() { settings.reload(); settings.enabled.toggle() }
  @objc func keepAwakeIndefinitely() { settings.startKeepAwake(until: nil) }
  @objc func keepAwake1h() { settings.startKeepAwake(until: Date().addingTimeInterval(3600)) }
  @objc func keepAwake3h() { settings.startKeepAwake(until: Date().addingTimeInterval(3 * 3600)) }
  @objc func keepAwakeUntil7() { settings.startKeepAwake(until: next7am()) }
  @objc func keepAwakeOff() { settings.stopKeepAwake() }
  @objc func pullReposNow() { settings.triggerPullNow() }

  func refresh() {
    let s = SettingsFile.read()
    let enabled = s["ENABLED"].map { $0.lowercased() == "yes" } ?? true
    let keepAwake = s["KEEP_AWAKE_ALWAYS"].map { $0.lowercased() == "yes" } ?? false
    let until = s["KEEP_AWAKE_UNTIL"].flatMap { untilFormat.date(from: $0) }

    // What we expect right now, shown until lidguard's own status catches up
    var state = keepAwake ? "caffeine" : (enabled ? "idle" : "off")
    var message = keepAwake ? "Keep Awake" : (enabled ? "On — starting…" : "Off — Mac sleeps normally")

    if let raw = try? String(contentsOf: statusURL, encoding: .utf8),
       let modified = (try? FileManager.default.attributesOfItem(atPath: statusURL.path))?[.modificationDate] as? Date {
      let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", maxSplits: 1).map(String.init)
      let consistent: (String) -> Bool = { st in
        keepAwake ? (st == "caffeine" || st == "idle") : (enabled ? (st == "idle" || st == "awake") : st == "off")
      }
      if Date().timeIntervalSince(modified) > 90 {
        state = "stale"; message = "lidguard isn't running"
      } else if parts.count == 2, consistent(parts[0]) {
        state = parts[0]; message = parts[1]
      }
    } else {
      state = "stale"; message = "lidguard isn't running"
    }

    let symbol = ["caffeine": "cup.and.heat.waves.fill",
                  "awake": "cup.and.saucer.fill", "idle": "cup.and.saucer",
                  "stale": "exclamationmark.triangle"][state] ?? "moon.zzz"
    let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "lidguard")
      ?? NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "lidguard")
    img?.isTemplate = true
    item.button?.image = img
    item.button?.toolTip = "lidguard: \(message)\nClick: turn \(enabled ? "off" : "on") · Option-click: Keep Awake · Right-click: menu"
    statusLine.title = message

    if let raw = try? String(contentsOf: lastSleepURL, encoding: .utf8) {
      let p = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", maxSplits: 1).map(String.init)
      lastSleepLine.title = p.count == 2 ? "Last put to sleep \(p[0]) — \(p[1])" : ""
    }
    lastSleepLine.isHidden = lastSleepLine.title.isEmpty

    toggleItem.state = enabled ? .on : .off
    caffeineItem.state = keepAwake ? .on : .off
    caffeineItem.title = keepAwake
      ? (until.map { "Keep Awake (until \(timeOnly.string(from: $0)))" } ?? "Keep Awake (on)")
      : "Keep Awake"
    settings.refreshGitSync()
  }

  @objc func openSettings() {
    settings.reload()
    if window == nil {
      // Configure full-size content before attaching SwiftUI. Changing it afterward
      // preserves the original title-bar inset and leaves an uncovered strip above it.
      let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 610),
                       styleMask: [.titled, .closable, .fullSizeContentView],
                       backing: .buffered, defer: false)
      w.title = "lidguard"
      Theme.prepare(w)
      w.contentView = NSHostingView(rootView: SettingsView(s: settings))
      w.setContentSize(NSSize(width: 800, height: 610))
      w.isReleasedWhenClosed = false
      w.center()
      window = w
    }
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }

  @objc func openLog() { NSWorkspace.shared.open(logURL) }
}

// `Lidguard --render <folder>` saves a PNG of each settings tab (used for README screenshots)
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--render" {
  MainActor.assumeIsolated {
    let out = URL(fileURLWithPath: CommandLine.arguments[2])
    for t in SettingsTab.allCases {
      let r = ImageRenderer(content: SettingsView(s: Settings(), tab: t))
      r.scale = 2
      if let cg = r.cgImage {
        let rep = NSBitmapImageRep(cgImage: cg)
        let name = t.rawValue.lowercased().replacingOccurrences(of: " & ", with: "-").replacingOccurrences(of: " ", with: "-")
        try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("settings-\(name).png"))
      }
    }
  }
  exit(0)
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
app.run()
