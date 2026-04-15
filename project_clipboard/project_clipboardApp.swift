//
//  project_clipboardApp.swift
//  project_clipboard
//
//  Created by Adit's Macbook    on 14/04/26.
//

import AppKit
import Combine
import Carbon.HIToolbox
import SwiftUI

@main
struct project_clipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        AppLifecycle.shared.startServicesIfNeeded()
    }

    func application(_ application: NSApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ application: NSApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
        false
    }

    @objc func openHistoryWindow() {
        AppLifecycle.shared.toggleHistoryWindow()
    }

    @objc func captureScreenshotToClipboard() {
        AppLifecycle.shared.captureScreenshotToClipboard()
    }
}

@MainActor
final class AppLifecycle: ObservableObject {
    static let shared = AppLifecycle()

    let store: ClipboardStore
    let monitor: ClipboardMonitor

    @Published private(set) var activeShortcutDisplay: String = "Not Active"
    @Published private(set) var shortcutStatusMessage: String = ""
    @Published private(set) var preferredShortcut: HotKeyShortcut

    private let windowController: HistoryWindowController
    private let hotKeyManager: HotKeyManager
    private var statusBarController: StatusBarController?
    private let fallbackShortcuts: [HotKeyShortcut] = HotKeyShortcut.defaultFallbacks

    private var didStartServices = false

    private static let shortcutDefaultsKey = "project_clipboard.hotkey.preference.v1"

    init() {
        let preferredShortcut = Self.loadPreferredShortcut() ?? .defaultPrimary

        let store = ClipboardStore()
        let monitor = ClipboardMonitor()
        monitor.onCapture = { payload in
            store.add(payload: payload)
        }

        let windowController = HistoryWindowController(store: store, monitor: monitor)
        let hotKeyManager = HotKeyManager()
        hotKeyManager.onHotKeyPressed = { [weak windowController] in
            windowController?.toggle()
        }

        self.preferredShortcut = preferredShortcut
        self.store = store
        self.monitor = monitor
        self.windowController = windowController
        self.hotKeyManager = hotKeyManager
    }

    func startServicesIfNeeded() {
        guard !didStartServices else { return }
        didStartServices = true

        statusBarController = StatusBarController(
            onPrimaryClick: { [weak self] in
                self?.toggleHistoryWindow()
            },
            onOpenHistory: { [weak self] in
                self?.showHistoryWindow()
            },
            onCaptureScreenshot: { [weak self] in
                self?.captureScreenshotToClipboard()
            },
            onClearUnpinned: { [weak self] in
                self?.store.clearUnpinned()
            },
            onClearAll: { [weak self] in
                self?.confirmAndClearAllHistory()
            },
            onEditShortcut: { [weak self] in
                self?.presentShortcutEditor()
            },
            onToggleMonitoring: { [weak self] in
                guard let self else { return }
                self.monitor.setMonitoring(!self.monitor.isMonitoring)
            },
            isMonitoringEnabled: { [weak self] in
                self?.monitor.isMonitoring ?? false
            },
            currentShortcutDisplay: { [weak self] in
                self?.activeShortcutDisplay ?? "Not Active"
            }
        )

        monitor.start()

        let exact = activateShortcut(preferred: preferredShortcut)
        if exact {
            shortcutStatusMessage = "Shortcut aktif: \(activeShortcutDisplay)"
        } else if activeShortcutDisplay == "Not Active" {
            shortcutStatusMessage = "Gagal mendaftarkan shortcut global."
        } else {
            shortcutStatusMessage = "Shortcut bentrok, app pakai: \(activeShortcutDisplay)"
        }
    }

    @discardableResult
    func updatePreferredShortcut(_ shortcut: HotKeyShortcut) -> Bool {
        preferredShortcut = shortcut
        Self.savePreferredShortcut(shortcut)

        let exact = activateShortcut(preferred: shortcut)
        if exact {
            shortcutStatusMessage = "Shortcut disimpan: \(activeShortcutDisplay)"
        } else if activeShortcutDisplay == "Not Active" {
            shortcutStatusMessage = "Gagal mendaftarkan shortcut. Coba kombinasi lain."
        } else {
            shortcutStatusMessage = "Shortcut bentrok, app pakai: \(activeShortcutDisplay)"
        }
        return exact
    }

    func toggleHistoryWindow() {
        windowController.toggle()
    }

    func showHistoryWindow() {
        windowController.show()
    }

    func dismissHistoryWindowAfterCopy() {
        windowController.dismissAfterCopy()
    }

