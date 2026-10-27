import AppKit

/// Every setting SnapText has, in rounded groups: the clipboard history, text capture, and general ones. The
/// clipboard history popup and the SnapText window each show one.
final class SettingsView: NSView, NSTextFieldDelegate {
    private static let copiesRange = 1...ClipboardHistory.capacity
    private static let daysRange = 1...365

    /// Makes a shortcut do something. Returns why it cannot, or nil once it does.
    var onChangeShortcut: (Shortcut, GlobalHotKey.Purpose) -> String? = { _, _ in nil }
    /// Called with true while a new shortcut is being recorded, when the current ones must not work, and false after.
    var onPauseShortcuts: (Bool) -> Void = { _ in }

    private let history: ClipboardHistory
    /// The width of the groups, which wrapping notes need to know.
    private let groupWidth: CGFloat

    private let historyShortcut = ShortcutField(shortcut: Preferences.historyShortcut)
    private let historyShortcutMessage = SettingsView.note()
    private let keepSwitch = SettingsView.switch()
    private let pasteSwitch = SettingsView.switch()
    private let privateSwitch = SettingsView.switch()
    /// Warns that passwords are being saved, while they are.
    private let privateWarning = SettingsView.note()
    private let privacy = SettingsView.note()
    /// Explains that pasting needs Accessibility permission, while it is missing.
    private let permissionNote = NSStackView()
    private let limitKind = NSPopUpButton()
    private let limitField = NSTextField()
    private let limitStepper = NSStepper()
    private let limitUnit = NSTextField(labelWithString: "")
    private let limitWarning = SettingsView.note()
    private let defaultLimitButton = NSButton()
    private let opacitySlider = NSSlider()
    private let opacityValue = NSTextField(labelWithString: "")
    private let savedCount = NSTextField(labelWithString: "")
    private let clearButton = NSButton()
    private let captureShortcut = ShortcutField(shortcut: Preferences.shortcut)
    private let captureShortcutMessage = SettingsView.note()
    private let lineBreaksSwitch = SettingsView.switch()
    private let noticeSwitch = SettingsView.switch()
    private let launchSwitch = SettingsView.switch()
    /// Whether the clear button has been clicked once and waits for the second click that confirms it.
    private var isConfirmingClear = false

