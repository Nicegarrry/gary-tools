# CubeBit appearance — Lidguard 1.1

The interface follows the same visual system as Paste Local:

- Exact palette: navy `#132A45`, sky blue `#7FB3DA`, rust `#B0552E`.
- Native behind-window blur with a translucent navy tint; solid navy when Reduce Transparency is enabled.
- Sidebar navigation across Agents, Keep Awake, Safety, Lid & Login, and Repos.
- Flat sections and thin separators in place of opaque outlined cards.
- Native rust switches, borderless choice menus, restrained step controls, and a rust primary action for Pull Now.
- Matching navy/sky/rust cup app icon and transparent native window title bar. Menu-bar state icons remain monochrome.
- Scrollable pane content, readable secondary text, semantic navigation selection, and keyboard-accessible toggles.

Verified locally:

- `./menubar/build.sh` compiles successfully for the existing macOS 13 deployment target.
- `codesign --verify --deep --strict Lidguard.app` passes; the bundle plist validates.
- The settings model is byte-for-byte identical to the source captured before the restyle. All 15 direct settings bindings remain present, along with the existing Keep Awake getter/setter actions.
- Menu/service behavior from `ensureLidguardRunning` through `refresh` is byte-for-byte identical to the pre-restyle source. Existing uncommitted Repos work was retained.
- The generated app icon was rendered and visually inspected.
- The settings screenshot renderer aborts in the tool sandbox, as did Paste Local's renderer. No live window-layout or blur verification is claimed.

To load the interface, choose **Quit Menu Icon** from Lidguard's menu and reopen `Lidguard.app` in the same project folder. Check all five panes and the Reduce Transparency fallback from a normal desktop session. Settings still save automatically.

The build stages compilation, icon generation, and signing before replacing the app bundle. It does not launch the background service or change personal settings.

## Title-bar correction — 1.1.1

The supplied desktop screenshot showed a separate strip above the rounded SwiftUI surface. The settings window now enables full-size content before attaching SwiftUI and explicitly sizes that full content area. One unrounded glass background extends under the native title bar and traffic lights; AppKit supplies the outer window corners. The sidebar shares that same material, and the native title-bar separator is hidden.

The patch compiles, the bundle plist validates, and its ad-hoc signature verifies. Live confirmation of the corrected title bar remains pending because desktop inspection is unavailable in this environment. Reopen the app to load version 1.1.1.
