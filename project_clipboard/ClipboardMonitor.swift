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

struct ClipboardPayload {
    let type: ClipboardContentType
    let value: String
    let preview: String
    let capturedAt: Date
    let binaryData: Data?
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
                    capturedAt: captureDate,
                    binaryData: nil
                )
            }

            let rawURL = urls.map(\.absoluteString).joined(separator: "\n")
            return ClipboardPayload(
                type: .url,
                value: rawURL,
                preview: truncate(urls.first?.absoluteString ?? rawURL),
                capturedAt: captureDate,
                binaryData: nil
            )
        }

        if let text = pasteboard.string(forType: .string) {
            if let rtfData = pasteboard.data(forType: .rtf),
               !rtfData.isEmpty,
               let attributed = try? NSAttributedString(
                   data: rtfData,
                   options: [.documentType: NSAttributedString.DocumentType.rtf],
                   documentAttributes: nil
               ) {
                let plain = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !plain.isEmpty else { return nil }
                return ClipboardPayload(
                    type: .richText,
                    value: attributed.string,
                    preview: truncate(plain),
                    capturedAt: captureDate,
                    binaryData: rtfData
                )
            }

            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            let type: ClipboardContentType = isLikelyURL(cleaned) ? .url : .text
            return ClipboardPayload(
                type: type,
                value: text,
                preview: truncate(cleaned),
                capturedAt: captureDate,
                binaryData: nil
            )
        }

        if let imageData = readImageData() {
            let size = ByteCountFormatter.string(
                fromByteCount: Int64(imageData.count),
                countStyle: .file
            )
            let imageHash = SHA256.hash(data: imageData)
                .map { String(format: "%02x", $0) }
                .joined()
            return ClipboardPayload(
                type: .image,
                value: imageHash,
                preview: "Image (\(size))",
                capturedAt: captureDate,
                binaryData: imageData
            )
        }

        return nil
    }

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
