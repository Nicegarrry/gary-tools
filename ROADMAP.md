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
