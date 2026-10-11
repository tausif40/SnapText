import Carbon.HIToolbox

/// The app's system-wide hotkey. Carbon hotkeys work without Accessibility permission.
enum GlobalHotKey {
    private static var hotKey: EventHotKeyRef?
    private static var action: (() -> Void)?
    private static var isHandlerInstalled = false

    /// Makes `shortcut` run `action`, replacing any earlier shortcut.
    /// Returns false if the system refused the combination.
    @discardableResult
    static func register(_ shortcut: Shortcut, action: @escaping () -> Void) -> Bool {
        unregister()
        installHandlerIfNeeded()

        let id = EventHotKeyID(signature: 0x4350_5458 /* "CPTX" */, id: 1)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), shortcut.carbonModifiers, id, GetEventDispatcherTarget(), 0, &hotKey)
        guard status == noErr else {
            hotKey = nil
            return false
        }
        self.action = action
        return true
    }

    static func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        action = nil
    }

    private static func installHandlerIfNeeded() {
        guard !isHandlerInstalled else { return }
        isHandlerInstalled = true

        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in
            // Carbon delivers hotkey events on the main thread.
            MainActor.assumeIsolated { GlobalHotKey.action?() }
            return noErr
        }, 1, &pressed, nil, nil)
    }
}
