import AppKit
import Carbon.HIToolbox

/// A button that shows a shortcut. Clicking it records the next key combination the user presses as the new one.
final class ShortcutField: NSButton {
    private(set) var shortcut: Shortcut
    /// Offered each combination the user presses. Returns why it cannot be used, or nil once it is in use.
    var onRecord: (Shortcut) -> String? = { _ in nil }
    /// Called with true when recording starts and false when it stops.
    var onRecordingChange: (Bool) -> Void = { _ in }
    /// Called with a hint or a problem to show by the field, or nil when there is none.
    var onMessage: (String?) -> Void = { _ in }

    private var monitor: Any?
    var isRecording: Bool { monitor != nil }

    init(shortcut: Shortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        bezelStyle = .rounded
        title = shortcut.title
        target = self
        action = #selector(clicked)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ shortcut: Shortcut) {
        self.shortcut = shortcut
        if !isRecording { title = shortcut.title }
    }

    @objc private func clicked() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        // A monitor sees every key press, whichever control has the focus.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return record(event)
        }
        title = "Press Shortcut…"
        onMessage("Press the new combination, or esc to keep \(shortcut.title).")
        onRecordingChange(true)
    }

    func stopRecording() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        title = shortcut.title
        onMessage(nil)
        onRecordingChange(false)
    }

    /// Takes a key press as the new combination.
    private func record(_ event: NSEvent) -> NSEvent? {
        if event.modifierFlags.isDisjoint(with: [.command, .control, .option]), event.keyCode == kVK_Escape {
            stopRecording()
            return nil
        }
        guard let pressed = Shortcut(event: event), pressed.isDistinctFromTyping else {
            onMessage("Add ⌘, ⌃ or ⌥ to the key.")
            NSSound.beep()
            return nil
        }
        if pressed != shortcut, let problem = onRecord(pressed) {
            onMessage(problem)
            NSSound.beep()
            return nil
        }
        shortcut = pressed
        stopRecording()
        return nil
    }
}
