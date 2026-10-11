import AppKit
import Carbon.HIToolbox

/// A dialog in which the user presses the key combination they want to capture text with.
final class ShortcutRecorder {
    let alert = NSAlert()
    private let field = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "")
    /// The combination the dialog shows: the current one until the user presses another.
    private(set) var shortcut: Shortcut

    init(current: Shortcut) {
        shortcut = current
        field.stringValue = current.title

        alert.messageText = "Change Shortcut"
        alert.informativeText = "Press the key combination that should capture text."
        alert.accessoryView = makeAccessory()
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
    }

    /// Shows the dialog. Returns the combination to use from now on, or nil if the user cancelled.
    func runModal() -> Shortcut? {
        // A monitor sees every key press, whichever control in the dialog has the focus.
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { self.record($0) }
        defer {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        return alert.runModal() == .alertFirstButtonReturn ? shortcut : nil
    }

    /// Takes a key press as the new combination. Returns the event if the dialog should handle it itself.
    func record(_ event: NSEvent) -> NSEvent? {
        // Leave the keys that work the dialog alone: Return saves, Escape cancels, Tab and Space use the buttons.
        let dialogKeys = [kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape, kVK_Tab, kVK_Space]
        if event.modifierFlags.isDisjoint(with: [.command, .control, .option]), dialogKeys.contains(Int(event.keyCode)) {
            return event
        }

        guard let pressed = Shortcut(event: event), pressed.isDistinctFromTyping else {
            hint.stringValue = "Add ⌘, ⌃ or ⌥ to the key."
            NSSound.beep()
            return nil
        }
        shortcut = pressed
        field.stringValue = pressed.title
        hint.stringValue = ""
        return nil
    }

    /// The well that shows the combination, with room underneath for a hint.
    private func makeAccessory() -> NSView {
        field.font = .systemFont(ofSize: 22, weight: .medium)
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center

        let well = NSBox()
        well.boxType = .custom
        well.cornerRadius = 8
        well.borderColor = .separatorColor
        well.fillColor = .quaternaryLabelColor
        well.addSubview(field)

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 228, height: 68))
        for view in [well, field, hint] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        accessory.addSubview(well)
        accessory.addSubview(hint)
        NSLayoutConstraint.activate([
            well.topAnchor.constraint(equalTo: accessory.topAnchor),
            well.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
            well.trailingAnchor.constraint(equalTo: accessory.trailingAnchor),
            well.heightAnchor.constraint(equalToConstant: 44),
            field.centerXAnchor.constraint(equalTo: well.centerXAnchor),
            field.centerYAnchor.constraint(equalTo: well.centerYAnchor),
            hint.topAnchor.constraint(equalTo: well.bottomAnchor, constant: 6),
            hint.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: accessory.trailingAnchor),
        ])
        return accessory
    }
}
