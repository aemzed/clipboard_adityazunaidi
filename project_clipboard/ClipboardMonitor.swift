//
//  ClipboardMonitor.swift
//  project_clipboard
//
//  Created by Codex on 14/04/26.
//

import AppKit
import Combine
import Foundation

struct ClipboardPayload {
    let type: ClipboardContentType
    let value: String
    let preview: String
    let capturedAt: Date
}

final class ClipboardMonitor: ObservableObject {
    @Published var isMonitoring: Bool = false

    var onCapture: ((ClipboardPayload) -> Void)?

    private let pasteboard: NSPasteboard
    private let interval: TimeInterval
    private let previewLimit: Int

    private var timer: Timer?
    private var lastChangeCount: Int

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

    func start() {
        guard timer == nil else { return }

        isMonitoring = true
        lastChangeCount = pasteboard.changeCount

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollClipboard()
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
    }

    func setMonitoring(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    private func pollClipboard() {
        guard isMonitoring else { return }
        guard pasteboard.changeCount != lastChangeCount else { return }

        lastChangeCount = pasteboard.changeCount
        guard let payload = makePayload() else { return }
        onCapture?(payload)
    }

    private func makePayload() -> ClipboardPayload? {
        let captureDate = Date()

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
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
                    capturedAt: captureDate
                )
            }

            let rawURL = urls.map(\.absoluteString).joined(separator: "\n")
            return ClipboardPayload(
                type: .url,
                value: rawURL,
                preview: truncate(urls.first?.absoluteString ?? rawURL),
                capturedAt: captureDate
            )
        }

        if let text = pasteboard.string(forType: .string) {
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            let type: ClipboardContentType = isLikelyURL(cleaned) ? .url : .text
            return ClipboardPayload(
                type: type,
                value: text,
                preview: truncate(cleaned),
                capturedAt: captureDate
            )
        }

        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            let size = ByteCountFormatter.string(
                fromByteCount: Int64(imageData.count),
                countStyle: .file
            )
            return ClipboardPayload(
                type: .image,
                value: "Image data (\(size))",
                preview: "Image (\(size))",
                capturedAt: captureDate
            )
        }

        return nil
    }

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
