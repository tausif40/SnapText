import Carbon.HIToolbox

/// The app's system-wide hotkeys. Carbon hotkeys work without Accessibility permission.
enum GlobalHotKey {
    /// What a hotkey does. Each purpose has one combination at a time.
    enum Purpose: UInt32 {
        case capture = 1
        case history = 2
    }

    private static var hotKeys: [Purpose: EventHotKeyRef] = [:]
    private static var actions: [Purpose: () -> Void] = [:]
    private static var isHandlerInstalled = false

    /// Makes `shortcut` run `action`, replacing any earlier shortcut for the same purpose.
    /// Returns false if the system refused the combination.
    @discardableResult
    static func register(_ shortcut: Shortcut, for purpose: Purpose, action: @escaping () -> Void) -> Bool {
        unregister(purpose)
        installHandlerIfNeeded()

        var hotKey: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x4350_5458 /* "CPTX" */, id: purpose.rawValue)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), shortcut.carbonModifiers, id, GetEventDispatcherTarget(), 0, &hotKey)
        guard status == noErr, let hotKey else { return false }
        hotKeys[purpose] = hotKey
        actions[purpose] = action
        return true
    }

    static func unregister(_ purpose: Purpose) {
        if let hotKey = hotKeys.removeValue(forKey: purpose) { UnregisterEventHotKey(hotKey) }
        actions[purpose] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !isHandlerInstalled else { return }
        isHandlerInstalled = true

        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return OSStatus(eventNotHandledErr) }
            // Carbon delivers hotkey events on the main thread.
            MainActor.assumeIsolated {
                if let purpose = Purpose(rawValue: id.id) { GlobalHotKey.actions[purpose]?() }
            }
            return noErr
        }, 1, &pressed, nil, nil)
    }
}
