# Vision

`Gary Tools` exists so that one developer's Mac keeps working for them while AI agents do the work.
It serves a developer who delegates real work to coding agents (Herdr, Claude Code, Codex) and steps away from the keyboard while they run.
It turns that developer's Mac - its power state, menu bar, clipboard and local repos - into a quiet, trustworthy layer around agent work.
It owns exactly one thing: the ambient layer of the Mac, the parts that run whether or not you are looking.

## Agents are the reason

Every tool here earns its place by making delegated agent work smoother.
Sleep Guard exists because a closed lid used to kill a running Herdr agent; it stays awake while agents work and lets the Mac sleep when they finish.
Repo Sync exists so every agent session starts on fresh code, and the same script feeds Claude Code, Codex and Antigravity session hooks.
Waiting on the human is part of agent work: the Mac stays reachable for a few minutes when an agent stops to ask a question.
General Mac utilities are welcome only when they remove friction a developer hits while agents run.

## Local, private, yours

Everything lives on the Mac, in one folder under `~/Library/Application Support/Gary Tools/`.
There are no accounts, no telemetry and no cloud sync.
Private data gets private permissions (`0700` folders, `0600` files).
The clipboard refuses what other apps mark as confidential or transient, and ignores password managers by default.
A feature that needs a server Gary Tools does not run on the Mac is refused, however useful.

## Safe by construction

Gary Tools never destroys the user's work or state.
Repo Sync only fast-forwards; it never merges, rebases, pushes or touches uncommitted work.
Migrations from older apps copy and keep the originals.
Staying awake always has a cut-off: low battery, Low Power Mode, sustained heat and a lid-closed battery limit.
Hiding menu bar icons never hides macOS system items, and every hidden icon comes back on reveal, quit or crash.
When safety and convenience collide, safety wins and the user is told why (for example, a notification when Sleep Guard puts the Mac to sleep).

## One native app

Gary Tools is one Swift and SwiftUI app, not a bundle of separate utilities.
LidGuard, Paste Local and ArrowBar were folded into it, and new tools join it rather than ship beside it.
It has no third-party package dependencies.
It prefers the platform's own mechanism to a workaround, and drops the workaround when the platform catches up, as the menu bar moved to `MenuBarClientCore` on macOS 27.
Logic that can be tested lives in `GaryCore`, and is covered by XCTest.
Bugs are fixed at the cause, not papered over in the UI.

## Plain-language control

Settings are written for a person, not a parser: every option in `settings.conf` says in plain words what yes and no do.
Changes apply within seconds, with no restart or reinstall.
Common choices are one click from the menu bar (Keep Awake for 1h, 3h, until 7am).
Keyboard shortcuts reach everything a hand reaches for often.

## Scope

Gary Tools is not an agent runner; Herdr, Helm and the agents' own CLIs run agents, and Gary Tools keeps the Mac fit for them.
It is not a team or multi-user product, a cloud service, or a cross-platform app.
It is not a general productivity suite or a launcher.
It holds itself to its own rules: its own data stays in its own folder, and its own installer cleans up what it replaces.

A change aligns when it makes delegated agent work on this Mac smoother or safer, stays local, fails safe, and lives inside the one native app.
A change should be resisted when it needs an account or a remote server, risks the user's code or data, ships as a separate app, adds a third-party dependency, or serves a Mac user who does not work with agents.