    func captureScreenshotToClipboard() {
        windowController.hide()

        // Let the window finish hiding before invoking interactive screenshot UI.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.runScreenshotCapture()
        }
    }

    func confirmAndClearAllHistory() {
        guard !store.entries.isEmpty else { return }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear all clipboard history?"
        alert.informativeText = "This will remove \(store.entries.count) items from local history."
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            store.clearAll()
        }
    }

    func presentShortcutEditor() {
        NSApp.activate(ignoringOtherApps: true)

        let editorView = ShortcutEditorAccessoryView(shortcut: preferredShortcut)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Edit Global Shortcut"
        alert.informativeText = "Set keyboard shortcut to open Clipboard History."
        alert.accessoryView = editorView
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let candidate = editorView.shortcutValue
        guard candidate.modifiers != 0 else {
            showInfoAlert(
                title: "Shortcut is invalid",
                message: "Pick at least one modifier key (Command, Shift, Option, or Control)."
            )
            return
        }

        let exact = updatePreferredShortcut(candidate)
        guard exact else {
            showInfoAlert(
                title: "Shortcut conflict",
                message: shortcutStatusMessage
            )
            return
        }
    }

    private func runScreenshotCapture() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-c", "-x"]

        do {
            try process.run()
        } catch {
            NSLog("Failed to launch screenshot tool: \(error)")
        }
    }

    private func activateShortcut(preferred: HotKeyShortcut) -> Bool {
        let candidates = [preferred] + fallbackShortcuts.filter { $0 != preferred }

        guard let active = hotKeyManager.registerFirstAvailable(candidates) else {
            activeShortcutDisplay = "Not Active"
            return false
        }

        activeShortcutDisplay = active.displayText
        return active == preferred
    }

    private static func loadPreferredShortcut() -> HotKeyShortcut? {
        guard let data = UserDefaults.standard.data(forKey: shortcutDefaultsKey) else {
            return nil
        }

        return try? JSONDecoder().decode(HotKeyShortcut.self, from: data)
    }

    private static func savePreferredShortcut(_ shortcut: HotKeyShortcut) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        UserDefaults.standard.set(data, forKey: shortcutDefaultsKey)
    }

    private func showInfoAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private final class ShortcutEditorAccessoryView: NSView {
    private let keyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let commandCheckbox = NSButton(checkboxWithTitle: "Command", target: nil, action: nil)
    private let shiftCheckbox = NSButton(checkboxWithTitle: "Shift", target: nil, action: nil)
    private let optionCheckbox = NSButton(checkboxWithTitle: "Option", target: nil, action: nil)
    private let controlCheckbox = NSButton(checkboxWithTitle: "Control", target: nil, action: nil)

    init(shortcut: HotKeyShortcut) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let keyLabel = NSTextField(labelWithString: "Key:")
        keyLabel.font = .systemFont(ofSize: 12, weight: .medium)

        keyPopup.translatesAutoresizingMaskIntoConstraints = false
        keyPopup.font = .systemFont(ofSize: 12)
        keyPopup.addItems(withTitles: ShortcutCatalog.keyOptions.map(\.label))

        if let selectedIndex = ShortcutCatalog.keyOptions.firstIndex(where: { $0.keyCode == shortcut.keyCode }) {
            keyPopup.selectItem(at: selectedIndex)
        } else {
            keyPopup.selectItem(at: 0)
        }

        commandCheckbox.state = (shortcut.modifiers & UInt32(cmdKey)) != 0 ? .on : .off
        shiftCheckbox.state = (shortcut.modifiers & UInt32(shiftKey)) != 0 ? .on : .off
        optionCheckbox.state = (shortcut.modifiers & UInt32(optionKey)) != 0 ? .on : .off
        controlCheckbox.state = (shortcut.modifiers & UInt32(controlKey)) != 0 ? .on : .off

        [commandCheckbox, shiftCheckbox, optionCheckbox, controlCheckbox].forEach {
            $0.font = .systemFont(ofSize: 12)
        }

        let keyRow = NSStackView(views: [keyLabel, keyPopup])
        keyRow.orientation = .horizontal
        keyRow.spacing = 8
        keyRow.alignment = .centerY

        let modifierRow = NSStackView(views: [
            commandCheckbox, shiftCheckbox, optionCheckbox, controlCheckbox
        ])
        modifierRow.orientation = .horizontal
        modifierRow.spacing = 10
        modifierRow.alignment = .centerY

        let root = NSStackView(views: [keyRow, modifierRow])
        root.orientation = .vertical
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false

        addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor),
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
            keyPopup.widthAnchor.constraint(equalToConstant: 64),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var shortcutValue: HotKeyShortcut {
        let selectedIndex = max(0, keyPopup.indexOfSelectedItem)
        let keyCode = ShortcutCatalog.keyOptions[selectedIndex].keyCode

        var modifiers: UInt32 = 0
        if commandCheckbox.state == .on { modifiers |= UInt32(cmdKey) }
        if shiftCheckbox.state == .on { modifiers |= UInt32(shiftKey) }
        if optionCheckbox.state == .on { modifiers |= UInt32(optionKey) }
        if controlCheckbox.state == .on { modifiers |= UInt32(controlKey) }

        return HotKeyShortcut(keyCode: keyCode, modifiers: modifiers)
    }
}
