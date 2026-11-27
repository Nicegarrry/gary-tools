# Gary Tools

A fast, local-first native macOS utility suite built in Swift & SwiftUI — combining **Clipboard**, **Context Grab**, **Sleep Guard**, **Repo Sync**, **Mac Settings**, and **Menu Bar Organizer** in one lightweight app.

- **100% local & private:** No accounts, no telemetry, no cloud sync, no third-party dependencies.
- **Guided first-run Setup Wizard:** Walks through permissions, Git/GitHub login, project folders, and Mac defaults in one place.
- **Built-in self-updater:** Checks GitHub for updates and rebuilds with a local trusted signing certificate so macOS permissions survive updates.

---

## Install

Requires **macOS 14+** *(Menu Bar Organizer requires macOS 27+)*.

Run in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/Nicegarrry/gary-tools/main/scripts/bootstrap.sh | bash
```

**What this does:**
1. Checks macOS 14+ and Xcode Command Line Tools *(if missing, opens Apple's installer and tells you when to re-run)*.
2. Clones this repo into `~/Library/Application Support/Gary Tools/source`.
3. Creates a local trusted `Gary Tools Local Signing` certificate in your login keychain *(one Touch ID / password prompt)* so Accessibility and Screen Recording permissions stay granted across future updates.
4. Builds and installs `/Applications/Gary Tools.app`, starts the background daemon, and launches the **Setup Wizard**.

### Updating

- **In the app:** Click **Update Available** in the sidebar/dashboard, or open **Gary Tools → Check for Updates…** → **Update & Relaunch**.
- **From Terminal:** Run `gary-tools-update` from anywhere.

### Uninstalling

```bash
curl -fsSL https://raw.githubusercontent.com/Nicegarrry/gary-tools/main/scripts/bootstrap.sh | bash -s -- --uninstall --remove-app
```

*(Your local clipboard history and settings in `~/Library/Application Support/Gary Tools/` are left untouched unless you delete that folder yourself.)*

---

## Features

| Utility | What it does | Shortcut |
| --- | --- | --- |
| **Clipboard** | Local clipboard history, search, pinboards, previews, snippets & sequential Paste Stack | `⌃⌥V` / `⌃⌥P` |
| **Context Grab** | Select a screen region or window → copies Markdown with app, URL, git branch, errors & on-device OCR + screenshot | `⌃⌥G` |
| **Sleep Guard** | One-click **Keep Awake** (`1h`, `3h`, `Until 7am`, indefinite) + optional lid-closed agent watcher with thermal & battery cut-offs | Menu Bar |
| **Repo Sync** | Hourly fast-forward `git pull --ff-only` across one or more project folders + optional agent `SessionStart` hooks | `⌘⇧R` |
| **Mac Settings** | Hard-to-find macOS tweaks (screenshots, default browser/file apps, Finder toggles, dev setup, Chrome downloads) with **Undo All Changes** | Main Window |
| **Menu Bar Organizer** | Zero-flicker native hiding of unpinned third-party menu bar icons *(macOS 27+)* | `⌃⌥⌘Space` |

### 1. Clipboard
- Preserves rich formats: plain text, RTF, HTML, images, links, hex colors, and files.
- Floating bottom-screen card browser (**⌃⌥V**) with instant search, pinboards, Quick Look-style previews (`Space`), snippet editor (`⌘N`), and sequential **Paste Stack** (**⌃⌥P**).
- Automatically skips confidential/transient pasteboard entries and password managers.
- Stored locally in `~/Library/Application Support/Gary Tools/Clipboard` with `0700`/`0600` permissions.

### 2. Context Grab
- Press **⌃⌥G**, drag over any area of the screen (or press `Space` to pick a window), and paste one structured Markdown block straight into your coding agent or chat.
- Captures the source app & window title, active browser URL, git repo & branch, highlighted error lines, full on-device Vision OCR text, and the screenshot image + file path.
- Keeps the newest 50 captures locally in `~/Library/Application Support/Gary Tools/Captures` (`0700`/`0600`) and adds them to Clipboard history.

### 3. Sleep Guard
- **Keep Awake** works out of the box with `1h`, `3h`, `Until 7am`, and indefinite presets — no extra tools required.
- Safety cut-offs protect your Mac on low battery, Low Power Mode, sustained heat with the lid closed, and a configurable lid-closed battery time limit.
- Automatic screen lock on lid close (skipped when connected to an external monitor).
- Optional **Agent Watcher**: if [Herdr](https://herdr.dev) is installed, keeps your Mac awake (even with the lid closed) while agents are working.

### 4. Repo Sync
- Periodically runs safe, fast-forward-only pulls (`git pull --ff-only`) across any number of project folders you choose (checking top-level repos and one grouping subfolder deep) while your Mac is awake.
- Never merges, rebases, force-pushes, or touches uncommitted work.
- Optional one-click `SessionStart` hooks for **Claude Code**, **Codex**, and **Antigravity** (only shown for CLIs detected on your Mac).

### 5. Mac Settings
- **Screenshots:** Custom save folder, image format, drop shadow, floating thumbnail, and date in filename.
- **Default Apps:** Set your default browser and default editor for `.md`, text, config, and code files (individually or by group).
- **Finder:** Show hidden files, file extensions, path bar, full POSIX path in title, and disable `.DS_Store` files on network/USB drives.
- **Developer & Chrome:** Create/pin your developer folder, install Command Line Tools & Homebrew, install Google Chrome (verifying Google's code signature), and set Chrome's download folder across profiles with automatic backups.
- **Fail-safe undo:** Original values are journaled before the first edit so **Undo All Changes** restores everything cleanly.

### 6. Menu Bar Organizer *(macOS 27+)*
- Uses macOS 27's native `MenuBarClientCore` visibility assertions to tuck away unpinned third-party icons instantly with zero flicker while keeping macOS system items visible.
- Includes a `«` / `»` toggle, drag-and-drop layout editor (`⌘E`), hover-to-reveal, floating `Show icons` recovery pill, and global reveal shortcut (**⌃⌥⌘Space**).
- Automatically restores all icons on reveal, quit, or crash. *(Unavailable on macOS 14–26; all other Gary Tools features work normally.)*

### 7. First-Run Setup Wizard & Live Permissions
- Automatically opens on fresh installs (and can be re-run anytime from **Gary Tools → Run Setup Wizard…** or **Settings → General**).
- Walks through **Accessibility**, **Screen Recording**, **Background Daemon**, optional **Lid-Close Sleep Control (`pmset`)** via a native macOS admin prompt, **Git identity & GitHub login**, **Repo Sync folders**, and optional **Mac Settings**.
- Permissions refresh live as soon as you return from System Settings.

---

## Permissions

Every permission stays on your Mac and is optional depending on which utilities you use:

| Permission | Used for |
| --- | --- |
| **Accessibility** | Direct paste into the previous app (Clipboard), window titles (Context Grab), Finder sidebar helper |
| **Screen Recording** | Region/window capture & on-device OCR (Context Grab) |
| **Background Daemon** | Sleep Guard and hourly Repo Sync when the main window is closed |
| **Lid-Close `pmset` Rule** *(optional)* | Keeping the Mac awake with the lid closed (configured in one click via macOS admin prompt) |

---

## Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `⌃⌥V` | Open Clipboard Browser |
| `⌃⌥P` | Paste next item from Paste Stack |
| `⌃⌥G` | Context Grab (region or window) |
| `⌃⌥⌘Space` | Reveal all Menu Bar icons *(macOS 27+)* |
| `⌘⇧R` | Pull Repos Now |
| `⌘,` | Open Settings |

---

## Developer Workflow

```bash
# One-time setup: create a local trusted signing cert so macOS permissions persist across rebuilds
./scripts/setup-signing.sh

