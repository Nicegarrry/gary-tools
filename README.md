# lidguard

**Close your MacBook lid without killing your AI agents.**

lidguard watches your [Herdr](https://herdr.dev) agents. While any of them is working, closing the lid
won't put the Mac to sleep. The screen locks and the agents keep going. When they finish, the Mac goes to sleep.
It also has a built-in **Keep Awake** mode (like `caffeinate`) with timers.

It lives in your menu bar as a small cup icon:

| Icon | Meaning |
|---|---|
| 🌙 moon | Off — Mac sleeps normally |
| ☕ empty cup | On, no agents working |
| ☕ filled cup | Keeping the Mac awake for working agents |
| ♨️ steaming cup | Keep Awake mode |
| ⚠️ triangle | Background service isn't running |

**Click** to turn it on or off · **Option-click** for Keep Awake · **Right-click** for the menu and Settings

The version 1.1 settings interface matches Paste Local's CubeBit styling: translucent navy
(`#132A45`), sky blue (`#7FB3DA`) highlights, and rust (`#B0552E`) actions. All five settings
panes use a flat sidebar layout, quieter typography, and native controls. Reduce Transparency
in macOS Accessibility settings switches the background to solid navy.

The app has a matching flat cup icon; its menu-bar state icons stay monochrome for macOS.
See [appearance and verification notes](docs/appearance.md).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Nicegarrry/lidguard/main/install.sh | bash
```

It asks for your password once (see [How it works](#how-it-works)). Run the same command again to update.

**Requirements:**
- macOS 14 or later
- Apple's command line tools (`xcode-select --install`)
- `jq` (included with macOS 15+)
- [Herdr](https://herdr.dev) for the agent-watching features. Keep Awake works without it.

**Uninstall:**

```bash
~/.lidguard/install.sh --uninstall && rm -rf ~/.lidguard
```

## What it does

- **Agents working → stays awake.** Closing the lid or leaving it idle won't sleep the Mac. Only agents Herdr reports as `working` count.
- **Agent asks you something → waits a few minutes** (default 3) so you can answer remotely, then sleeps.
- **Agents finish → sleeps.** If lidguard was holding a closed lid awake, the Mac sleeps right away.
- **Locks the screen** the moment the lid closes, while everything keeps running.
- **Safety cut-offs** put the Mac to sleep anyway:
  - battery is below 20%
  - Low Power Mode is on
  - it's running hot with the lid closed (based on macOS's own heat rating)
  - the lid has been closed on battery for more than 4 hours (no limit when plugged in)
- **Tells you why** it put the Mac to sleep, with a notification you'll see on the lock screen.
- **Keep Awake:** keeps the Mac on no matter what, either until you turn it off or for 1 hour, 3 hours or until 7am.
- **Desk-friendly:** with the lid closed and an external monitor connected, it never locks or forces sleep.
- **Login options:** choose whether it starts at login, and whether it starts switched on or off (off by default).

All settings are in the Settings window (right-click → Settings…) or in `~/.lidguard/settings.conf`,
a plain-text file with notes for each option. Changes apply within seconds.

## How it works

- `lidguard.sh` is a small background script. Every 2 seconds it checks Herdr (`herdr agent list`), the lid, the battery and the Mac's heat rating.
- To keep a closed lid awake it toggles `pmset -a disablesleep`, which is the only reliable way to stop lid-close sleep on battery.
  - That needs root, so the installer adds `/etc/sudoers.d/lidguard`. It allows **only** `pmset -a disablesleep 0` and `pmset -a disablesleep 1` without a password, and nothing else.
- `lidguard-helper` is a small Swift program that reads the heat rating and locks the screen. Locking uses the same private macOS call as Apple menu → Lock Screen.
- `Lidguard.app` is the native SwiftUI menu bar app. It reads and writes `settings.conf`, and the script reports its status back to the menu.
- Everything is built from source on your Mac during install, so there are no downloaded binaries and no Gatekeeper prompts.

Log: `~/Library/Logs/lidguard.log`

## Caveats

- **Timing:** checks run every 2 seconds, so closing the lid within a second or two of an agent starting can still sleep the Mac.
- **Heat:** a Mac running flat out in a closed bag gets warm. The heat and battery cut-offs are there for that, so leave them on.
- **Keep Awake** ignores the battery rules on purpose. Use a timer if you might forget it.

## License

MIT
