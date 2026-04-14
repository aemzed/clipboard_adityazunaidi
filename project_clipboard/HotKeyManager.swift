//
//  HotKeyManager.swift
//  project_clipboard
//
//  Created by Codex on 14/04/26.
//

import Carbon.HIToolbox
import Foundation

final class HotKeyManager {
    var onHotKeyPressed: (() -> Void)?

    private var eventHandler: EventHandlerRef?
    private var activeHotKeyRef: EventHotKeyRef?
    private var activeHotKeyID: UInt32?

    func registerFirstAvailable(_ shortcuts: [HotKeyShortcut]) -> HotKeyShortcut? {
        installHandlerIfNeeded()

        for (index, shortcut) in shortcuts.enumerated() {
            let candidateID = UInt32(index + 1)
            if register(shortcut: shortcut, hotKeyID: candidateID) {
                return shortcut
            }
        }

        return nil
    }

    func unregister() {
        unregisterHotKey()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit {
        unregister()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData,
                    let event
                else {
                    return noErr
                }

                let manager = Unmanaged<HotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                manager.handleHotKeyEvent(event)
                return noErr
            },
            1,
            &eventSpec,
            userData,
            &eventHandler
        )
    }

    private func register(shortcut: HotKeyShortcut, hotKeyID: UInt32) -> Bool {
        unregisterHotKey()

        var hotKeyRef: EventHotKeyRef?
        let carbonHotKeyID = EventHotKeyID(
            signature: fourCharCode("CLPH"),
            id: hotKeyID
        )

        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            carbonHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr,
            let hotKeyRef
        else {
            return false
        }

        activeHotKeyRef = hotKeyRef
        activeHotKeyID = hotKeyID
        return true
    }

    private func unregisterHotKey() {
        if let activeHotKeyRef {
            UnregisterEventHotKey(activeHotKeyRef)
        }
        activeHotKeyRef = nil
        activeHotKeyID = nil
    }

    private func handleHotKeyEvent(_ event: EventRef) {
        var hotKeyID = EventHotKeyID()
        let result = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard result == noErr,
            hotKeyID.id == activeHotKeyID
        else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onHotKeyPressed?()
        }
    }
}

private func fourCharCode(_ value: String) -> FourCharCode {
    value.utf8.reduce(0) { ($0 << 8) + FourCharCode($1) }
}
