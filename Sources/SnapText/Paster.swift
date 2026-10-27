import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Pastes into the app in front, as if the user pressed ⌘V there. macOS lets an app look at other apps' text
/// fields and press keys in them only once the user has allowed it under Accessibility.
enum Paster {
    /// The roles of the elements that take typed text.
    private static let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"]

    static var hasPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the macOS prompt that adds SnapText to the Accessibility list and leads to System Settings.
    static func requestPermission() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Whether the app in front has the keyboard focus in something that takes text. Without permission there
    /// is no telling, so the answer is no.
    static var isTypingInTextField: Bool {
        guard hasPermission, let app = NSWorkspace.shared.frontmostApplication,
              app != NSRunningApplication.current else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // An app that has stopped responding would otherwise hold things up for six seconds.
        AXUIElementSetMessagingTimeout(element, 0.5)

        var focused = focusedElement(in: element)
        if focused == nil {
            // Electron apps describe their windows only to those who ask for it.
            AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            focused = focusedElement(in: element)
        }
        guard let focused else { return false }

        if let role = value(of: kAXRoleAttribute, in: focused) as? String, textRoles.contains(role) { return true }
        // Editable web content has other roles, but it lets the selection be moved.
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(focused, kAXSelectedTextRangeAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    /// Presses ⌘V in the app in front.
    static func paste() {
        // Give the app a moment to get the keyboard back from the history panel.
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            let source = CGEventSource(stateID: .combinedSessionState)
            for isDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: isDown)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    private static func focusedElement(in app: AXUIElement) -> AXUIElement? {
        guard let focused = value(of: kAXFocusedUIElementAttribute, in: app),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(focused, to: AXUIElement.self)
    }

    private static func value(of attribute: String, in element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }
}
