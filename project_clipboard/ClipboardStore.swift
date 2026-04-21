//
//  ClipboardStore.swift
//  project_clipboard
//
//  Created by Codex on 14/04/26.
//

import Combine
import Foundation

// MARK: - ClipboardStore

/// Manages the in-memory clipboard history and coordinates with a ``ClipboardPersistence`` backend.
///
/// All published state mutations happen on the `@MainActor`.
/// Disk I/O is delegated to the injected persistence service, which handles
/// debouncing and background writes internally.
@MainActor
final class ClipboardStore: ObservableObject {

    // MARK: - Published State

    @Published private(set) var entries: [ClipboardEntry] = []

    // MARK: - Private Properties

    private let historyLimit: Int
    private let persistence: ClipboardPersistence

    // MARK: - Initialization

    /// Creates a clipboard store backed by the given persistence service.
    /// - Parameters:
    ///   - historyLimit: Maximum number of entries to retain. Defaults to `20`.
    ///   - persistence: The storage backend. Pass `nil` to use the default ``DiskPersistenceManager``.
    init(historyLimit: Int = 20, persistence: ClipboardPersistence? = nil) {
        self.historyLimit = historyLimit
        self.persistence = persistence ?? DiskPersistenceManager()
        load()
    }

    // MARK: - Public Methods

    /// Adds a clipboard payload as a new entry, or re-promotes an existing duplicate.
    ///
    /// Duplicate detection is based on content type and value.
    /// If the same content already exists, it is moved to the top with an updated timestamp.
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
            existing.binaryData = payload.binaryData
            entries.insert(existing, at: 0)
            entries.sort(by: sortRule)
            persist()
            return
        }

        let entry = ClipboardEntry(
            capturedAt: payload.capturedAt,
            contentType: payload.type,
            preview: payload.preview,
            value: payload.value,
            binaryData: payload.binaryData
        )
        entries.insert(entry, at: 0)
        trimHistoryIfNeeded()
        persist()
    }

    /// Toggles the pinned state for the entry with the given ID.
    func togglePin(for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isPinned.toggle()
        entries.sort(by: sortRule)
        persist()
    }

    /// Deletes a single entry by ID.
    func delete(id: UUID) {
        entries.removeAll(where: { $0.id == id })
        persist()
    }

    /// Deletes multiple entries by their IDs.
    func delete(ids: [UUID]) {
        let idSet = Set(ids)
        entries.removeAll(where: { idSet.contains($0.id) })
        persist()
    }

    /// Removes all unpinned entries.
    func clearUnpinned() {
        entries.removeAll(where: { !$0.isPinned })
        persist()
    }

    /// Removes all entries, including pinned ones.
    func clearAll() {
        entries.removeAll()
        persist()
    }

    /// Returns the entry matching the given ID, if it exists.
    func entry(for id: UUID?) -> ClipboardEntry? {
        guard let id else { return nil }
        return entries.first(where: { $0.id == id })
    }

    /// Immediately flushes any pending persistence to disk.
    ///
    /// Call before the application terminates to prevent data loss.
    func flushPersistence() {
        persistence.flush(entries)
    }

    // MARK: - Private Helpers

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
        let loaded = persistence.load()
        entries = loaded.sorted(by: sortRule)
        trimHistoryIfNeeded()
        persist()
    }

    private func persist() {
        persistence.save(entries)
    }
}
