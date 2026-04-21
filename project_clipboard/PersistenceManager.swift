//
//  PersistenceManager.swift
//  project_clipboard
//
//  Decoupled persistence layer following Single Responsibility Principle.
//

import Foundation

// MARK: - Protocol

/// Defines the contract for clipboard history persistence.
///
/// Conforming types handle loading and saving ``ClipboardEntry`` arrays
/// to a durable storage backend (disk, database, etc.).
protocol ClipboardPersistence: Sendable {
    /// Loads previously persisted clipboard entries.
    /// - Returns: An array of ``ClipboardEntry`` sorted by the implementation's default order,
    ///   or an empty array if no persisted data exists.
    func load() -> [ClipboardEntry]

    /// Persists the given entries with debouncing to avoid redundant I/O.
    ///
    /// Rapid successive calls cancel any pending write and restart the delay.
    /// - Parameter entries: The current snapshot of clipboard entries to persist.
    func save(_ entries: [ClipboardEntry])

    /// Immediately writes any pending changes to disk.
    ///
    /// Call this before the application terminates to prevent data loss
    /// from in-flight debounced writes.
    func flush(_ entries: [ClipboardEntry])
}

// MARK: - Implementation

/// Disk-backed persistence manager with debounced writes.
///
/// Uses a dedicated serial queue at `.utility` QoS to keep I/O off the main thread.
/// Writes are debounced by ``debounceInterval`` seconds — rapid mutations
/// coalesce into a single disk write.
final class DiskPersistenceManager: ClipboardPersistence, @unchecked Sendable {

    // MARK: - Properties

    private let storageURL: URL
    private let debounceInterval: TimeInterval
    private let queue = DispatchQueue(label: "com.app.clipboard.persist", qos: .utility)
    private var pendingWorkItem: DispatchWorkItem?

    // MARK: - Initialization

    /// Creates a new disk persistence manager.
    /// - Parameters:
    ///   - storageURL: The file URL where JSON data is written. Defaults to the app's
    ///     Application Support directory.
    ///   - debounceInterval: Seconds to wait before committing a write. Defaults to `2.0`.
    init(storageURL: URL? = nil, debounceInterval: TimeInterval = 2.0) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        self.debounceInterval = debounceInterval
    }

    // MARK: - ClipboardPersistence

    func load() -> [ClipboardEntry] {
        guard let data = try? Data(contentsOf: storageURL) else {
            return []
        }
        return (try? JSONDecoder().decode([ClipboardEntry].self, from: data)) ?? []
    }

    func save(_ entries: [ClipboardEntry]) {
        pendingWorkItem?.cancel()

        let workItem = DispatchWorkItem { [storageURL] in
            Self.writeEntries(entries, to: storageURL)
        }
        pendingWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    func flush(_ entries: [ClipboardEntry]) {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        queue.sync { [storageURL] in
            Self.writeEntries(entries, to: storageURL)
        }
    }

    // MARK: - Private Helpers

    private static func writeEntries(_ entries: [ClipboardEntry], to url: URL) {
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Failed to persist clipboard history: \(error)")
        }
    }

    private static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return base
            .appendingPathComponent("project_clipboard", isDirectory: true)
            .appendingPathComponent("clipboard_history.json", isDirectory: false)
    }
}
