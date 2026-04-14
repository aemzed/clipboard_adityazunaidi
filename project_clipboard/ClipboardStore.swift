//
//  ClipboardStore.swift
//  project_clipboard
//
//  Created by Codex on 14/04/26.
//

import Combine
import Foundation

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []

    private let historyLimit: Int
    private let storageURL: URL

    init(historyLimit: Int = 20) {
        self.historyLimit = historyLimit
        self.storageURL = Self.makeStorageURL()
        load()
    }

    func add(payload: ClipboardPayload) {
        if let first = entries.first,
           first.contentType == payload.type,
           first.value == payload.value {
            return
        }

        if let existingIndex = entries.firstIndex(where: {
            $0.contentType == payload.type && $0.value == payload.value
        }) {
            var existing = entries.remove(at: existingIndex)
            existing.capturedAt = payload.capturedAt
            existing.preview = payload.preview
            entries.insert(existing, at: 0)
            entries.sort(by: sortRule)
            persist()
            return
        }

        let entry = ClipboardEntry(
            capturedAt: payload.capturedAt,
            contentType: payload.type,
            preview: payload.preview,
            value: payload.value
        )
        entries.insert(entry, at: 0)
        trimHistoryIfNeeded()
        persist()
    }

    func togglePin(for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isPinned.toggle()
        entries.sort(by: sortRule)
        persist()
    }

    func delete(id: UUID) {
        entries.removeAll(where: { $0.id == id })
        persist()
    }

    func delete(ids: [UUID]) {
        let idSet = Set(ids)
        entries.removeAll(where: { idSet.contains($0.id) })
        persist()
    }

    func clearUnpinned() {
        entries.removeAll(where: { !$0.isPinned })
        persist()
    }

    func clearAll() {
        entries.removeAll()
        persist()
    }

    func entry(for id: UUID?) -> ClipboardEntry? {
        guard let id else { return nil }
        return entries.first(where: { $0.id == id })
    }

    private func trimHistoryIfNeeded() {
        entries.sort(by: sortRule)
        guard entries.count > historyLimit else { return }

        while entries.count > historyLimit {
            guard let oldestIndex = entries.indices.min(by: { lhs, rhs in
                entries[lhs].capturedAt < entries[rhs].capturedAt
            }) else {
                break
            }
            entries.remove(at: oldestIndex)
        }
    }

    private func sortRule(_ lhs: ClipboardEntry, _ rhs: ClipboardEntry) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }
        return lhs.capturedAt > rhs.capturedAt
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else {
            entries = []
            return
        }

        guard let decoded = try? JSONDecoder().decode([ClipboardEntry].self, from: data) else {
            entries = []
            return
        }

        entries = decoded.sorted(by: sortRule)
        trimHistoryIfNeeded()
        persist()
    }

    private func persist() {
        do {
            let directory = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Keep app usable even if disk write fails.
            NSLog("Failed to persist clipboard history: \(error)")
        }
    }

    private static func makeStorageURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return base
            .appendingPathComponent("project_clipboard", isDirectory: true)
            .appendingPathComponent("clipboard_history.json", isDirectory: false)
    }
}
