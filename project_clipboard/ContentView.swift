//
//  ContentView.swift
//  project_clipboard
//
//  Created by Adit's Macbook    on 14/04/26.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var monitor: ClipboardMonitor
    @ObservedObject private var lifecycle = AppLifecycle.shared

    @State private var searchText: String = ""
    @State private var selectedID: UUID?
    @State private var isShowingShortcutSettings = false

    private var filteredEntries: [ClipboardEntry] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return store.entries
        }

        return store.entries.filter {
            $0.preview.localizedCaseInsensitiveContains(searchText)
                || $0.value.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedEntry: ClipboardEntry? {
        store.entry(for: selectedID)
    }

    var body: some View {
        ZStack {
            TranslucentBackgroundView(material: .underWindowBackground)
                .ignoresSafeArea()

            GeometryReader { proxy in
                NavigationSplitView {
                    List(selection: $selectedID) {
                        if filteredEntries.isEmpty {
                            ContentUnavailableView {
                                Label {
                                    Text(searchText.isEmpty ? "Clipboard kosong" : "Tidak ada hasil")
                                        .font(.title3.weight(.semibold))
                                } icon: {
                                    Image(systemName: "doc.text.magnifyingglass")
                                }
                            } description: {
                                Text(searchText.isEmpty ? "Copy sesuatu dulu, nanti akan muncul di sini." : "Coba kata kunci lain.")
                                    .font(.body)
                            }
                        } else {
                            ForEach(filteredEntries) { entry in
                                ClipboardRow(entry: entry)
                                    .tag(entry.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if selectedID == entry.id {
                                            copyEntry(entry)
                                        } else {
                                            selectedID = entry.id
                                        }
                                    }
                                    .contextMenu {
                                        Button("Copy Ulang", systemImage: "doc.on.doc") {
                                            copyEntry(entry)
                                        }

                                        Button(entry.isPinned ? "Lepas Pin" : "Pin", systemImage: entry.isPinned ? "pin.slash" : "pin") {
                                            store.togglePin(for: entry.id)
                                        }

                                        Divider()

                                        Button("Hapus", systemImage: "trash", role: .destructive) {
                                            deleteEntry(entry)
                                        }
                                    }
                            }
                            .onDelete(perform: deleteItems)
                        }
                    }
                    .navigationSplitViewColumnWidth(
                        min: sidebarMinWidth(for: proxy.size.width),
                        ideal: sidebarIdealWidth(for: proxy.size.width)
                    )
                    .searchable(text: $searchText, placement: .sidebar, prompt: "Cari history")
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .toolbar {
                        ToolbarItemGroup(placement: .automatic) {
                            Button {
                                monitor.setMonitoring(!monitor.isMonitoring)
                            } label: {
                                Label(
                                    monitor.isMonitoring ? "Pause Monitor" : "Resume Monitor",
                                    systemImage: monitor.isMonitoring ? "pause.circle" : "play.circle"
                                )
                            }

                            Button(role: .destructive, action: clearUnpinned) {
                                Label("Clear Unpinned", systemImage: "trash")
                            }
                            .disabled(store.entries.isEmpty)

                            Button(role: .destructive, action: clearAll) {
                                Label("Clear All", systemImage: "trash.fill")
                            }
                            .disabled(store.entries.isEmpty)

                            Button("Shortcut", systemImage: "keyboard") {
                                isShowingShortcutSettings = true
                            }

                            Button("Screenshot", systemImage: "camera.viewfinder") {
                                lifecycle.captureScreenshotToClipboard()
                            }

                            Button("Open Window", systemImage: "rectangle.inset.filled.and.person.filled") {
                                NSApp.sendAction(#selector(AppDelegate.openHistoryWindow), to: nil, from: nil)
                            }

                            Button("Quit", systemImage: "power") {
                                NSApplication.shared.terminate(nil)
                            }
                        }
                    }
                } detail: {
                    ClipboardDetailView(
                        entry: selectedEntry,
                        onCopy: copyEntry,
                        onDelete: deleteEntry,
                        onTogglePin: { store.togglePin(for: $0.id) }
                    )
                }
                .background(Color.clear)
            }
        }
        .background(Color.clear)
        .onChange(of: selectedID) { _, newValue in
            guard let entry = store.entry(for: newValue) else { return }
            copyEntry(entry)
        }
        .sheet(isPresented: $isShowingShortcutSettings) {
            ShortcutSettingsSheet(
                isPresented: $isShowingShortcutSettings,
                lifecycle: lifecycle
            )
        }
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
        default:
            pasteboard.setString(entry.value, forType: .string)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        let targetIDs = offsets.map { filteredEntries[$0].id }
        store.delete(ids: targetIDs)

        if let selectedID,
            store.entry(for: selectedID) == nil
        {
            self.selectedID = nil
        }
    }

    private func deleteEntry(_ entry: ClipboardEntry) {
        store.delete(id: entry.id)
        if selectedID == entry.id {
            selectedID = nil
        }
    }

    private func clearUnpinned() {
        let selectedWasPinned = selectedEntry?.isPinned ?? false
        store.clearUnpinned()

        if !selectedWasPinned {
            selectedID = nil
        }
    }

    private func clearAll() {
        store.clearAll()
        selectedID = nil
    }

    private func sidebarMinWidth(for totalWidth: CGFloat) -> CGFloat {
        min(max(340, totalWidth * 0.28), 520)
    }

    private func sidebarIdealWidth(for totalWidth: CGFloat) -> CGFloat {
        let minWidth = sidebarMinWidth(for: totalWidth)
        return min(max(minWidth + 56, totalWidth * 0.34), 680)
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

private struct ShortcutSettingsSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var lifecycle: AppLifecycle

    @State private var selectedKeyCode: UInt32
    @State private var useCommand: Bool
    @State private var useOption: Bool
    @State private var useControl: Bool
    @State private var useShift: Bool
    @State private var localMessage: String = ""

    init(isPresented: Binding<Bool>, lifecycle: AppLifecycle) {
        self._isPresented = isPresented
        self.lifecycle = lifecycle

        let shortcut = lifecycle.preferredShortcut
        _selectedKeyCode = State(initialValue: shortcut.keyCode)
        _useCommand = State(initialValue: (shortcut.modifiers & UInt32(cmdKey)) != 0)
        _useOption = State(initialValue: (shortcut.modifiers & UInt32(optionKey)) != 0)
        _useControl = State(initialValue: (shortcut.modifiers & UInt32(controlKey)) != 0)
        _useShift = State(initialValue: (shortcut.modifiers & UInt32(shiftKey)) != 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Aktif Saat Ini") {
                    HStack {
                        Image(systemName: "keyboard")
                            .foregroundStyle(.secondary)
                        Text(lifecycle.activeShortcutDisplay)
                            .font(.headline)
                    }
                }

                Section("Key") {
                    Picker("Key", selection: $selectedKeyCode) {
                        ForEach(ShortcutCatalog.keyOptions) { option in
                            Text(option.label).tag(option.keyCode)
                        }
                    }
                    .labelsHidden()
                }

                Section("Modifier Keys") {
                    Toggle("Command (⌘)", isOn: $useCommand)
                    Toggle("Shift (⇧)", isOn: $useShift)
                    Toggle("Option (⌥)", isOn: $useOption)
                    Toggle("Control (⌃)", isOn: $useControl)
                }

                if !localMessage.isEmpty || !lifecycle.shortcutStatusMessage.isEmpty {
                    Section {
                        Text(localMessage.isEmpty ? lifecycle.shortcutStatusMessage : localMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Shortcut Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") {
                        saveShortcut()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 420, height: 420)
    }

    private func saveShortcut() {
        let modifiers = composeModifiers()
        guard modifiers != 0 else {
            localMessage = "Pilih minimal satu modifier (Command/Option/Control/Shift)."
            return
        }

        let shortcut = HotKeyShortcut(
            keyCode: selectedKeyCode,
            modifiers: modifiers
        )

        let exact = lifecycle.updatePreferredShortcut(shortcut)
        localMessage = lifecycle.shortcutStatusMessage

        if exact {
            isPresented = false
        }
    }

    private func composeModifiers() -> UInt32 {
        var modifiers: UInt32 = 0
        if useCommand { modifiers |= UInt32(cmdKey) }
        if useOption { modifiers |= UInt32(optionKey) }
        if useControl { modifiers |= UInt32(controlKey) }
        if useShift { modifiers |= UInt32(shiftKey) }
        return modifiers
    }
}

private struct ClipboardRow: View {
    let entry: ClipboardEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.contentType.systemImageName)
                .foregroundStyle(entry.isPinned ? .orange : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.contentType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if entry.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                Text(entry.preview)
                    .lineLimit(2)
                    .truncationMode(.tail)

                Text(entry.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ClipboardDetailView: View {
    let entry: ClipboardEntry?
    let onCopy: (ClipboardEntry) -> Void
    let onDelete: (ClipboardEntry) -> Void
    let onTogglePin: (ClipboardEntry) -> Void

    var body: some View {
        Group {
            if let entry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            Image(systemName: entry.contentType.systemImageName)
                            Text(entry.contentType.displayName)
                                .font(.headline)
                        }

                        Text(entry.capturedAt.formatted(date: .long, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if entry.contentType == .image {
                            imageContent(for: entry)
                        } else {
                            Text(entry.value)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        HStack(spacing: 12) {
                            Button("Copy Ulang", systemImage: "doc.on.doc") {
                                onCopy(entry)
                            }

                            Button(entry.isPinned ? "Lepas Pin" : "Pin", systemImage: entry.isPinned ? "pin.slash" : "pin") {
                                onTogglePin(entry)
                            }

                            Button("Hapus", systemImage: "trash", role: .destructive) {
                                onDelete(entry)
                            }
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Pilih item history",
                    systemImage: "list.clipboard",
                    description: Text("Detail clipboard akan tampil di sini.")
                )
            }
        }
    }

    @ViewBuilder
    private func imageContent(for entry: ClipboardEntry) -> some View {
        if let data = entry.binaryData,
           let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text("Ukuran image: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Data image lama tidak tersedia. Copy image baru untuk menyimpan data image ke history.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
