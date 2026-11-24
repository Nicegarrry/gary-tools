# Gary Tools

**A native macOS utility suite built in Swift & SwiftUI** — consolidating **Sleep Guard** (formerly LidGuard), **Clipboard** (formerly Paste Local), **Menu Bar Organizer** (formerly ArrowBar), **Context Grab**, and **Git Repo Auto-Pull** into one fast, local-first application styled with the CubeBit palette (translucent navy `#132A45`, sky blue `#7FB3DA`, rust `#B0552E`).

## What’s Included

### 1. Sleep Guard
- Keeps your Mac awake (even with the lid closed) while [Herdr](https://herdr.dev) agents are actively working.
- Built-in **Keep Awake** mode (like `caffeinate`) with 1h, 3h, Until 7am, and indefinite presets.
- Automatic screen lock on lid close (skipped when connected to an external monitor).
- Safety cut-offs for low battery, Low Power Mode, sustained thermal heat, and lid-closed battery duration.

### 2. Clipboard
- Local-only clipboard manager preserving rich formats (text, RTF, HTML, images, links, hex colors, files).
- Floating bottom-screen card browser (**⌃⌥V**) with instant search, pinboards, previews (`Space`), snippet editor (`⌘N`), and serialized **Paste Stack** (**⌃⌥P**).
- Confidential/transient pasteboard marker exclusions and ignored password-manager bundle IDs.
- All data stored locally in `~/Library/Application Support/Gary Tools/Clipboard` with `0700`/`0600` permissions — no accounts, telemetry, or cloud sync.

### 3. Menu Bar Organizer
- Uses macOS 27’s native `MenuBarClientCore` visibility control for instant, zero-flicker hiding of unpinned third-party menu bar icons while keeping all macOS system items (Battery, Bluetooth, Clock, Displays, Keyboard, Volume, Wi-Fi, Screen Mirroring, Control Center) visible.
- Dedicated `«` / `»` menu bar toggle, drag-and-drop layout editor (`⌘E`), hover-to-reveal, floating `Show icons` recovery pill, and global reveal shortcut (**⌃⌥⌘Space**).
- XPC-backed assertions automatically restore all icons on reveal, quit, or crash. *(Note: macOS pauses Live Activity pills while icons are tucked; click the arrow, hover the menu bar, or press `⌃⌥⌘Space` anytime to reveal.)*

### 4. Context Grab
- Press **⌃⌥G**, drag over part of the screen (or press `Space` to pick a window), and Gary Tools puts one paste-ready block for your agent on the clipboard.
- The block is Markdown: the app and window it came from, the browser URL, the git repo and branch (found from terminal and editor window titles), any error lines first, then all the text on screen, read on-device with Vision.
- The screenshot rides along as an image for apps that take one, and its path is in the Markdown so a terminal agent can open it. The last 50 screenshots are kept in `~/Library/Application Support/Gary Tools/Captures` (`0700`/`0600`).
- It also lands in Clipboard history. Needs Screen Recording access; window titles use the Accessibility access the clipboard already has.

### 5. Repo Sync
- Hourly background fast-forward pull (`git pull --ff-only`) across `~/Developer` (and one grouping subfolder deep, e.g. `local/`) while the Mac is awake — even when Sleep Guard is turned off.
- Shared lock-protected script (`scripts/dev-pull-all.sh`) also powers `SessionStart` hooks for Antigravity, Claude Code, and Codex.

### 5. Mac Settings
- Common macOS settings that are hard to find, in one place: where screenshots save (plus format, shadow, thumbnail, date in the name), the default browser, and the default app for `.md`, text, config and code files (one at a time or a whole group at once).
- Finder settings with no switch in System Settings: hidden files, file extensions, path bar, full path in the title, and no `.DS_Store` files on network or USB drives.
- Developer setup: create the developer folder (the Repo Sync folder, `~/Developer` by default) and add it to the Finder sidebar; install the Command Line Tools (Apple's installer) and Homebrew (its official script, in Terminal).
- Google Chrome: install it (downloaded from Google and checked for Google's signature) and set its download folder in every profile. Chrome must be quit for that, and each profile's `Preferences` is backed up to `Chrome Backups/` first.
- Fail-safe: before the first change to anything, Gary Tools records its original value in `mac-settings-originals.plist`, and **Undo All Changes** puts every setting back.

## Build, Test & Install

Requires macOS 14+ and Xcode Command Line Tools (`swift`, `jq`). No third-party package dependencies.

```bash
# Build dist/Gary Tools.app (includes CubeBit AppIcon and lidguard-helper)
./build.sh

# Run XCTest suite (ArrowCore, VisibilityController, Clipboard, DataMigration)
./test.sh

# Build, install background daemon LaunchAgent, and open Gary Tools.app
./install.sh
```

## Architecture

- `Sources/MenuBarBridge/` — Objective-C CoreFoundation container preferences bridge
- `Sources/GaryCore/` — Pure, testable Swift core logic (clipboard store/monitor, menu bar switch state machine, non-destructive migration)
- `Sources/GaryTools/` — Native AppKit + SwiftUI application (Dock app, unified Menu Bar Hub, ArrowBar chevron, CubeBit glass UI, floating clipboard browser, Settings window)
- `scripts/` — `lidguard.sh` daemon, `dev-pull-all.sh` repo sync, `helper.swift` thermal/lock helper, `make-icon.swift` CubeBit icon generator
- `Tests/` — XCTest unit test suite

## Data & Privacy

All persistent state lives in `~/Library/Application Support/Gary Tools/`:
- `settings.conf` — Sleep Guard & Repo Sync configuration
- `Clipboard/` — Clipboard history index, raw payloads, and thumbnails
- `Captures/` — Context Grab screenshots (newest 50)
- Log: `~/Library/Logs/gary-tools.log`

## License

MIT
