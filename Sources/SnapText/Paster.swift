import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Pastes into the app in front, as if the user pressed ⌘V there. macOS lets an app look at other apps' text
/// fields and press keys in them only once the user has allowed it under Accessibility.
enum Paster {
    /// The roles of the elements that take typed text.
    private static let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"]

    /// What the keyboard focus of the app in front is in.
    enum Focus {
        /// Something that takes typed text: a text field, or editable web content such as a chat box.
        case text
        /// Something else, such as a list or a button.
        case other
        /// The app does not say. Chrome and the other Chromium browsers keep quiet about what is focused in a web
        /// page, and Safari says only once it has been asked before.
        case unknown
    }

    /// An app to paste into, noted when the clipboard history opens, before the history takes the keyboard.
    struct Target {
        let app: NSRunningApplication
        /// Whether the app said it had a text field focused, rather than not saying.
        let hasTextField: Bool
    }

    static var hasPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the macOS prompt that adds SnapText to the Accessibility list and leads to System Settings.
    static func requestPermission() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// The app in front, unless its keyboard focus is known to be in something that takes no text. Without
    /// permission there is no telling, so the answer is nil.
    static func target() -> Target? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        switch focus {
        case .text: return Target(app: app, hasTextField: true)
        // ⌘V does nothing where there is nothing to paste into, so pasting is safe.
        case .unknown: return Target(app: app, hasTextField: false)
        case .other: return nil
        }
    }

    /// What the keyboard focus of the app in front is in.
    static var focus: Focus {
        guard hasPermission, let app = NSWorkspace.shared.frontmostApplication,
              app != NSRunningApplication.current else { return .other }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // An app that has stopped responding would otherwise hold things up for six seconds.
        AXUIElementSetMessagingTimeout(element, 0.5)

        var focused = focusedElement(in: element)
        if focused == nil {
            // Electron apps describe their windows only to those who ask for it.
            AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            focused = focusedElement(in: element)
        }
        guard let focused else { return .unknown }

        let role = value(of: kAXRoleAttribute, in: focused) as? String
        if let role, textRoles.contains(role) { return .text }
        // Editable web content, such as a chat box, can have other roles, but browsers tell which editable element
        // it belongs to, and let its selection be moved.
        if value(of: "AXEditableAncestor", in: focused) != nil { return .text }
        if isSettable(kAXSelectedTextRangeAttribute, in: focused) { return .text }
        // The page itself, while the browser is still working out which of its elements has the focus.
        if role == "AXWebArea" { return .unknown }
        return .other
    }

    /// Presses ⌘V in the target app once it has the keyboard back from the history panel, if it is still in front.
    static func paste(into target: Target) {
        Task {
            // The app gets the keyboard back a moment after the panel closes. A ⌘V sent before then finds no text
            // field to paste into, so wait for one to have the focus again, for half a second at most. An app that
            // did not say what had the focus will not say now either, so it only gets a moment.
            try? await Task.sleep(for: .milliseconds(50))
            let waitsAllowed = target.hasTextField ? 10 : 2
            var waits = 0
            while focus != .text, waits < waitsAllowed {
                try? await Task.sleep(for: .milliseconds(50))
                waits += 1
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.app.processIdentifier else {
                return
            }
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

    private static func isSettable(_ attribute: String, in element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }

    private static func value(of attribute: String, in element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }
}
