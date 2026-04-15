//
//  HistoryWindowController.swift
//  project_clipboard
//
//  Created by Codex on 14/04/26.
//

import AppKit
import SwiftUI

private final class SpotlightPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    private let store: ClipboardStore
    private let monitor: ClipboardMonitor
    private var window: NSWindow?
    private var pendingDismissWorkItem: DispatchWorkItem?

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

    func dismissAfterCopy() {
        guard window != nil else { return }

        pendingDismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performDismissAfterCopy()
        }
        pendingDismissWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func show(_ window: NSWindow) {
        pendingDismissWorkItem?.cancel()
        pendingDismissWorkItem = nil
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
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

        let size = preferredWindowSize()
        let window = SpotlightPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = "Papan Klip"
        window.setContentSize(size)
        window.minSize = size
        window.maxSize = size
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isFloatingPanel = true
        window.level = .floating
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.center()
        window.delegate = self
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        self.window = window
        return window
    }

    private func preferredWindowSize() -> NSSize {
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            return NSSize(width: 880, height: 560)
        }

        let preferredWidth = min(max(820, visibleFrame.width * 0.50), 980)
        let preferredHeight = min(max(520, visibleFrame.height * 0.56), 640)

        return NSSize(
            width: preferredWidth.rounded(.toNearestOrAwayFromZero),
            height: preferredHeight.rounded(.toNearestOrAwayFromZero)
        )
    }

    private func performDismissAfterCopy() {
        pendingDismissWorkItem = nil
        guard let window else { return }

        if window.styleMask.contains(.miniaturizable) {
            window.miniaturize(nil)
            if window.isMiniaturized {
                return
            }
        }

        window.orderOut(nil)
    }
}
