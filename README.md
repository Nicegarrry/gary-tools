# Gary Tools

**A native macOS utility suite built in Swift & SwiftUI** — consolidating **Sleep Guard** (formerly LidGuard), **Clipboard** (formerly Paste Local), **Menu Bar Organizer** (formerly ArrowBar), **Context Grab**, **Repo Sync**, and **Mac Settings** into one fast, local-first application styled with the CubeBit palette (translucent navy `#132A45`, sky blue `#7FB3DA`, rust `#B0552E`).

## What’s Included

### 1. Sleep Guard
- Built-in **Keep Awake** mode (like `caffeinate`) that works out of the box with 1h, 3h, Until 7am, and indefinite presets — no extra tools required.
- Optional agent watcher: keeps your Mac awake (even with the lid closed) while [Herdr](https://herdr.dev) agents are actively working (optional — only needed if you use Herdr).
- Automatic screen lock on lid close (skipped when connected to an external monitor).
- Safety cut-offs for low battery, Low Power Mode, sustained thermal heat, and lid-closed battery duration.

### 2. Clipboard
- Local-only clipboard manager preserving rich formats (text, RTF, HTML, images, links, hex colors, files).
- Floating bottom-screen card browser (**⌃⌥V**) with instant search, pinboards, previews (`Space`), snippet editor (`⌘N`), and serialized **Paste Stack** (**⌃⌥P**).
- Confidential/transient pasteboard marker exclusions and ignored password-manager bundle IDs.
- All data stored locally in `~/Library/Application Support/Gary Tools/Clipboard` with `0700`/`0600` permissions — no accounts, telemetry, or cloud sync.

### 3. Menu Bar Organizer *(requires macOS 27+)*
- Uses macOS 27’s native `MenuBarClientCore` visibility control for instant, zero-flicker hiding of unpinned third-party menu bar icons while keeping all macOS system items (Battery, Bluetooth, Clock, Displays, Keyboard, Volume, Wi-Fi, Screen Mirroring, Control Center) visible.
- Dedicated `«` / `»` menu bar toggle, drag-and-drop layout editor (`⌘E`), hover-to-reveal, floating `Show icons` recovery pill, and global reveal shortcut (**⌃⌥⌘Space**).
- XPC-backed assertions automatically restore all icons on reveal, quit, or crash. *(Note: macOS pauses Live Activity pills while icons are tucked; click the arrow, hover the menu bar, or press `⌃⌥⌘Space` anytime to reveal.)*

### 4. Context Grab
- Press **⌃⌥G**, drag over part of the screen (or press `Space` to pick a window), and Gary Tools puts one paste-ready block for your agent on the clipboard.
- The block is Markdown: the app and window it came from, the browser URL, the git repo and branch (found from terminal and editor window titles), any error lines first, then all the text on screen, read on-device with Vision.
- The screenshot rides along as an image for apps that take one, and its path is in the Markdown so a terminal agent can open it. The last 50 screenshots are kept in `~/Library/Application Support/Gary Tools/Captures` (`0700`/`0600`).
- It also lands in Clipboard history. Needs Screen Recording access; window titles use the Accessibility access the clipboard already has.

### 5. Repo Sync
- Hourly background fast-forward pull (`git pull --ff-only`) across one or more project folders (default `~/Developer`, configurable via colon-separated `AUTO_PULL_DIRS`, checking top-level and one grouping subfolder deep, e.g. `local/`) while the Mac is awake — even when Sleep Guard is turned off.
- Shared lock-protected script (`scripts/dev-pull-all.sh`) also powers `SessionStart` hooks for Antigravity, Claude Code, and Codex.

### 6. Mac Settings
- Common macOS settings that are hard to find, in one place: where screenshots save (plus format, shadow, thumbnail, date in the name), the default browser, and the default app for `.md`, text, config and code files (one at a time or a whole group at once).
- Finder settings with no switch in System Settings: hidden files, file extensions, path bar, full path in the title, and no `.DS_Store` files on network or USB drives.
- Developer setup: create the developer folder (the Repo Sync folder, `~/Developer` by default) and add it to the Finder sidebar; install the Command Line Tools (Apple's installer) and Homebrew (its official script, in Terminal).
- Google Chrome: install it (downloaded from Google and checked for Google's signature) and set its download folder in every profile. Chrome must be quit for that, and each profile's `Preferences` is backed up to `Chrome Backups/` first.
- Fail-safe: before the first change to anything, Gary Tools records its original value in `mac-settings-originals.plist`, and **Undo All Changes** puts every setting back.

## Build, Test & Install

Requires macOS 14+ and Xcode Command Line Tools (`git`, `swift`). Menu Bar Organizer requires macOS 27+. No third-party package dependencies.

### Quick Install (For Friends / Fresh Mac)

Run this one-line installer in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/Nicegarrry/gary-tools/main/scripts/bootstrap.sh | bash
```

What it does automatically:
1. Checks macOS 14+ and Xcode Command Line Tools (if missing, launches Apple's installer and tells you when to re-run).
2. Clones Gary Tools into `~/Library/Application Support/Gary Tools/source` (or fast-forwards an existing clone).
3. Creates a local trusted `Gary Tools Local Signing` certificate in your login keychain so macOS Accessibility & Screen Recording permissions survive future updates.
4. Builds and installs `/Applications/Gary Tools.app`, configures the background LaunchAgent daemon, and opens Gary Tools into its first-run Setup Wizard.
5. Enables the built-in self-updater (or run `~/.local/bin/gary-tools-update` anytime).

To uninstall later:

```bash
curl -fsSL https://raw.githubusercontent.com/Nicegarrry/gary-tools/main/scripts/bootstrap.sh | bash -s -- --uninstall --remove-app
```

### Developer Workflow

```bash
# One-time setup: create a local trusted signing cert so Accessibility & Screen Recording
# permissions survive future rebuilds (avoids ad-hoc signature invalidation)
./scripts/setup-signing.sh

# Check whether newer commits are available on origin without changing the working tree
./update.sh --check

# Pull latest, run tests, rebuild, and cleanly restart Gary Tools + daemon
# (also symlinked to ~/.local/bin/gary-tools-update after install)
./update.sh

# Build dist/Gary Tools.app (includes CubeBit AppIcon and lidguard-helper)
./build.sh

# Run XCTest suite (ArrowCore, VisibilityController, Clipboard, DataMigration)
./test.sh

# Build, install/restart background daemon LaunchAgent, and cleanly relaunch Gary Tools.app
# Pass --applications to install to /Applications/Gary Tools.app, or --local-dist to run from dist/
./install.sh
```

## Architecture

- `Sources/MenuBarBridge/` — Objective-C CoreFoundation container preferences bridge
- `Sources/GaryCore/` — Pure, testable Swift core logic (clipboard store/monitor, menu bar switch state machine, non-destructive migration)
- `Sources/GaryTools/` — Native AppKit + SwiftUI application (Dock app, unified Menu Bar Hub, ArrowBar chevron, CubeBit glass UI, floating clipboard browser, Settings window)
- `scripts/` — `bootstrap.sh` one-line installer, `lidguard.sh` daemon, `dev-pull-all.sh` multi-folder repo sync, `setup-signing.sh` local signing setup, `helper.swift` thermal/lock helper, `make-icon.swift` CubeBit icon generator
- `Tests/` — XCTest unit test suite

## Data & Privacy

All persistent state lives in `~/Library/Application Support/Gary Tools/`:
- `settings.conf` — Sleep Guard & Repo Sync configuration
- `source-repo.txt` — Recorded source checkout path used by the built-in updater (`0600`)
- `Clipboard/` — Clipboard history index, raw payloads, and thumbnails
- `Captures/` — Context Grab screenshots (newest 50)
- Log: `~/Library/Logs/gary-tools.log`

## License

MIT
