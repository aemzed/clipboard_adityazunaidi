//
//  ShortcutCatalog.swift
//  project_clipboard
//
//  Created by Codex on 14/04/26.
//

import Carbon.HIToolbox
import Foundation

struct HotKeyShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    var displayText: String {
        ShortcutCatalog.display(shortcut: self)
    }

    static let defaultPrimary = HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(shiftKey | cmdKey)
    )

    static let defaultFallbacks: [HotKeyShortcut] = [
        HotKeyShortcut(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        ),
        HotKeyShortcut(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        ),
    ]
}

struct ShortcutKeyOption: Identifiable, Hashable {
    let label: String
    let keyCode: UInt32

    var id: UInt32 { keyCode }
}

enum ShortcutCatalog {
    static let keyOptions: [ShortcutKeyOption] = [
        ShortcutKeyOption(label: "A", keyCode: UInt32(kVK_ANSI_A)),
        ShortcutKeyOption(label: "B", keyCode: UInt32(kVK_ANSI_B)),
        ShortcutKeyOption(label: "C", keyCode: UInt32(kVK_ANSI_C)),
        ShortcutKeyOption(label: "D", keyCode: UInt32(kVK_ANSI_D)),
        ShortcutKeyOption(label: "E", keyCode: UInt32(kVK_ANSI_E)),
        ShortcutKeyOption(label: "F", keyCode: UInt32(kVK_ANSI_F)),
        ShortcutKeyOption(label: "G", keyCode: UInt32(kVK_ANSI_G)),
        ShortcutKeyOption(label: "H", keyCode: UInt32(kVK_ANSI_H)),
        ShortcutKeyOption(label: "I", keyCode: UInt32(kVK_ANSI_I)),
        ShortcutKeyOption(label: "J", keyCode: UInt32(kVK_ANSI_J)),
        ShortcutKeyOption(label: "K", keyCode: UInt32(kVK_ANSI_K)),
        ShortcutKeyOption(label: "L", keyCode: UInt32(kVK_ANSI_L)),
        ShortcutKeyOption(label: "M", keyCode: UInt32(kVK_ANSI_M)),
        ShortcutKeyOption(label: "N", keyCode: UInt32(kVK_ANSI_N)),
        ShortcutKeyOption(label: "O", keyCode: UInt32(kVK_ANSI_O)),
        ShortcutKeyOption(label: "P", keyCode: UInt32(kVK_ANSI_P)),
        ShortcutKeyOption(label: "Q", keyCode: UInt32(kVK_ANSI_Q)),
        ShortcutKeyOption(label: "R", keyCode: UInt32(kVK_ANSI_R)),
        ShortcutKeyOption(label: "S", keyCode: UInt32(kVK_ANSI_S)),
        ShortcutKeyOption(label: "T", keyCode: UInt32(kVK_ANSI_T)),
        ShortcutKeyOption(label: "U", keyCode: UInt32(kVK_ANSI_U)),
        ShortcutKeyOption(label: "V", keyCode: UInt32(kVK_ANSI_V)),
        ShortcutKeyOption(label: "W", keyCode: UInt32(kVK_ANSI_W)),
        ShortcutKeyOption(label: "X", keyCode: UInt32(kVK_ANSI_X)),
        ShortcutKeyOption(label: "Y", keyCode: UInt32(kVK_ANSI_Y)),
        ShortcutKeyOption(label: "Z", keyCode: UInt32(kVK_ANSI_Z)),
        ShortcutKeyOption(label: "0", keyCode: UInt32(kVK_ANSI_0)),
        ShortcutKeyOption(label: "1", keyCode: UInt32(kVK_ANSI_1)),
        ShortcutKeyOption(label: "2", keyCode: UInt32(kVK_ANSI_2)),
        ShortcutKeyOption(label: "3", keyCode: UInt32(kVK_ANSI_3)),
        ShortcutKeyOption(label: "4", keyCode: UInt32(kVK_ANSI_4)),
        ShortcutKeyOption(label: "5", keyCode: UInt32(kVK_ANSI_5)),
        ShortcutKeyOption(label: "6", keyCode: UInt32(kVK_ANSI_6)),
        ShortcutKeyOption(label: "7", keyCode: UInt32(kVK_ANSI_7)),
        ShortcutKeyOption(label: "8", keyCode: UInt32(kVK_ANSI_8)),
        ShortcutKeyOption(label: "9", keyCode: UInt32(kVK_ANSI_9)),
    ]

    static func display(shortcut: HotKeyShortcut) -> String {
        let key = keyLabel(for: shortcut.keyCode)
        let modifiers = modifierLabels(for: shortcut.modifiers)
        if modifiers.isEmpty { return key }
        return "\(modifiers.joined(separator: " + ")) + \(key)"
    }

    static func keyLabel(for keyCode: UInt32) -> String {
        keyOptions.first(where: { $0.keyCode == keyCode })?.label ?? "Key(\(keyCode))"
    }

    static func modifierLabels(for modifiers: UInt32) -> [String] {
        var labels: [String] = []
        if (modifiers & UInt32(controlKey)) != 0 { labels.append("Control") }
        if (modifiers & UInt32(optionKey)) != 0 { labels.append("Option") }
        if (modifiers & UInt32(cmdKey)) != 0 { labels.append("Command") }
        if (modifiers & UInt32(shiftKey)) != 0 { labels.append("Shift") }
        return labels
    }
}
