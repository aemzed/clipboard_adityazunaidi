//
//  HistoryWindowController.swift
//  project_clipboard
//
//  Created by Codex on 14/04/26.
//

import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    private let store: ClipboardStore
    private let monitor: ClipboardMonitor
    private var window: NSWindow?

    init(store: ClipboardStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
    }

    func toggle() {
        if let window, window.isVisible {
            window.orderOut(nil)
            return
        }
        show()
    }

    func show() {
        let window = getOrCreateWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func getOrCreateWindow() -> NSWindow {
        if let window {
            return window
        }

        let content = ContentView(store: store, monitor: monitor)
        let hostingController = NSHostingController(rootView: content)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Clipboard History"
        window.setContentSize(NSSize(width: 920, height: 560))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        self.window = window
        return window
    }
}
