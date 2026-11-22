import AppKit
import GaryCore
import SwiftUI

struct ClipboardHomeView: View {
    @ObservedObject var coordinator: AppCoordinator
    @LocalState private var query = ""
    @LocalState private var board: UUID? = nil

    private var store: LibraryStore { coordinator.clipboardStore }
    private var clips: [Clip] { store.filtered(query: query, board: board, kind: nil, source: "", days: 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Controls row: search + pause toggle
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.muted)
                    TextField("Search clipboard history", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5))
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))

                Button(store.paused ? "Resume Capture" : "Pause Capture") {
                    coordinator.toggleClipboardPause()
                }
                .buttonStyle(FlatButtonStyle(compact: true))
            }

            // Pinboard tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    boardPill("All History (\(store.clips.count))", id: nil)
                    ForEach(store.boards) { item in
                        let count = store.clips.filter { $0.boards.contains(item.id) }.count
                        boardPill("\(item.name) (\(count))", id: item.id)
                            .contextMenu {
                                Button("Rename…") { coordinator.renameBoard(item.id) }
                                Button("Delete pinboard…", role: .destructive) { coordinator.deleteBoard(item.id) }
                            }
                    }
                    Button { coordinator.newBoard() } label: {
                        Label("New board", systemImage: "plus")
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.sky)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Paste stack strip if active
            if !store.stack.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "square.3.layers.3d").foregroundStyle(AppTheme.sky)
                    Text("Paste Stack · \(store.stack.count) queued")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Reverse") { store.stack.reverse() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(AppTheme.secondary)
                    Button("Clear") { store.stack = [] }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(AppTheme.secondary)
                    Button("Paste Next  ⌃⌥P") { coordinator.pasteStack(false) }.buttonStyle(FlatButtonStyle(primary: true, compact: true))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.sky.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // Clip grid
            if clips.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: store.paused ? "pause.circle" : "doc.on.clipboard")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(AppTheme.sky)
                    Text(query.isEmpty ? "No clips yet" : "No matching clips")
                        .font(.system(size: 16, weight: .medium))
                    Text(query.isEmpty ? "Copy text, links, colors, images, or files — or press ⌃⌥V anywhere." : "Try a different search or switch pinboards.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(AppTheme.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 12)], spacing: 12) {
                    ForEach(clips.prefix(60)) { clip in
                        compactCard(clip)
                    }
                }
            }
        }
    }

    private func boardPill(_ label: String, id: UUID?) -> some View {
        let active = board == id
        return Button { board = id } label: {
            VStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 12, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? AppTheme.text : AppTheme.secondary)
                Capsule().fill(active ? AppTheme.rust : .clear).frame(height: 2)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
    }

    private func compactCard(_ clip: Clip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: clip.kind.symbol).font(.system(size: 11)).foregroundStyle(AppTheme.sky)
                Text(clip.sourceName).font(.system(size: 11)).foregroundStyle(AppTheme.secondary).lineLimit(1)
                Spacer()
                if clip.isPinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(AppTheme.sky) }
            }

            if let thumb = store.thumbnail(for: clip.id) {
                Image(nsImage: thumb).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else if clip.kind == .color, let ns = NSColor(hex: clip.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: ns)).frame(width: 34, height: 34)
                    Text(clip.text).font(.system(size: 13, weight: .medium, design: .monospaced))
                }
            } else {
                Text(clip.text.isEmpty ? clip.title : clip.text)
                    .font(.system(size: 12.5))
                    .lineSpacing(3)
                    .lineLimit(4)
                    .foregroundStyle(AppTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            HStack {
                Text(clip.copiedAt, style: .relative).font(.system(size: 10)).foregroundStyle(AppTheme.muted)
                Spacer()
                Button("Copy") { coordinator.copyClip(clip.id, false) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.sky)
            }
        }
        .padding(14)
        .frame(height: 152, alignment: .topLeading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.hairline, lineWidth: 1))
        .onTapGesture(count: 2) { coordinator.copyClip(clip.id, false) }
        .contextMenu {
            Button("Copy") { coordinator.copyClip(clip.id, false) }
            if !clip.text.isEmpty {
                Button("Copy as plain text") { coordinator.copyClip(clip.id, true) }
            }
            Divider()
            Button("Preview…") { coordinator.previewClip(clip.id) }
            if [.text, .link, .color].contains(clip.kind) { Button("Edit text…") { coordinator.editClip(clip.id) } }
            Button("Rename…") { coordinator.renameClip(clip.id) }
            Button("Duplicate") { store.duplicate(clip.id) }
            Menu("Pinboards") {
                ForEach(store.boards) { b in
                    Button { store.togglePin(clip.id, board: b.id) } label: {
                        if clip.boards.contains(b.id) { Label(b.name, systemImage: "checkmark") } else { Text(b.name) }
                    }
                }
                Button("New pinboard…") { coordinator.newBoard() }
            }
            Divider()
            Button(store.stack.contains(clip.id) ? "Remove from stack" : "Add to paste stack") {
                if store.stack.contains(clip.id) { store.stack.removeAll { $0 == clip.id } } else { store.enqueue(clip.id) }
            }
            Button("Delete…", role: .destructive) { coordinator.deleteClip(clip.id) }
        }
        .onDrag { store.dragProvider(for: clip.id) }
    }
}
