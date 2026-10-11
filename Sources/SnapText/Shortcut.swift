import AppKit
import Carbon.HIToolbox

/// A key combination that can trigger a capture from anywhere.
struct Shortcut: Equatable {
    let keyCode: Int
    /// The key as a menu key equivalent: the character it types on its own, such as "x", or the character
    /// AppKit uses for a key that types nothing, such as an arrow.
    let key: String
    let modifiers: NSEvent.ModifierFlags

    static let `default` = Shortcut(keyCode: kVK_ANSI_X, key: "x", modifiers: .option)

    /// The combination the way macOS menus show it, e.g. "⌥X".
    var title: String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols + (Self.namedKeys[keyCode]?.name ?? key.uppercased())
    }

    var carbonModifiers: UInt32 {
        var flags = 0
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        if modifiers.contains(.command) { flags |= cmdKey }
        return UInt32(flags)
    }

    /// Whether pressing the combination cannot be mistaken for typing: it needs ⌘, ⌃ or ⌥, unless the key
    /// is a function key.
    var isDistinctFromTyping: Bool {
        !modifiers.isDisjoint(with: [.command, .control, .option]) || Self.functionKeys.contains(keyCode)
    }

    private static let functionKeys = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    /// Keys that type nothing visible: the name to show for each, and the character `NSMenuItem` knows it by.
    private static let namedKeys: [Int: (name: String, key: String)] = {
        var keys: [Int: (name: String, key: String)] = [
            kVK_Space: ("Space", " "), kVK_Return: ("↩", "\r"), kVK_Tab: ("⇥", "\t"), kVK_Escape: ("⎋", "\u{1B}"),
            kVK_Delete: ("⌫", "\u{8}"), kVK_ForwardDelete: ("⌦", "\u{7F}"),
            kVK_LeftArrow: ("←", "\u{F702}"), kVK_RightArrow: ("→", "\u{F703}"),
            kVK_UpArrow: ("↑", "\u{F700}"), kVK_DownArrow: ("↓", "\u{F701}"),
            kVK_Home: ("↖", "\u{F729}"), kVK_End: ("↘", "\u{F72B}"),
            kVK_PageUp: ("⇞", "\u{F72C}"), kVK_PageDown: ("⇟", "\u{F72D}"),
        ]
        // AppKit numbers F1 to F20 consecutively from U+F704.
        for (index, keyCode) in functionKeys.enumerated() {
            keys[keyCode] = ("F\(index + 1)", String(UnicodeScalar(0xF704 + index)!))
        }
        return keys
    }()
}

extension Shortcut {
    /// The combination pressed in a key-down `event`, or nil for a key that has no name to show.
    init?(event: NSEvent) {
        let keyCode = Int(event.keyCode)
        guard let key = Self.namedKeys[keyCode]?.key ?? Self.character(typedBy: event) else { return nil }
        self.init(
            keyCode: keyCode, key: key,
            modifiers: event.modifierFlags.intersection([.control, .option, .shift, .command]))
    }

    /// The character the event's key types with no modifier held, if it is a visible one.
    private static func character(typedBy event: NSEvent) -> String? {
        guard let typed = event.characters(byApplyingModifiers: []), let first = typed.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(first) else { return nil }
        return typed
    }

    /// Restores a shortcut from the form `propertyList` gives.
    init?(propertyList: Any?) {
        guard let values = propertyList as? [String: Any], let keyCode = values["keyCode"] as? Int,
              let key = values["key"] as? String, let modifiers = values["modifiers"] as? UInt else { return nil }
        self.init(keyCode: keyCode, key: key, modifiers: NSEvent.ModifierFlags(rawValue: modifiers))
    }

    /// A form that user defaults can store.
    var propertyList: [String: Any] {
        ["keyCode": keyCode, "key": key, "modifiers": modifiers.rawValue]
    }
}