# Check if newer commits exist on origin without modifying the working tree
./update.sh --check

# Pull latest, run tests, rebuild, and cleanly restart Gary Tools + daemon
./update.sh

# Test, rebuild, and restart from your local working tree (add --push to push after tests pass)
./update.sh --local

# Run XCTest suite
./test.sh

# Build dist/Gary Tools.app only
./build.sh

# Build & install (--applications for /Applications/Gary Tools.app, --local-dist for dist/)
./install.sh
```

### Architecture

- `Sources/MenuBarBridge/` — Objective-C bridge for macOS 27 `MenuBarClientCore` visibility assertions
- `Sources/GaryCore/` — Pure, testable Swift core logic (clipboard store/monitor, context grab, repo sync config & hooks, update checker, onboarding state, Mac settings journal, menu bar policy, non-destructive migration)
- `Sources/GaryTools/` — Native AppKit + SwiftUI app (Dock app, unified Menu Bar Hub, Setup Wizard, floating Clipboard Browser, Settings)
- `scripts/` — `bootstrap.sh`, `setup-signing.sh`, `lidguard.sh`, `dev-pull-all.sh`, `helper.swift`, `make-icon.swift`
- `Tests/` — XCTest unit test suite

---

## Data & Privacy

All persistent state stays on your Mac under `~/Library/Application Support/Gary Tools/`:
- `settings.conf` — Sleep Guard & Repo Sync settings
- `source-repo.txt` — Recorded source checkout path used by the built-in updater (`0600`)
- `Clipboard/` — Clipboard index, raw payloads, and thumbnails (`0700`/`0600`)
- `Captures/` — Context Grab screenshots, newest 50 (`0700`/`0600`)
- `mac-settings-originals.plist` & `Chrome Backups/` — Undo records for Mac Settings
- Logs: `~/Library/Logs/gary-tools.log` and `~/Library/Logs/gary-tools-update.log`

## License

MIT
