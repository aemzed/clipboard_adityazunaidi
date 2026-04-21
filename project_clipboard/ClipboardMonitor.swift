//
//  ClipboardMonitor.swift
//  project_clipboard
//
//  Created by Codex on 14/04/26.
//

import AppKit
import Combine
import CryptoKit
import Foundation

// MARK: - ClipboardPayload

/// A value type representing a single clipboard capture before it becomes a persisted entry.
struct ClipboardPayload {
    let type: ClipboardContentType
    let value: String
    let preview: String
    let capturedAt: Date
    let binaryData: Data?
}

// MARK: - ClipboardMonitor

/// Polls the system pasteboard on a background serial queue and emits ``ClipboardPayload`` values
/// through the ``onCapture`` callback whenever new content is detected.
///
/// Heavy operations — image conversion, SHA-256 hashing, RTF parsing — run entirely
/// off the main thread. Only the ``onCapture`` callback and ``isMonitoring`` updates
/// are dispatched to the main thread.
final class ClipboardMonitor: ObservableObject {

    // MARK: - Published State

    @Published var isMonitoring: Bool = false

    // MARK: - Callback

    /// Called on the main thread whenever a new clipboard payload is captured.
    var onCapture: ((ClipboardPayload) -> Void)?

    // MARK: - Private Properties

    private let pasteboard: NSPasteboard
    private let interval: TimeInterval
    private let previewLimit: Int

    private let queue = DispatchQueue(label: "com.app.clipboard.monitor", qos: .utility)
    private var timerSource: DispatchSourceTimer?
    private var lastChangeCount: Int
    private var lastImageHash: String?

    // MARK: - Initialization

    /// Creates a clipboard monitor.
    /// - Parameters:
    ///   - pasteboard: The pasteboard to observe. Defaults to `.general`.
    ///   - interval: Polling interval in seconds. Defaults to `0.7`.
    ///   - previewLimit: Maximum character length for preview strings. Defaults to `180`.
    init(
        pasteboard: NSPasteboard = .general,
        interval: TimeInterval = 0.7,
        previewLimit: Int = 180
    ) {
        self.pasteboard = pasteboard
        self.interval = interval
        self.previewLimit = previewLimit
        self.lastChangeCount = pasteboard.changeCount
    }

    // MARK: - Public Methods

    /// Starts polling the pasteboard on a background queue.
    func start() {
        guard timerSource == nil else { return }

        isMonitoring = true
        lastChangeCount = pasteboard.changeCount

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(Int(interval * 200))
        )
        source.setEventHandler { [weak self] in
            self?.pollClipboard()
        }
        source.resume()
        timerSource = source
    }

    /// Stops polling and cancels the background timer.
    func stop() {
        timerSource?.cancel()
        timerSource = nil
        DispatchQueue.main.async { [weak self] in
            self?.isMonitoring = false
        }
    }

    /// Convenience toggle for monitoring state.
    func setMonitoring(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    // MARK: - Polling

    private func pollClipboard() {
        // NSPasteboard.changeCount must be read on the main thread.
        var currentChangeCount: Int = 0
        DispatchQueue.main.sync {
            currentChangeCount = self.pasteboard.changeCount
        }

        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        // Heavy work runs on this background queue.
        guard let payload = makePayload() else { return }

        // Deliver result on the main thread.
        DispatchQueue.main.async { [weak self] in
            self?.onCapture?(payload)
        }
    }

    // MARK: - Payload Construction

    /// Inspects the current pasteboard content and builds a typed payload.
    ///
    /// Priority order: files/URLs → rich text → plain text → image.
    private func makePayload() -> ClipboardPayload? {
        let captureDate = Date()

        return processURLsAndFiles(capturedAt: captureDate)
            ?? processText(capturedAt: captureDate)
            ?? processImage(capturedAt: captureDate)
    }

    // MARK: - Content Processors

    /// Attempts to read file URLs or web URLs from the pasteboard.
    private func processURLsAndFiles(capturedAt date: Date) -> ClipboardPayload? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty else {
            return nil
        }

        let fileURLs = urls.filter(\.isFileURL)

        if !fileURLs.isEmpty {
            let names = fileURLs.map(\.lastPathComponent)
            let preview: String
            if fileURLs.count == 1 {
                preview = names[0]
            } else {
                preview = "\(fileURLs.count) files: \(names.joined(separator: ", "))"
            }

            return ClipboardPayload(
                type: .file,
                value: fileURLs.map(\.path).joined(separator: "\n"),
                preview: truncate(preview),
                capturedAt: date,
                binaryData: nil
            )
        }

        let rawURL = urls.map(\.absoluteString).joined(separator: "\n")
        return ClipboardPayload(
            type: .url,
            value: rawURL,
            preview: truncate(urls.first?.absoluteString ?? rawURL),
            capturedAt: date,
            binaryData: nil
        )
    }

    /// Attempts to read plain or rich text from the pasteboard.
    private func processText(capturedAt date: Date) -> ClipboardPayload? {
        guard let text = pasteboard.string(forType: .string) else { return nil }

        // Prefer rich text when available.
        if let rtfPayload = processRichText(plainText: text, capturedAt: date) {
            return rtfPayload
        }

        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let type: ClipboardContentType = isLikelyURL(cleaned) ? .url : .text
        return ClipboardPayload(
            type: type,
            value: text,
            preview: truncate(cleaned),
            capturedAt: date,
            binaryData: nil
        )
    }

    /// Parses RTF data from the pasteboard and returns a rich-text payload.
    private func processRichText(plainText: String, capturedAt date: Date) -> ClipboardPayload? {
        guard let rtfData = pasteboard.data(forType: .rtf),
              !rtfData.isEmpty,
              let attributed = try? NSAttributedString(
                  data: rtfData,
                  options: [.documentType: NSAttributedString.DocumentType.rtf],
                  documentAttributes: nil
              ) else {
            return nil
        }

        let plain = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return nil }

        return ClipboardPayload(
            type: .richText,
            value: attributed.string,
            preview: truncate(plain),
            capturedAt: date,
            binaryData: rtfData
        )
    }

    /// Reads image data from the pasteboard, converts to PNG, and deduplicates via SHA-256.
    private func processImage(capturedAt date: Date) -> ClipboardPayload? {
        guard let imageData = readImageData() else { return nil }

        let imageHash = SHA256.hash(data: imageData)
            .map { String(format: "%02x", $0) }
            .joined()

        // Skip if the image hasn't actually changed since last capture.
        if imageHash == lastImageHash {
            return nil
        }
        lastImageHash = imageHash

        let size = ByteCountFormatter.string(
            fromByteCount: Int64(imageData.count),
            countStyle: .file
        )
        return ClipboardPayload(
            type: .image,
            value: imageHash,
            preview: "Image (\(size))",
            capturedAt: date,
            binaryData: imageData
        )
    }

    // MARK: - Image Reading

    /// Reads PNG image data from the pasteboard, converting from TIFF if necessary.
    private func readImageData() -> Data? {
        if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty {
            return pngData
        }

        if let tiffData = pasteboard.data(forType: .tiff),
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]),
           !pngData.isEmpty {
            return pngData
        }

        if let image = NSImage(pasteboard: pasteboard),
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]),
           !pngData.isEmpty {
            return pngData
        }

        return nil
    }

    // MARK: - Utilities

    private func truncate(_ value: String) -> String {
        guard value.count > previewLimit else { return value }
        let shortened = value.prefix(previewLimit)
        return "\(shortened)…"
    }

    private func isLikelyURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme,
              !scheme.isEmpty else {
            return false
        }
        return components.host != nil || scheme == "mailto"
    }
}
