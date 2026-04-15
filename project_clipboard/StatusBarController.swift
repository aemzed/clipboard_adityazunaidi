//
//  StatusBarController.swift
//  project_clipboard
//
//  Created by Codex on 14/04/26.
//

import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let onPrimaryClick: () -> Void
    private let onOpenHistory: () -> Void
    private let onCaptureScreenshot: () -> Void
    private let onClearUnpinned: () -> Void
    private let onClearAll: () -> Void
    private let onEditShortcut: () -> Void
    private let onToggleMonitoring: () -> Void
    private let isMonitoringEnabled: () -> Bool
    private let currentShortcutDisplay: () -> String

    private let statusItem: NSStatusItem

    private lazy var menu: NSMenu = {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(openItem)
        menu.addItem(screenshotItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(currentShortcutItem)
        menu.addItem(editShortcutItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(clearUnpinnedItem)
        menu.addItem(clearAllItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(toggleMonitorItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)
        return menu
    }()

    private lazy var openItem: NSMenuItem = {
        let item = NSMenuItem(
            title: "Open Clipboard History",
            action: #selector(openHistoryFromMenu),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }()

    private lazy var screenshotItem: NSMenuItem = {
        let item = NSMenuItem(
            title: "Screenshot to Clipboard",
            action: #selector(captureScreenshotFromMenu),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }()

    private lazy var toggleMonitorItem: NSMenuItem = {
        let item = NSMenuItem(
            title: "Pause Monitoring",
            action: #selector(toggleMonitoringFromMenu),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }()

    private lazy var clearUnpinnedItem: NSMenuItem = {
        let item = NSMenuItem(
            title: "Clear Unpinned",
            action: #selector(clearUnpinnedFromMenu),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }()

    private lazy var clearAllItem: NSMenuItem = {
        let item = NSMenuItem(
            title: "Clear All",
            action: #selector(clearAllFromMenu),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }()

    private lazy var currentShortcutItem: NSMenuItem = {
        let item = NSMenuItem(
            title: "Shortcut: \(currentShortcutDisplay())",
            action: nil,
            keyEquivalent: ""
        )
        item.isEnabled = false
        return item
    }()

    private lazy var editShortcutItem: NSMenuItem = {
        let item = NSMenuItem(
            title: "Edit Shortcut...",
            action: #selector(editShortcutFromMenu),
            keyEquivalent: ","
        )
        item.target = self
        return item
    }()

    private lazy var quitItem: NSMenuItem = {
        let item = NSMenuItem(
            title: "Quit",
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        )
        item.target = self
        return item
    }()

    init(
        onPrimaryClick: @escaping () -> Void,
        onOpenHistory: @escaping () -> Void,
        onCaptureScreenshot: @escaping () -> Void,
        onClearUnpinned: @escaping () -> Void,
        onClearAll: @escaping () -> Void,
        onEditShortcut: @escaping () -> Void,
        onToggleMonitoring: @escaping () -> Void,
        isMonitoringEnabled: @escaping () -> Bool,
        currentShortcutDisplay: @escaping () -> String
    ) {
        self.onPrimaryClick = onPrimaryClick
        self.onOpenHistory = onOpenHistory
        self.onCaptureScreenshot = onCaptureScreenshot
        self.onClearUnpinned = onClearUnpinned
        self.onClearAll = onClearAll
        self.onEditShortcut = onEditShortcut
        self.onToggleMonitoring = onToggleMonitoring
        self.isMonitoringEnabled = isMonitoringEnabled
        self.currentShortcutDisplay = currentShortcutDisplay
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = NSImage(
            systemSymbolName: "clipboard",
            accessibilityDescription: "Clipboard History"
        )
        button.image?.isTemplate = true
        button.action = #selector(statusItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            onPrimaryClick()
            return
        }

        switch event.type {
        case .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            showContextMenu()
        default:
            onPrimaryClick()
        }
    }

    private func showContextMenu() {
        toggleMonitorItem.title = isMonitoringEnabled() ? "Pause Monitoring" : "Resume Monitoring"
        currentShortcutItem.title = "Shortcut: \(currentShortcutDisplay())"
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openHistoryFromMenu() {
        onOpenHistory()
    }

    @objc private func captureScreenshotFromMenu() {
        onCaptureScreenshot()
    }

    @objc private func toggleMonitoringFromMenu() {
        onToggleMonitoring()
    }

    @objc private func clearUnpinnedFromMenu() {
        onClearUnpinned()
    }

    @objc private func clearAllFromMenu() {
        onClearAll()
    }

    @objc private func editShortcutFromMenu() {
        onEditShortcut()
    }

    @objc private func quitFromMenu() {
        NSApplication.shared.terminate(nil)
    }
}
