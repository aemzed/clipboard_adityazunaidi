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

        let model = ShortcutEditorModel(shortcut: preferredShortcut)
        let content = ShortcutEditorModalContent(model: model)
        let hostingController = NSHostingController(rootView: content)

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.title = "Edit Global Shortcut"
        panel.setContentSize(NSSize(width: 340, height: 320))
        panel.center()
        panel.isReleasedWhenClosed = false

        model.onCancel = {
            NSApp.stopModal(withCode: .cancel)
            panel.orderOut(nil)
        }
        model.onSave = {
            NSApp.stopModal(withCode: .OK)
            panel.orderOut(nil)
        }

        let closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { _ in
            NSApp.stopModal(withCode: .cancel)
        }

        let response = NSApp.runModal(for: panel)
        NotificationCenter.default.removeObserver(closeObserver)
        panel.orderOut(nil)

        guard response == .OK else { return }

        let candidate = model.shortcutValue
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

private final class ShortcutEditorModel: ObservableObject {
    @Published var selectedKeyCode: UInt32
    @Published var useCommand: Bool
    @Published var useShift: Bool
    @Published var useOption: Bool
    @Published var useControl: Bool

    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    init(shortcut: HotKeyShortcut) {
        self.selectedKeyCode = shortcut.keyCode
        self.useCommand = (shortcut.modifiers & UInt32(cmdKey)) != 0
        self.useShift = (shortcut.modifiers & UInt32(shiftKey)) != 0
        self.useOption = (shortcut.modifiers & UInt32(optionKey)) != 0
        self.useControl = (shortcut.modifiers & UInt32(controlKey)) != 0
    }

    var shortcutValue: HotKeyShortcut {
        var modifiers: UInt32 = 0
        if useCommand { modifiers |= UInt32(cmdKey) }
        if useShift { modifiers |= UInt32(shiftKey) }
        if useOption { modifiers |= UInt32(optionKey) }
        if useControl { modifiers |= UInt32(controlKey) }
        return HotKeyShortcut(keyCode: selectedKeyCode, modifiers: modifiers)
    }
}

private struct ShortcutEditorModalContent: View {
    @ObservedObject var model: ShortcutEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set keyboard shortcut to open Clipboard History.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text("Key:")
                    .font(.body.weight(.medium))
                Picker("", selection: $model.selectedKeyCode) {
                    ForEach(ShortcutCatalog.keyOptions) { option in
                        Text(option.label).tag(option.keyCode)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Modifiers:")
                    .font(.body.weight(.medium))

                Toggle("Command (⌘)", isOn: $model.useCommand)
                Toggle("Shift (⇧)", isOn: $model.useShift)
                Toggle("Option (⌥)", isOn: $model.useOption)
                Toggle("Control (⌃)", isOn: $model.useControl)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") {
                    model.onCancel?()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    model.onSave?()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320, height: 300)
    }
}
