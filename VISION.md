# Vision

`Gary Tools` exists so that an agentic engineer's Mac gets out of the way and quietly helps.
It is a small collection of helpful Mac utilities for someone who spends the day directing coding agents, built first and foremost for Nick and his two Macs.
It takes the small frictions of that work - a Mac that sleeps too soon, a cluttered menu bar, a lost clipboard, stale repos - and removes them.
It owns exactly one thing: the background layer of the Mac, the utilities that run whether or not you are looking.

## A small collection, built for one person

Gary Tools is a handful of utilities, each small, each useful on its own: Sleep Guard, Clipboard, Menu Bar Organizer and Repo Sync today.
A new utility earns a place when Nick would reach for it most days.
It is shaped around Nick's setup and habits, not a market: his choices are the defaults, and a utility may assume his tools (Herdr, his `~/Developer` layout, his agents) are installed.
Making it easy for a stranger to install is not a goal and never justifies a compromise.
The collection stays small: a utility that stops earning its place is removed.

## For agentic engineers, not about agents

The utilities fit how an agentic engineer works: long-running sessions, work that carries on with the lid closed, two Macs, fresh repos for every session.
Sleep Guard keeps the Mac awake while Herdr agents work; Repo Sync keeps every repo fresh and feeds Claude Code, Codex and Antigravity session hooks.
Utilities with nothing to do with agents are welcome when they help that same person at that same Mac.
Gary Tools never starts, schedules or runs agents; Herdr, Helm and the agents' own CLIs do that.

## Local, private, his

Everything lives on Nick's Macs, under `~/Library/Application Support/Gary Tools/`.
There are no accounts, no telemetry and no Gary Tools server.
Apple's own platform services, such as push notifications to his phone and Watch, count as local.
The two Macs talk to each other directly over the local network, to share the clipboard and settings, never through a third-party cloud.
Private data gets private permissions (`0700` folders, `0600` files).
The clipboard refuses what other apps mark as confidential or transient, and ignores password managers by default.

## Safe by construction

Gary Tools never destroys Nick's work or state.
Repo Sync fast-forwards on pull, and may push Nick's own branches so committed work is never stranded on one Mac.
It never merges, rebases, force-pushes, rewrites history or touches uncommitted work.
Migrations from older apps copy and keep the originals.
Staying awake always has a cut-off: low battery, Low Power Mode, sustained heat and a lid-closed battery limit.
When a cut-off is about to sleep the Mac while an agent is mid-task, Gary Tools first saves what it can of that session's state, then sleeps.
Hiding menu bar icons never hides macOS system items, and every hidden icon comes back on reveal, quit or crash.
When safety and convenience collide, safety wins and Nick is told why.

## One native app

Gary Tools is one Swift and SwiftUI app, not a bundle of separate apps.
LidGuard, Paste Local and ArrowBar were folded into it, and new utilities join it rather than ship beside it.
Dependencies are few and earn their place; a well-known Mac library such as Sparkle is fine when building it ourselves would be worse.
It prefers the platform's own mechanism to a workaround, and drops the workaround when the platform catches up, as the menu bar moved to `MenuBarClientCore` on macOS 27.
Logic that can be tested lives in `GaryCore`, and is covered by XCTest.
Bugs are fixed at the cause, not papered over in the UI.

## Plain-language control

Settings are written for a person, not a parser: every option in `settings.conf` says in plain words what yes and no do.
Changes apply within seconds, with no restart or reinstall.
Common choices are one click from the menu bar (Keep Awake for 1h, 3h, until 7am).
Keyboard shortcuts reach everything a hand reaches for often.

## Scope

Gary Tools is not an agent tool, runner or scheduler, a team or multi-user product, a cloud service, a cross-platform app, or a suite that grows without limit.
It holds itself to its own rules: its own data stays in its own folder, and its own installer cleans up what it replaces.

A change aligns when it is a small utility Nick would use most days at his Mac, stays on his devices and Apple's services, fails safe, and lives inside the one native app.
A change should be resisted when it starts or schedules agents, needs an account or a server of its own, risks his code or data, ships as a separate app, or exists to serve users other than Nick.
