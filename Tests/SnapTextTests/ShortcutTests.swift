import AppKit
import Carbon.HIToolbox
import Testing
@testable import SnapText

@MainActor
private func keyDown(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags, characters: String) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
        characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(keyCode))!
}

@MainActor
@Suite struct ShortcutTests {
    @Test func defaultIsOptionX() {
        #expect(Shortcut.default.title == "⌥X")
        #expect(Shortcut.default.isDistinctFromTyping)
    }

    @Test func titleListsModifiersInMenuOrder() {
        let shortcut = Shortcut(keyCode: kVK_ANSI_2, key: "2", modifiers: [.command, .shift, .option, .control])
        #expect(shortcut.title == "⌃⌥⇧⌘2")
    }

    // Named keys do not depend on the keyboard layout, unlike letters.
    @Test func readsNamedKeysFromKeyEvents() {
        #expect(Shortcut(event: keyDown(kVK_Space, [.control, .option], characters: " "))?.title == "⌃⌥Space")
        #expect(Shortcut(event: keyDown(kVK_LeftArrow, [.command, .function, .numericPad], characters: "\u{F702}"))?.title == "⌘←")
        #expect(Shortcut(event: keyDown(kVK_Delete, .option, characters: "\u{7F}"))?.title == "⌥⌫")
    }

    @Test func ignoresFlagsThatAreNotModifierKeys() {
        let shortcut = Shortcut(event: keyDown(kVK_F5, [.function, .capsLock], characters: "\u{F708}"))
        #expect(shortcut?.title == "F5")
        #expect(shortcut?.modifiers == [])
    }

    @Test func needsAModifierUnlessItIsAFunctionKey() {
        #expect(!Shortcut(keyCode: kVK_ANSI_A, key: "a", modifiers: []).isDistinctFromTyping)
        #expect(!Shortcut(keyCode: kVK_ANSI_A, key: "a", modifiers: .shift).isDistinctFromTyping)
        #expect(Shortcut(keyCode: kVK_ANSI_A, key: "a", modifiers: .control).isDistinctFromTyping)
        #expect(Shortcut(keyCode: kVK_F5, key: "\u{F708}", modifiers: []).isDistinctFromTyping)
    }

    @Test func survivesBeingStored() {
        let shortcut = Shortcut(keyCode: kVK_Space, key: " ", modifiers: [.control, .option])
        #expect(Shortcut(propertyList: shortcut.propertyList) == shortcut)
    }

    @Test func rejectsWhatItDidNotStore() {
        // Version 1.0 stored the title of a preset.
        #expect(Shortcut(propertyList: "⌃⌥⌘2") == nil)
        #expect(Shortcut(propertyList: ["keyCode": 7]) == nil)
        #expect(Shortcut(propertyList: nil) == nil)
    }
}
