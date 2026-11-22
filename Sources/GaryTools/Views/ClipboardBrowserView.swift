import AppKit
import GaryCore
import SwiftUI

struct BrowserActions {
    var paste: (UUID, Bool) -> Void
    var copy: (UUID, Bool) -> Void
    var preview: (UUID) -> Void
    var edit: (UUID) -> Void
    var rename: (UUID) -> Void
    var newText: () -> Void
    var newBoard: () -> Void
    var renameBoard: (UUID) -> Void
    var deleteBoard: (UUID) -> Void
    var deleteClip: (UUID) -> Void
    var pasteStack: (Bool) -> Void
    var settings: () -> Void
    var togglePause: () -> Void
    var hide: () -> Void
}

struct ClipboardBrowserView: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var state: BrowserState
    let actions: BrowserActions
    @FocusState private var searchFocused: Bool
    var results: [Clip] { state.results(store) }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar.padding(.horizontal, 28).padding(.bottom, 18)
            if results.isEmpty { emptyState } else { clips }
            Spacer(minLength: 14)
            if !store.stack.isEmpty { stackBar }
            footer
        }
        .foregroundStyle(AppTheme.text)
        .background(GlassBackground(radius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 0.5))
        .tint(AppTheme.rust)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .focusPasteSearch)) { _ in searchFocused = true }
        .onChange(of: state.query) { _, _ in state.selected = results.first?.id }
        .onChange(of: state.board) { _, _ in state.selected = results.first?.id }
        .onChange(of: state.kind) { _, _ in state.selected = results.first?.id }
        .onChange(of: state.source) { _, _ in state.selected = results.first?.id }
        .onChange(of: state.days) { _, _ in state.selected = results.first?.id }
        .onChange(of: store.clips) { _, _ in if !results.contains(where: { $0.id == state.selected }) { state.selected = results.first?.id } }
    }

    private var header: some View {
        HStack(spacing: 24) {
            HStack(spacing: 9) {
                GaryBrandMark(size: 20)
                Text("Clipboard").font(.system(size: 15, weight: .medium)).tracking(0.1)
            }.fixedSize()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    boardTab("History", id: nil)
                    ForEach(store.boards) { board in
                        boardTab(board.name, id: board.id)
                            .contextMenu {
                                Button("Rename…") { actions.renameBoard(board.id) }
                                Button("Delete pinboard…", role: .destructive) { actions.deleteBoard(board.id) }
                            }
                    }
                    ChromeButton(symbol: "plus", label: "New pinboard", action: actions.newBoard)
                }
            }
            HStack(spacing: 4) {
                ChromeButton(symbol: store.paused ? "play" : "pause", label: store.paused ? "Resume capture" : "Pause capture", action: actions.togglePause)
                Menu {
                    Button("New text snippet…", action: actions.newText)
                    Button("New pinboard…", action: actions.newBoard)
                    Divider()
                    Button("Settings…", action: actions.settings)
                    Button("Close", action: actions.hide)
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15)).foregroundStyle(AppTheme.secondary).frame(width: 28, height: 28)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More actions")
                ChromeButton(symbol: "xmark", label: "Close · Esc", action: actions.hide)
            }
        }.padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 18)
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .regular)).foregroundStyle(AppTheme.muted)
            TextField("Search your clipboard", text: $state.query)
                .textFieldStyle(.plain).font(.system(size: 16, weight: .regular)).focused($searchFocused)
                .onSubmit { if let id = state.selected ?? results.first?.id { actions.paste(id, false) } }
                .accessibilityLabel("Search your clipboard")
            if !state.query.isEmpty {
                ChromeButton(symbol: "xmark.circle.fill", label: "Clear search") { state.query = "" }
            }
            Menu {
                Picker("Content type", selection: $state.kind) {
                    Text("All types").tag(ClipKind?.none)
                    ForEach(ClipKind.allCases, id: \.self) { kind in Label(kind.label, systemImage: kind.symbol).tag(Optional(kind)) }
                }
                Picker("Source app", selection: $state.source) {
                    Text("All apps").tag("")
                    ForEach(sourceApps, id: \.0) { app in Text(app.1).tag(app.0) }
                }
                Picker("Copied", selection: $state.days) {
                    Text("Any time").tag(0); Text("Last 24 hours").tag(1); Text("Last 7 days").tag(7); Text("Last 30 days").tag(30)
                }
                if state.hasFilters { Divider(); Button("Clear filters") { state.resetFilters() } }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "slider.horizontal.3")
                    Text(state.hasFilters ? "Filtered" : "Filters")
                    if state.hasFilters { Circle().fill(AppTheme.rust).frame(width: 4, height: 4) }
                }.font(.system(size: 12)).foregroundStyle(state.hasFilters ? AppTheme.accentText : AppTheme.secondary)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, 16).frame(height: 46)
        .background(.white.opacity(0.045), in: Capsule())
    }

    private var clips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { offset, clip in
                        ClipCard(clip: clip, image: store.thumbnail(for: clip.id), selected: state.selected == clip.id,
                                 stackIndex: store.stack.firstIndex(of: clip.id), shortcut: offset < 9 ? offset + 1 : nil)
                            .id(clip.id)
                            .onTapGesture(count: 2) { actions.paste(clip.id, false) }
                            .onTapGesture { state.selected = clip.id; searchFocused = false }
                            .contextMenu { clipMenu(clip) }
                            .onDrag { store.dragProvider(for: clip.id) }
                    }
                }.padding(.horizontal, 28).padding(.vertical, 3)
            }
            .onChange(of: state.selected) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }.frame(height: 228)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: store.paused ? "pause.circle" : state.query.isEmpty && !state.hasFilters ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 29, weight: .ultraLight)).foregroundStyle(AppTheme.accentText).padding(.bottom, 4)
            Text(emptyTitle).font(.system(size: 20, weight: .regular))
            Text(emptyDetail).font(.system(size: 13)).foregroundStyle(AppTheme.secondary)
            if state.board != nil { Button("Create a snippet", action: actions.newText).buttonStyle(FlatButtonStyle()).padding(.top, 4) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 28)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: store.paused ? "pause.circle" : "circle.inset.filled")
                .font(.system(size: 8)).foregroundStyle(store.paused ? AppTheme.accentText : AppTheme.muted)
            Text(store.paused ? "Capture paused" : "Only on this Mac")
            Text("/").foregroundStyle(AppTheme.muted.opacity(0.6))
            Text("\(results.count) clips")
            if !store.notice.isEmpty { Text("·"); Text(store.notice).lineLimit(1).truncationMode(.tail) }
            Spacer(minLength: 16)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    ShortcutHint(keys: "← →", label: "Browse")
                    ShortcutHint(keys: "↵", label: "Paste")
                    ShortcutHint(keys: "⌘C", label: "Copy")
                    ShortcutHint(keys: "Space", label: "Preview")
                }.fixedSize()
                HStack(spacing: 16) {
                    ShortcutHint(keys: "↵", label: "Paste")
                    ShortcutHint(keys: "⌘C", label: "Copy")
                }.fixedSize()
                ShortcutHint(keys: "↵", label: "Paste").fixedSize()
            }.layoutPriority(-1)
        }
        .font(.system(size: 11)).foregroundStyle(AppTheme.muted)
        .padding(.horizontal, 28).padding(.bottom, 18)
    }

    private var sourceApps: [(String, String)] {
        Dictionary(store.clips.filter { !$0.sourceBundle.isEmpty }.map { ($0.sourceBundle, $0.sourceName) }, uniquingKeysWith: { a, _ in a })
            .map { ($0.key, $0.value) }.sorted { $0.1 < $1.1 }
    }

    private var emptyTitle: String {
        if !state.query.isEmpty || state.hasFilters { return "No matching clips" }
        return state.board == nil ? "A little less to remember." : "Keep the good stuff close."
    }

    private var emptyDetail: String {
        if !state.query.isEmpty || state.hasFilters { return "Try another search or clear your filters." }
        return state.board == nil ? "Copy text, an image, a link, or a file. We’ll keep it here." : "Pin a clip to this board, or write something new."
    }

    private func boardTab(_ label: String, id: UUID?) -> some View {
        Button { state.board = id } label: {
            VStack(spacing: 7) {
                Text(label).font(.system(size: 12, weight: state.board == id ? .medium : .regular))
                    .foregroundStyle(state.board == id ? AppTheme.text : AppTheme.secondary).lineLimit(1)
                Capsule().fill(state.board == id ? AppTheme.rust : .clear).frame(height: 2)
            }.padding(.top, 7).fixedSize(horizontal: true, vertical: false).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(state.board == id ? .isSelected : [])
    }

    @ViewBuilder private func clipMenu(_ clip: Clip) -> some View {
        Button("Paste") { actions.paste(clip.id, false) }
        Button("Copy") { actions.copy(clip.id, false) }
        if !clip.text.isEmpty {
            Button("Paste as plain text") { actions.paste(clip.id, true) }
            Button("Copy as plain text") { actions.copy(clip.id, true) }
        }
        Divider()
        Button("Preview…") { actions.preview(clip.id) }
        if [.text, .link, .color].contains(clip.kind) { Button("Edit text…") { actions.edit(clip.id) } }
        Button("Rename…") { actions.rename(clip.id) }
        Button("Duplicate") { store.duplicate(clip.id) }
        Menu("Pinboards") {
            ForEach(store.boards) { board in
                Button { store.togglePin(clip.id, board: board.id) } label: {
                    if clip.boards.contains(board.id) { Label(board.name, systemImage: "checkmark") } else { Text(board.name) }
                }
            }
            Button("New pinboard…", action: actions.newBoard)
        }
        if clip.kind == .files {
            Button("Reveal in Finder") {
                store.perform { NSWorkspace.shared.activateFileViewerSelecting(try store.payload(for: clip.id).fileURLs) }
            }
        }
        Divider()
        Button(store.stack.contains(clip.id) ? "Remove from stack" : "Add to paste stack") {
            if store.stack.contains(clip.id) { store.stack.removeAll { $0 == clip.id } } else { store.enqueue(clip.id) }
        }
        Button("Delete…", role: .destructive) { actions.deleteClip(clip.id) }
    }

    private var stackBar: some View {
        VStack(spacing: 0) {
            Hairline().padding(.horizontal, 28)
            HStack(spacing: 14) {
                Image(systemName: "square.3.layers.3d").foregroundStyle(AppTheme.accentText)
                Text("Stack").fontWeight(.medium)
                Text("\(store.stack.count)").foregroundStyle(AppTheme.accentText)
                Text(store.stack.first.flatMap { id in store.clips.first { $0.id == id } }?.title ?? "")
                    .lineLimit(1).foregroundStyle(AppTheme.secondary)
                Spacer(minLength: 0)
                Button("Reverse") { store.stack.reverse() }.buttonStyle(.plain).foregroundStyle(AppTheme.secondary)
                Button("Clear") { store.stack = [] }.buttonStyle(.plain).foregroundStyle(AppTheme.secondary)
                Button("Paste all text") { actions.pasteStack(true) }.buttonStyle(FlatButtonStyle())
                Button("Paste next") { actions.pasteStack(false) }.buttonStyle(FlatButtonStyle(primary: true))
            }.font(.system(size: 12)).padding(.horizontal, 28).padding(.vertical, 10)
        }.padding(.bottom, 10)
    }
}

