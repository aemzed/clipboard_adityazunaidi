//
//  project_clipboardApp.swift
//  project_clipboard
//
//  Created by Adit's Macbook    on 14/04/26.
//

import AppKit
import Combine
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

    @objc func openHistoryWindow() {
        AppLifecycle.shared.toggleHistoryWindow()
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
            onToggleMonitoring: { [weak self] in
                guard let self else { return }
                self.monitor.setMonitoring(!self.monitor.isMonitoring)
            },
            isMonitoringEnabled: { [weak self] in
                self?.monitor.isMonitoring ?? false
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
}
