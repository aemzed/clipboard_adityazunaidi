//
//  ContentView.swift
//  project_clipboard
//
//  Created by Adit's Macbook on 14/04/26.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var monitor: ClipboardMonitor
    @ObservedObject private var lifecycle = AppLifecycle.shared

    @State private var searchText: String = ""
    @State private var selectedID: UUID?
    @State private var copiedEntryID: UUID?
    @State private var clearCopiedIndicatorTask: DispatchWorkItem?

    @FocusState private var isSearchFocused: Bool

    private var filteredEntries: [ClipboardEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return store.entries
        }

        return store.entries.filter { entry in
            entry.preview.localizedCaseInsensitiveContains(query)
                || entry.value.localizedCaseInsensitiveContains(query)
                || entry.contentType.searchAliases.contains(where: {
                    $0.localizedCaseInsensitiveContains(query)
                })
                || entry.contentType.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    private var displayEntries: [ClipboardEntry] {
        Array(filteredEntries.prefix(20))
    }

    private var selectedEntry: ClipboardEntry? {
        displayEntries.first(where: { $0.id == selectedID })
    }

    var body: some View {
        ZStack {
            TranslucentBackgroundView(material: .hudWindow)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                searchBar
                quickActionsBar
                resultPanel
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
        .background(Color.clear)
        .onAppear {
            ensureSelection()
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onChange(of: searchText) { _, _ in
            ensureSelection()
        }
        .onChange(of: store.entries) { _, _ in
            ensureSelection()
        }
        .onMoveCommand(perform: moveSelection)
        .onCommand(#selector(NSResponder.insertNewline(_:))) {
            copySelectedEntryAndDismiss()
        }
        .onCommand(#selector(NSResponder.insertLineBreak(_:))) {
            copySelectedEntryAndDismiss()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            TextField("Cari Riwayat Papan Klip...", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .onSubmit {
                    copySelectedEntryAndDismiss()
                }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.20))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.30), lineWidth: 1)
        )
    }

    private var resultPanel: some View {
        Group {
            if displayEntries.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 10) {
                            ForEach(displayEntries) { entry in
                                SpotlightClipboardRow(
                                    entry: entry,
                                    isSelected: selectedID == entry.id,
                                    isCopied: copiedEntryID == entry.id,
                                    onSelect: {
                                        selectedID = entry.id
                                    },
                                    onCopy: {
                                        copyEntryAndDismiss(entry)
                                    }
                                )
                                .id(entry.id)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.trailing, 10)
                    }
                    .frame(maxHeight: 380)
                    .overlay(alignment: .trailing) {
                        if displayEntries.count > 1 {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.26))
                                .frame(width: 2.5, height: 84)
                                .padding(.trailing, 2)
                        }
                    }
                    .onChange(of: selectedID) { _, newValue in
                        guard let newValue else { return }
                        withAnimation(.easeInOut(duration: 0.16)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private var quickActionsBar: some View {
        HStack(spacing: 8) {
            Text("Shortcut: \(lifecycle.activeShortcutDisplay)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                lifecycle.presentShortcutEditor()
            } label: {
                Label("Edit Shortcut", systemImage: "keyboard")
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.18))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.26), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                lifecycle.confirmAndClearAllHistory()
            } label: {
                Label("Clear All", systemImage: "trash")
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.red.opacity(0.30))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.24), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(store.entries.isEmpty)
            .opacity(store.entries.isEmpty ? 0.55 : 1.0)
        }
        .padding(.horizontal, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))

            Text(searchText.isEmpty ? "Riwayat papan klip kosong" : "Tidak ada hasil")
                .font(.headline)
                .foregroundStyle(.white)

            Text(searchText.isEmpty ? "Salin sesuatu, lalu item akan muncul di sini." : "Coba kata kunci lain.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !displayEntries.isEmpty else { return }

        guard let selectedID,
              let currentIndex = displayEntries.firstIndex(where: { $0.id == selectedID }) else {
            self.selectedID = displayEntries.first?.id
            return
        }

        switch direction {
        case .up:
            let nextIndex = max(0, currentIndex - 1)
            self.selectedID = displayEntries[nextIndex].id
        case .down:
            let nextIndex = min(displayEntries.count - 1, currentIndex + 1)
            self.selectedID = displayEntries[nextIndex].id
        default:
            break
        }
    }

    private func ensureSelection() {
        if let selectedID,
           displayEntries.contains(where: { $0.id == selectedID }) {
            return
        }
        self.selectedID = displayEntries.first?.id
    }

    private func copySelectedEntryAndDismiss() {
        guard let entry = selectedEntry else { return }
        copyEntryAndDismiss(entry)
    }

    private func copyEntryAndDismiss(_ entry: ClipboardEntry) {
        copyEntry(entry)
        showCopiedIndicator(for: entry.id)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            lifecycle.dismissHistoryWindowAfterCopy()
        }
    }

    private func showCopiedIndicator(for id: UUID) {
        copiedEntryID = id
        clearCopiedIndicatorTask?.cancel()

        let clearTask = DispatchWorkItem {
            copiedEntryID = nil
        }
        clearCopiedIndicatorTask = clearTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: clearTask)
    }

    private func copyEntry(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch entry.contentType {
        case .file:
            let urls = entry.value
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) }

            if !urls.isEmpty {
                pasteboard.writeObjects(urls as [NSURL])
                return
            }

            pasteboard.setString(entry.value, forType: .string)

        case .image:
            if let data = entry.binaryData,
               let image = NSImage(data: data) {
                if pasteboard.writeObjects([image]) {
                    return
                }
                pasteboard.setData(data, forType: .png)
                return
            }
            pasteboard.setString(entry.preview, forType: .string)

        case .richText:
            if let rtfData = entry.binaryData {
                pasteboard.declareTypes([.rtf, .string], owner: nil)
                pasteboard.setData(rtfData, forType: .rtf)
                pasteboard.setString(entry.value, forType: .string)
                return
            }
            pasteboard.setString(entry.value, forType: .string)

        default:
            pasteboard.setString(entry.value, forType: .string)
        }
    }
}

private struct TranslucentBackgroundView: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.material = material
        view.blendingMode = .withinWindow
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.state = .active
        nsView.blendingMode = .withinWindow
    }
}

private struct SpotlightClipboardRow: View {
    let entry: ClipboardEntry
    let isSelected: Bool
    let isCopied: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            leadingVisual

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.preview)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(.white)

                Text(entry.contentType.displayName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                Text(entry.capturedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))

                Button {
                    onCopy()
                } label: {
                    Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(isCopied ? Color.green.opacity(0.70) : Color.white.opacity(0.20))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.32), lineWidth: 1)
                )
                .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.28) : Color.white.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.52) : Color.white.opacity(0.24), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .highPriorityGesture(
            TapGesture(count: 2)
                .onEnded {
                    onSelect()
                    onCopy()
                }
        )
        .onTapGesture {
            onSelect()
        }
    }

    @ViewBuilder
    private var leadingVisual: some View {
        if entry.contentType == .image,
           let thumbnailImage {
            Image(nsImage: thumbnailImage)
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
        } else {
            Image(systemName: entry.contentType.systemImageName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.20))
                )
        }
    }

    private var thumbnailImage: NSImage? {
        guard let data = entry.binaryData else { return nil }
        return NSImage(data: data)
    }
}