struct ClipCard: View {
    let clip: Clip
    let image: NSImage?
    let selected: Bool
    let stackIndex: Int?
    let shortcut: Int?
    @LocalState private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: clip.kind.symbol).font(.system(size: 11)).foregroundStyle(selected ? AppTheme.accentText : AppTheme.secondary)
                Text(clip.sourceName).font(.system(size: 11)).foregroundStyle(AppTheme.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if clip.isPinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(AppTheme.accentText) }
                if let stackIndex { Text("\(stackIndex + 1)").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(AppTheme.accentText) }
            }.frame(height: 22).padding(.bottom, 13)
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack {
                Text(clip.copiedAt, style: .relative).lineLimit(1)
                Spacer(minLength: 4)
                if selected { Text("↵ Paste").foregroundStyle(AppTheme.accentText) }
                else if let shortcut { Text("⌘\(shortcut)").font(.system(size: 10, design: .monospaced)) }
            }.font(.system(size: 10)).foregroundStyle(AppTheme.muted).padding(.top, 12)
        }
        .padding(17).frame(width: 232, height: 220)
        .background(.white.opacity(selected ? 0.075 : hovered ? 0.055 : 0.025), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? AppTheme.sky.opacity(0.7) : .clear, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(clip.kind.label): \(clip.title), from \(clip.sourceName)")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : [.isButton])
    }

    @ViewBuilder private var content: some View {
        if let image {
            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else if clip.kind == .color, let color = NSColor(hex: clip.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(nsColor: color)).frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(clip.text).font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundStyle(AppTheme.text)
            }
        } else {
            VStack(alignment: .leading, spacing: 9) {
                if clip.kind == .link {
                    Text(linkDomain).font(.system(size: 18, weight: .medium)).lineLimit(1).foregroundStyle(AppTheme.text)
                }
                if clip.kind == .files {
                    Image(systemName: "folder").font(.system(size: 27, weight: .ultraLight)).foregroundStyle(AppTheme.accentText).padding(.bottom, 4)
                }
                Text(clip.kind == .files ? clip.title : clip.text.isEmpty ? clip.title : clip.text)
                    .font(.system(size: clip.kind == .link ? 12 : 13, weight: .regular)).lineSpacing(4)
                    .lineLimit(clip.kind == .link ? 4 : 6)
                    .foregroundStyle(clip.kind == .link ? AppTheme.secondary : AppTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var linkDomain: String { URL(string: clip.text.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? "Saved link" }
}

struct ClipPreviewView: View {
    let clip: Clip
    let payload: ClipPayload
    let copy: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Label(clip.kind.label, systemImage: clip.kind.symbol).foregroundStyle(AppTheme.sky)
                Text("/").foregroundStyle(AppTheme.muted)
                Text(clip.sourceName).foregroundStyle(AppTheme.secondary).lineLimit(1)
                Spacer(minLength: 12)
                Button("Copy", action: copy).buttonStyle(FlatButtonStyle(primary: true))
            }.font(.system(size: 12)).padding(.bottom, 20)
            Text(clip.title).font(.system(size: 23, weight: .regular)).lineLimit(3).textSelection(.enabled).padding(.bottom, 22)
            Hairline().padding(.bottom, 22)
            content
            Spacer(minLength: 16)
            HStack {
                Text(clip.copiedAt.formatted(date: .abbreviated, time: .shortened))
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(clip.byteCount), countStyle: .file))
                Text("· \(payload.items.count) item(s), \(payload.items.flatMap(\.representations).count) formats")
            }.font(.system(size: 10)).foregroundStyle(AppTheme.muted).padding(.top, 18)
        }
        .padding(.horizontal, 30).padding(.top, 48).padding(.bottom, 24)
        .foregroundStyle(AppTheme.text).tint(AppTheme.rust)
        .background(GlassBackground(radius: 0)).preferredColorScheme(.dark)
        .frame(minWidth: 500, minHeight: 360)
    }

    @ViewBuilder private var content: some View {
        if let image = payload.image {
            GeometryReader { geometry in
                Image(nsImage: image).resizable().scaledToFit().frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        } else if !payload.fileURLs.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(payload.fileURLs.enumerated()), id: \.offset) { _, url in
                        HStack(spacing: 14) {
                            Image(systemName: "doc").font(.system(size: 25, weight: .ultraLight)).foregroundStyle(AppTheme.sky)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(url.lastPathComponent).font(.system(size: 13))
                                Text(url.path).font(.system(size: 11)).foregroundStyle(AppTheme.muted).textSelection(.enabled)
                            }
                            Spacer()
                            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(FlatButtonStyle())
                        }
                    }
                }
            }
        } else {
            ScrollView {
                Text(payload.plainText ?? "No text preview is available. Copy restores the original formats.")
                    .font(.system(size: 14)).lineSpacing(6).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct SnippetEditorView: View {
    @LocalState var text: String
    let title: String
    let save: (String) -> Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 24, weight: .regular))
                Text("A few words, ready when you need them.").font(.system(size: 12)).foregroundStyle(AppTheme.secondary)
            }
            TextEditor(text: $text).font(.system(size: 14)).scrollContentBackground(.hidden)
                .padding(12).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Snippet text")
            HStack(spacing: 10) {
                Label("Saved on this Mac", systemImage: "lock").font(.system(size: 10)).foregroundStyle(AppTheme.muted)
                Spacer()
                Button("Cancel") { NSApp.keyWindow?.close() }.buttonStyle(FlatButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Save snippet") { if save(text) { NSApp.keyWindow?.close() } }.buttonStyle(FlatButtonStyle(primary: true))
                    .disabled(text.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28).padding(.top, 48).padding(.bottom, 24)
        .foregroundStyle(AppTheme.text).tint(AppTheme.rust)
        .background(GlassBackground(radius: 0)).preferredColorScheme(.dark)
        .frame(width: 600, height: 440)
    }
}