    /// A view `width` points wide, with `margin` points on each side of its groups.
    init(history: ClipboardHistory, width: CGFloat, margin: CGFloat) {
        self.history = history
        groupWidth = width - 2 * margin
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        build(margin: margin)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Lays out from the top, as a scrolling page reads.
    override var isFlipped: Bool { true }

    /// Shows the current settings, and drops any change that was half done.
    func reset() {
        isConfirmingClear = false
        stopRecording()
        showLimitWarning(false)
        update()
    }

    func stopRecording() {
        historyShortcut.stopRecording()
        captureShortcut.stopRecording()
    }

    /// Shows the current settings.
    func update() {
        let byDays = Preferences.limitsHistoryByDays
        let range = limitRange
        let value = byDays ? Preferences.historyDays : Preferences.historyCopies

        historyShortcut.show(Preferences.historyShortcut)
        keepSwitch.state = Preferences.keepsHistory ? .on : .off
        pasteSwitch.state = Preferences.pastesFromHistory ? .on : .off
        privateSwitch.state = Preferences.savesPrivateCopies ? .on : .off
        privateWarning.isHidden = !Preferences.savesPrivateCopies
        privacy.stringValue = Preferences.savesPrivateCopies
            ? "Copies stay on this Mac. Lowering the limit deletes the older ones straight away."
            : """
                Copies stay on this Mac. Lowering the limit deletes the older ones straight away, and copies that \
                password managers mark as private are never saved.
                """
        permissionNote.isHidden = !Preferences.pastesFromHistory || Paster.hasPermission
        limitKind.selectItem(at: byDays ? 1 : 0)
        limitField.integerValue = value
        limitStepper.minValue = Double(range.lowerBound)
        limitStepper.maxValue = Double(range.upperBound)
        limitStepper.integerValue = value
        limitUnit.stringValue = byDays ? (value == 1 ? "day" : "days") : (value == 1 ? "copy" : "copies")
        let defaultValue = byDays ? Preferences.defaultHistoryDays : Preferences.defaultHistoryCopies
        defaultLimitButton.title = "Use the Default, \(defaultValue) \(byDays ? "Days" : "Copies")"
        defaultLimitButton.isHidden = value == defaultValue

        opacitySlider.doubleValue = Preferences.historyOpacity
        showOpacity()

        let count = history.entries.count
        savedCount.stringValue = switch count {
        case 0: "No copies saved"
        case 1: "1 copy saved"
        default: "\(count.formatted()) copies saved"
        }
        clearButton.title = isConfirmingClear
            ? "Click Again to Delete"
            : "Clear History"
        clearButton.isEnabled = count > 0

        captureShortcut.show(Preferences.shortcut)
        lineBreaksSwitch.state = Preferences.keepLineBreaks ? .on : .off
        noticeSwitch.state = Preferences.showCopiedNotice ? .on : .off
        launchSwitch.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    // MARK: - Changes

    private var limitRange: ClosedRange<Int> {
        Preferences.limitsHistoryByDays ? Self.daysRange : Self.copiesRange
    }

    @objc private func keepChanged() {
        Preferences.keepsHistory = keepSwitch.state == .on
        update()
    }

    @objc private func privateChanged() {
        Preferences.savesPrivateCopies = privateSwitch.state == .on
        update()
    }

    @objc private func pasteChanged() {
        Preferences.pastesFromHistory = pasteSwitch.state == .on
        if Preferences.pastesFromHistory, !Paster.hasPermission {
            Preferences.hasAskedToPaste = true
            Paster.requestPermission()
        }
        update()
    }

    @objc private func allowPastingClicked() {
        Paster.requestPermission()
        NSWorkspace.shared.open(Constants.accessibilitySettings)
    }

    @objc private func limitKindChanged() {
        Preferences.limitsHistoryByDays = limitKind.indexOfSelectedItem == 1
        showLimitWarning(false)
        applyLimit()
    }

    @objc private func limitValueChanged(_ sender: NSControl) {
        // Anything that is not a whole number puts back the value there was, rather than deleting copies.
        let typed = sender === limitStepper ? limitStepper.integerValue : Int(limitField.stringValue.filter(\.isNumber))
        guard let typed, typed > 0 else { return update() }

        let range = limitRange
        showLimitWarning(typed > range.upperBound)
        let value = min(typed, range.upperBound)
        if Preferences.limitsHistoryByDays { Preferences.historyDays = value } else { Preferences.historyCopies = value }
        applyLimit()
    }

    /// Says so while the user types a limit larger than there can be, before it is cut down.
    func controlTextDidChange(_ notification: Notification) {
        let typed = Int(limitField.stringValue.filter(\.isNumber)) ?? 0
        showLimitWarning(typed > limitRange.upperBound)
    }

    @objc private func defaultLimitClicked() {
        if Preferences.limitsHistoryByDays {
            Preferences.historyDays = Preferences.defaultHistoryDays
        } else {
            Preferences.historyCopies = Preferences.defaultHistoryCopies
        }
        showLimitWarning(false)
        applyLimit()
    }

    private func applyLimit() {
        history.limit = Preferences.historyLimit
        update()
    }

    private func showLimitWarning(_ isShown: Bool) {
        limitWarning.stringValue = Preferences.limitsHistoryByDays
            ? "You can’t keep more than \(Self.daysRange.upperBound) days."
            : "You can’t save more than \(ClipboardHistory.capacity.formatted()) copies."
        limitWarning.isHidden = !isShown
    }

    @objc private func opacityChanged() {
        Preferences.historyOpacity = opacitySlider.doubleValue
        showOpacity()
    }

    private func showOpacity() {
        opacityValue.stringValue = "\(Int((opacitySlider.doubleValue * 100).rounded()))%"
    }

    @objc private func clearClicked() {
        if isConfirmingClear { history.removeAll() }
        isConfirmingClear.toggle()
        update()
    }

    @objc private func lineBreaksChanged() {
        Preferences.keepLineBreaks = lineBreaksSwitch.state == .on
    }

    @objc private func noticeChanged() {
        Preferences.showCopiedNotice = noticeSwitch.state == .on
    }

    @objc private func launchChanged() {
        LaunchAtLogin.set(launchSwitch.state == .on)
        update()
    }

    /// Sets up a shortcut field to change the shortcut for `purpose`, with `message` below it for its hints.
    private func connect(_ field: ShortcutField, to purpose: GlobalHotKey.Purpose, message: NSTextField) {
        field.onRecord = { [weak self] shortcut in self?.onChangeShortcut(shortcut, purpose) ?? nil }
        field.onMessage = { text in
            message.stringValue = text ?? ""
            message.isHidden = text == nil
        }
        field.onRecordingChange = { [weak self] isRecording in
            guard let self else { return }
            // One at a time.
            if isRecording {
                for other in [historyShortcut, captureShortcut] where other !== field { other.stopRecording() }
            }
            onPauseShortcuts(isRecording)
        }
    }

    // MARK: - Layout

    private func build(margin: CGFloat) {
        for (control, action) in [
            (keepSwitch, #selector(keepChanged)), (pasteSwitch, #selector(pasteChanged)),
            (privateSwitch, #selector(privateChanged)),
            (lineBreaksSwitch, #selector(lineBreaksChanged)), (noticeSwitch, #selector(noticeChanged)),
            (launchSwitch, #selector(launchChanged)),
        ] {
            control.target = self
            control.action = action
        }
        connect(historyShortcut, to: .history, message: historyShortcutMessage)
        connect(captureShortcut, to: .capture, message: captureShortcutMessage)
        for field in [historyShortcut, captureShortcut] {
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true
        }

        let permissionText = Self.note()
        permissionText.stringValue = "Pasting needs Accessibility permission."
        let allowButton = Self.smallButton("Allow in System Settings", target: self, action: #selector(allowPastingClicked))
        permissionNote.setViews([permissionText, allowButton], in: .leading)
        permissionNote.orientation = .vertical
        permissionNote.alignment = .leading
        permissionNote.spacing = 4

        limitKind.addItems(withTitles: ["Number of copies", "Number of days"])
        limitKind.target = self
        limitKind.action = #selector(limitKindChanged)
        limitField.alignment = .right
        limitField.delegate = self
        limitField.cell?.sendsActionOnEndEditing = true
        limitField.target = self
        limitField.action = #selector(limitValueChanged)
        limitField.widthAnchor.constraint(equalToConstant: 56).isActive = true
        limitStepper.autorepeat = true
        limitStepper.valueWraps = false
        limitStepper.target = self
        limitStepper.action = #selector(limitValueChanged)
        limitWarning.textColor = .systemRed
        defaultLimitButton.bezelStyle = .rounded
        defaultLimitButton.controlSize = .small
        defaultLimitButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        defaultLimitButton.target = self
        defaultLimitButton.action = #selector(defaultLimitClicked)
        opacitySlider.minValue = Preferences.historyOpacityRange.lowerBound
        opacitySlider.maxValue = Preferences.historyOpacityRange.upperBound
        opacitySlider.isContinuous = true
        opacitySlider.controlSize = .small
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged)
        opacitySlider.widthAnchor.constraint(equalToConstant: 120).isActive = true
        opacityValue.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        opacityValue.textColor = .secondaryLabelColor
        opacityValue.alignment = .right
        opacityValue.widthAnchor.constraint(equalToConstant: 36).isActive = true
        let opacity = NSStackView(views: [opacitySlider, opacityValue])
        opacity.spacing = 6
        savedCount.font = .systemFont(ofSize: 13)
        clearButton.bezelStyle = .rounded
        clearButton.hasDestructiveAction = true
        clearButton.target = self
        clearButton.action = #selector(clearClicked)
        for message in [historyShortcutMessage, limitWarning, captureShortcutMessage] {
            message.isHidden = true
        }
        let limitValue = NSStackView(views: [limitField, limitStepper, limitUnit])
        limitValue.spacing = 4

        privateWarning.textColor = .systemRed
        privateWarning.stringValue = """
            Passwords and other private copies are saved too, as plain text in the history file. Anyone using \
            this Mac can see them in the history.
            """

        let historyGroup = Groups.box([
            row("Shortcut", historyShortcut, notes: [historyShortcutMessage]),
            row("Save history", keepSwitch),
            row("Paste into text fields", pasteSwitch, notes: [permissionNote]),
            row("Save passwords and private copies", privateSwitch, notes: [privateWarning]),
            row("Limit by", limitKind),
            row("Keep the last", limitValue, notes: [limitWarning, defaultLimitButton]),
            row("Popup opacity", opacity),
            row(savedCount, clearButton),
        ])
        let captureGroup = Groups.box([
            row("Shortcut", captureShortcut, notes: [captureShortcutMessage]),
            row("Keep line breaks", lineBreaksSwitch),
            row("Show copied notice", noticeSwitch),
        ])
        let content = NSStackView(views: [
            Groups.heading("Clipboard History"), historyGroup, privacy,
            Groups.heading("Capture Text (OCR)"), captureGroup,
            Groups.heading("General"), Groups.box([row("Open SnapText at login", launchSwitch)]),
        ])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        content.setCustomSpacing(6, after: historyGroup)
        content.setCustomSpacing(20, after: privacy)
        content.setCustomSpacing(20, after: captureGroup)

        privacy.preferredMaxLayoutWidth = groupWidth - 8
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            privacy.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 4),
        ])
    }

    private func row(_ title: String, _ control: NSView, notes: [NSView] = []) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        return row(label, control, notes: notes)
    }

    /// A row of a group: a label, the control that sets it at the far end, and any notes underneath.
    private func row(_ label: NSTextField, _ control: NSView, notes: [NSView] = []) -> NSView {
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if let control = control as? NSStackView {
            control.setHuggingPriority(.defaultHigh, for: .horizontal)
        } else {
            control.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        }
        let line = NSStackView(views: [label, control])
        // The label takes the spare width, which puts the control at the far end.
        line.distribution = .fill
        line.spacing = 12
        line.heightAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true

        let row = NSStackView(views: [line] + notes)
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        line.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -24).isActive = true
        for case let note as NSTextField in notes {
            note.preferredMaxLayoutWidth = groupWidth - 24
        }
        return row
    }

    private static func `switch`() -> NSSwitch {
        let control = NSSwitch()
        control.controlSize = .small
        return control
    }

    private static func note() -> NSTextField {
        let note = NSTextField(wrappingLabelWithString: "")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        return note
    }

    private static func smallButton(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        return button
    }
}

/// Rounded groups of rows, as System Settings shows them.
enum Groups {
    static func heading(_ text: String) -> NSTextField {
        let heading = NSTextField(labelWithString: text)
        heading.font = .systemFont(ofSize: 12, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        return heading
    }

    /// Rows in a rounded box as wide as its container, with a line between each.
    static func box(_ rows: [NSView]) -> NSBox {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let line = NSBox()
                line.boxType = .separator
                stack.addArrangedSubview(line)
                line.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let box = FullWidthBox()
        box.boxType = .custom
        box.cornerRadius = 10
        box.borderColor = .separatorColor
        box.fillColor = NSColor.labelColor.withAlphaComponent(0.04)
        box.contentViewMargins = .zero
        box.contentView = stack
        return box
    }
}

/// A box that stretches across the stack view it is in.
private final class FullWidthBox: NSBox {
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let superview else { return }
        widthAnchor.constraint(equalTo: superview.widthAnchor).isActive = true
    }
}
