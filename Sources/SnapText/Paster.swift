import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Pastes into the app the user was in, as if they pressed ⌘V there. macOS lets an app press keys in other apps
/// only once the user has allowed it under Accessibility.
///
/// It does not first check that a text field has the focus. Browsers do not say what has the focus inside a web
/// page, so a check left out the ChatGPT prompt box and every other text box on the web. ⌘V does nothing where
/// there is nothing to paste into, so pasting everywhere is safe.
enum Paster {
    static var hasPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the macOS prompt that adds SnapText to the Accessibility list and leads to System Settings.
    static func requestPermission() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// The app to paste into: the one in front, noted before the clipboard history takes the keyboard. Nil when
    /// that is SnapText itself, or without permission, since nothing can be pasted then.
    static func target() -> NSRunningApplication? {
        guard hasPermission, let app = NSWorkspace.shared.frontmostApplication,
              app != NSRunningApplication.current else { return nil }
        return app
    }

    /// Presses ⌘V in `app` once it has the keyboard back from the history panel, if it is still in front. The text
    /// to paste must already be on the clipboard.
    static func paste(into app: NSRunningApplication) {
        Task {
            // A ⌘V sent before the app has the keyboard back finds nothing to paste into.
            try? await Task.sleep(for: .milliseconds(100))
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
            let source = CGEventSource(stateID: .combinedSessionState)
            for isDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: isDown)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
    }
}
