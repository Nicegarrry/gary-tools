# Roadmap

Candidate utilities, checked against [VISION.md](VISION.md). Nothing here is promised; a candidate gets built when Nick picks it.

## Candidates

### Disk Delta

"What ate 40 GB since yesterday?"
Gary Tools snapshots folder sizes once a day and shows what grew, biggest first, with a click to reveal each folder in Finder.
It starts at folder level and never deletes anything.
Fits the vision: a small local utility an agentic engineer hits often (`node_modules`, build caches, simulators, Docker, worktrees), and it is read-only, so it is safe by construction.

### Unplug Check

One click before you grab the laptop: which external drives are still busy.
It starts with drives only, and says "couldn't verify" rather than give a false all-clear.
Fits the vision: a daily, local utility whose first rule is not to mislead, which is the same safety-first rule Sleep Guard follows.

### System widget

A desktop and Notification Center widget with the basics at a glance: CPU, memory and how many agents are live.
The agent count reads the same Herdr status Sleep Guard already watches; it shows agents, never starts them.
Fits the vision: local, small and used all day. It ships as a widget extension inside the one app, not a separate app.
Open question: a WidgetKit extension needs the app built as an Xcode project with an app group, which the SwiftPM build does not do today.

### Dark mode anything

Like the Noir extension for Safari, but for any app or page: one toggle that turns a bright window dark.
Fits the vision as a small, local utility used every day.
Open question: macOS cannot force another app into dark mode, so there are two routes.
The first is a Safari web extension (needs the Xcode project the widget also needs).
The second is a per-window smart-invert overlay that works everywhere but is rougher on images.
Start with the route that covers the apps Nick actually squints at.

### Markdown viewer

A very simple Markdown viewer and editor, simpler than MarkText: open a `.md` file, read it rendered, flip to edit, save.
Useful for reading the plans, handoffs and READMEs agents write all day.
Tension with the vision: Gary Tools owns the background layer, and an editor is a foreground app.
It fits if it stays a quick window inside Gary Tools (open from Finder or a hotkey, close when done), not a full writing app with tabs, sync or plugins.

### Chrome extension

A small Gary Tools extension for Chrome, talking to the app through Chrome native messaging, with two starting features.
**Send page to agent**: a clean page-to-Markdown copy plus the URL, handed to an agent Nick picks (onto the clipboard, or into that agent's inbox).
It is Context Grab for the browser, and only a handoff: Gary Tools never starts the agent.
**Dark mode while browsing**: the first step of Dark mode anything, done where it is easiest.
Tension with the vision: an extension ships outside the one app.
It fits only as a thin companion with no settings or logic of its own; everything else stays in Gary Tools.

Rejected: letting the Claude app control local agents through the browser.
Claude in Chrome already covers browser control, it breaks the rule that Gary Tools never starts agents, and a browser door into local agents is a security risk.
