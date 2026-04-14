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
        let window = getOrCreateWindow()

        if shouldHide(window) {
            window.orderOut(nil)
            return
        }

        show(window)
    }

    func show() {
        let window = getOrCreateWindow()
        show(window)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func show(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func shouldHide(_ window: NSWindow) -> Bool {
        window.isVisible
            && window.isOnActiveSpace
            && window.isKeyWindow
            && NSApp.isActive
    }

    private func getOrCreateWindow() -> NSWindow {
        if let window {
            return window
        }

        let content = ContentView(store: store, monitor: monitor)
        let hostingController = NSHostingController(rootView: content)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Clipboard History"
        window.setContentSize(preferredWindowSize())
        window.minSize = NSSize(width: 860, height: 520)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.moveToActiveSpace]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        self.window = window
        return window
    }

    private func preferredWindowSize() -> NSSize {
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            return NSSize(width: 1120, height: 680)
        }

        let preferredWidth = min(max(980, visibleFrame.width * 0.58), visibleFrame.width * 0.9)
        let preferredHeight = min(max(560, visibleFrame.height * 0.62), visibleFrame.height * 0.9)

        return NSSize(
            width: preferredWidth.rounded(.toNearestOrAwayFromZero),
            height: preferredHeight.rounded(.toNearestOrAwayFromZero)
        )
    }
}
