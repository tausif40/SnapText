import AppKit

/// The clipboard history popup: a searchable list of what the user copied, with the app's settings behind the
/// gear button. Picking an entry pastes it, and its copy button puts it back on the clipboard.
final class HistoryPanel: NSObject, NSWindowDelegate, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static let copiesRange = 1...ClipboardHistory.capacity
    private static let daysRange = 1...365

    private let history: ClipboardHistory
    /// Called with the text of the entry the user picks.
    var onChoose: (String) -> Void = { _ in }
    /// Makes a shortcut do something. Returns why it cannot, or nil once it does.
    var onChangeShortcut: (Shortcut, GlobalHotKey.Purpose) -> String? = { _, _ in nil }
    /// Called with true while a new shortcut is being recorded, when the current ones must not work, and false after.
    var onPauseShortcuts: (Bool) -> Void = { _ in }
    private let panel = KeyPanel(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 460), styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered, defer: true)

    private let listPage = NSView()
    private let search = NSSearchField()
    private let table = NSTableView()
    private let emptyNote = NSTextField(labelWithString: "")
    private let footer = NSTextField(labelWithString: "")
    /// The entries the list shows: those matching the search.
    private var shown: [ClipboardEntry] = []

    private let settingsPage = NSView()
    private let settingsGrid = NSGridView()
    private let historyShortcut = ShortcutField(shortcut: Preferences.historyShortcut)
    private let historyShortcutMessage = NSTextField(wrappingLabelWithString: "")
    private let keepSwitch = NSSwitch()
    private let pasteSwitch = NSSwitch()
    /// Explains that pasting needs Accessibility permission, while it is missing.
    private let permissionNote = NSStackView()
    private let limitKind = NSPopUpButton()
    private let limitField = NSTextField()
    private let limitStepper = NSStepper()
    private let limitUnit = NSTextField(labelWithString: "")
    private let limitWarning = NSTextField(wrappingLabelWithString: "")
    private let defaultLimitButton = NSButton()
    private let clearButton = NSButton()
    private let captureShortcut = ShortcutField(shortcut: Preferences.shortcut)
    private let captureShortcutMessage = NSTextField(wrappingLabelWithString: "")
    private let lineBreaksSwitch = NSSwitch()
    private let noticeSwitch = NSSwitch()
    /// Whether the clear button has been clicked once and waits for the second click that confirms it.
    private var isConfirmingClear = false

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    init(history: ClipboardHistory) {
        self.history = history
        super.init()
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Dragging any empty part of it moves it, such as the space around the search field.
        panel.isMovableByWindowBackground = true
        // Panels hide while their app is inactive by default, and this app is never active.
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.cancel() }
        panel.contentView = makeContent()
    }

    func toggle() {
        if panel.isVisible { close() } else { show() }
    }

    func show(settings: Bool = false) {
        history.prune()
        search.stringValue = ""
        showPage(settings: settings)
        reload()
        placeOnScreen()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(search)
    }

    func close() {
        stopRecording()
        panel.orderOut(nil)
    }

    /// Escape leaves the settings, or else closes the panel.
    private func cancel() {
        if settingsPage.isHidden { close() } else { closeSettings() }
    }

    /// Clicking anywhere outside the panel closes it.
    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    /// Remembers where the user drags the panel to.
    func windowDidMove(_ notification: Notification) {
        if !isPlacing { Preferences.historyWindowOrigin = panel.frame.origin }
    }

    /// True while the panel is being put in place, rather than moved by the user.
    private var isPlacing = false

    /// Puts the panel where the user last dragged it, if that is still on a screen. Otherwise centers it a little
    /// above the middle of the screen the pointer is on.
    private func placeOnScreen() {
        isPlacing = true
        defer { isPlacing = false }
        if let origin = Preferences.historyWindowOrigin,
           NSScreen.screens.contains(where: { $0.visibleFrame.contains(NSRect(origin: origin, size: panel.frame.size)) }) {
            panel.setFrameOrigin(origin)
            return
        }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2 + area.height / 10)
        panel.setFrameOrigin(CGPoint(x: origin.x.rounded(), y: max(origin.y, area.minY).rounded()))
    }

    // MARK: - The list

    private func reload() {
        shown = history.entries(matching: search.stringValue)
        table.reloadData()
        if !shown.isEmpty {
            table.selectRowIndexes([0], byExtendingSelection: false)
            table.scrollRowToVisible(0)
        }
        emptyNote.stringValue = history.entries.isEmpty ? "Nothing copied yet" : "No matches"
        emptyNote.isHidden = !shown.isEmpty

        let count = history.entries.count
        let saved = count == 1 ? "1 copy" : "\(count.formatted()) copies"
        let use = Preferences.pastesFromHistory ? "↩ to paste" : "↩ to copy"
        footer.stringValue = Preferences.keepsHistory
            ? "\(saved)  ·  \(use)  ·  esc to close"
            : "History is off. Turn it on in Settings."
    }

    private func moveSelection(by step: Int) {
        guard !shown.isEmpty else { return }
        let row = min(max(table.selectedRow + step, 0), shown.count - 1)
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    private func choose(_ row: Int) {
        guard shown.indices.contains(row) else { return }
        close()
        onChoose(shown[row].text)
    }

    @objc private func rowClicked() {
        choose(table.clickedRow)
    }

    /// Puts the entry back on the clipboard, and keeps the list open.
    @objc private func copyClicked(_ sender: NSButton) {
        let row = table.row(for: sender)
        guard shown.indices.contains(row) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shown[row].text, forType: .string)
        (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? EntryCell)?.showCopied()
    }

    @objc private func deleteClicked() {
        guard shown.indices.contains(table.clickedRow) else { return }
        history.remove(shown[table.clickedRow])
        reload()
    }

    func controlTextDidChange(_ notification: Notification) {
        if notification.object as? NSTextField === limitField {
            // Say so while the user types it, before the value is cut down to the most there can be.
            let typed = Int(limitField.stringValue.filter(\.isNumber)) ?? 0
            showLimitWarning(typed > limitRange.upperBound)
        } else {
            reload()
        }
    }

    /// The search field keeps the focus, so it passes on the keys that work the list.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === search else { return false }
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
        case #selector(NSResponder.insertNewline(_:)):
            choose(table.selectedRow)
        case #selector(NSResponder.cancelOperation(_:)):
            if search.stringValue.isEmpty {
                close()
            } else {
                search.stringValue = ""
                reload()
            }
        default:
            return false
        }
        return true
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        shown.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        EntryRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: EntryCell.identifier, owner: nil) as? EntryCell ?? EntryCell()
        cell.copyButton.target = self
        cell.copyButton.action = #selector(copyClicked)
        let entry = shown[row]
        cell.show(entry.text, copiedAt: dateFormatter.string(from: entry.date))
        return cell
    }

    // MARK: - Settings

    @objc private func openSettings() {
        showPage(settings: true)
    }

    @objc private func closeSettings() {
        showPage(settings: false)
        reload()
    }

    private func showPage(settings: Bool) {
        listPage.isHidden = settings
        settingsPage.isHidden = !settings
        isConfirmingClear = false
        stopRecording()
        showLimitWarning(false)
        if settings {
            updateSettings()
            panel.makeFirstResponder(nil)
        } else {
            panel.makeFirstResponder(search)
        }
    }

    private var limitRange: ClosedRange<Int> {
        Preferences.limitsHistoryByDays ? Self.daysRange : Self.copiesRange
    }

    @objc private func keepChanged() {
        Preferences.keepsHistory = keepSwitch.state == .on
        updateSettings()
    }

    @objc private func pasteChanged() {
        Preferences.pastesFromHistory = pasteSwitch.state == .on
        if Preferences.pastesFromHistory, !Paster.hasPermission {
            Preferences.hasAskedToPaste = true
            Paster.requestPermission()
        }
        updateSettings()
    }

    @objc private func allowPastingClicked() {
        close()
        Paster.requestPermission()
        if let settings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(settings)
        }
    }

    @objc private func limitKindChanged() {
        Preferences.limitsHistoryByDays = limitKind.indexOfSelectedItem == 1
        showLimitWarning(false)
        applyLimit()
    }

    @objc private func limitValueChanged(_ sender: NSControl) {
        // Anything that is not a whole number puts back the value there was, rather than deleting copies.
        let typed = sender === limitStepper ? limitStepper.integerValue : Int(limitField.stringValue.filter(\.isNumber))
        guard let typed, typed > 0 else { return updateSettings() }

        let range = limitRange
        showLimitWarning(typed > range.upperBound)
        let value = min(typed, range.upperBound)
        if Preferences.limitsHistoryByDays { Preferences.historyDays = value } else { Preferences.historyCopies = value }
        applyLimit()
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
        updateSettings()
    }

    private func showLimitWarning(_ isShown: Bool) {
        limitWarning.stringValue = Preferences.limitsHistoryByDays
            ? "You can’t keep more than \(Self.daysRange.upperBound) days."
            : "You can’t save more than \(ClipboardHistory.capacity.formatted()) copies."
        show(limitWarning, isShown)
    }

    @objc private func clearClicked() {
        if isConfirmingClear { history.removeAll() }
        isConfirmingClear.toggle()
        updateSettings()
    }

    @objc private func lineBreaksChanged() {
        Preferences.keepLineBreaks = lineBreaksSwitch.state == .on
    }

    @objc private func noticeChanged() {
        Preferences.showCopiedNotice = noticeSwitch.state == .on
    }

    /// Sets up a shortcut field to change the shortcut for `purpose`, with `message` below it for its hints.
    private func connect(_ field: ShortcutField, to purpose: GlobalHotKey.Purpose, message: NSTextField) {
        field.onRecord = { [weak self] shortcut in self?.onChangeShortcut(shortcut, purpose) ?? nil }
        field.onMessage = { [weak self] text in
            message.stringValue = text ?? ""
            self?.show(message, text != nil)
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

    private func stopRecording() {
        historyShortcut.stopRecording()
        captureShortcut.stopRecording()
    }

    /// Shows or hides the row of the settings that holds `view`.
    private func show(_ view: NSView, _ isShown: Bool) {
        settingsGrid.cell(for: view)?.row?.isHidden = !isShown
    }

    private func updateSettings() {
        let byDays = Preferences.limitsHistoryByDays
        let range = limitRange
        let value = byDays ? Preferences.historyDays : Preferences.historyCopies

        historyShortcut.show(Preferences.historyShortcut)
        keepSwitch.state = Preferences.keepsHistory ? .on : .off
        pasteSwitch.state = Preferences.pastesFromHistory ? .on : .off
        show(permissionNote, Preferences.pastesFromHistory && !Paster.hasPermission)
        limitKind.selectItem(at: byDays ? 1 : 0)
        limitField.integerValue = value
        limitStepper.minValue = Double(range.lowerBound)
        limitStepper.maxValue = Double(range.upperBound)
        limitStepper.integerValue = value
        limitUnit.stringValue = byDays ? (value == 1 ? "day" : "days") : (value == 1 ? "copy" : "copies")
        let defaultValue = byDays ? Preferences.defaultHistoryDays : Preferences.defaultHistoryCopies
        defaultLimitButton.title = "Use the Default, \(defaultValue) \(byDays ? "Days" : "Copies")"
        show(defaultLimitButton, value != defaultValue)

        let count = history.entries.count
        clearButton.title = isConfirmingClear
            ? "Click Again to Delete \(count == 1 ? "1 Copy" : "\(count.formatted()) Copies")"
            : "Clear History"
        clearButton.isEnabled = count > 0

        captureShortcut.show(Preferences.shortcut)
        lineBreaksSwitch.state = Preferences.keepLineBreaks ? .on : .off
        noticeSwitch.state = Preferences.showCopiedNotice ? .on : .off
    }

    // MARK: - Layout

    private func makeContent() -> NSView {
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.maskImage = HUD.roundedMask(radius: 12)
        for page in [listPage, settingsPage] {
            page.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(page)
            NSLayoutConstraint.activate([
                page.topAnchor.constraint(equalTo: background.topAnchor),
                page.bottomAnchor.constraint(equalTo: background.bottomAnchor),
                page.leadingAnchor.constraint(equalTo: background.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            ])
        }
        buildList()
        buildSettings()
        return background
    }

    private func buildList() {
        search.placeholderString = "Search copies"
        search.controlSize = .large
        search.font = .systemFont(ofSize: 14)
        search.focusRingType = .none
        search.delegate = self
        let gear = iconButton("gearshape", label: "Settings", action: #selector(openSettings))

        let menu = NSMenu()
        menu.addItem(withTitle: "Delete", action: #selector(deleteClicked), keyEquivalent: "").target = self

        let column = NSTableColumn(identifier: EntryCell.identifier)
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.headerView = nil
        table.style = .inset
        table.rowHeight = 40
        table.backgroundColor = .clear
        // The search field keeps the focus, and passes the arrow keys on.
        table.refusesFirstResponder = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        table.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        emptyNote.font = .systemFont(ofSize: 13)
        emptyNote.textColor = .secondaryLabelColor
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .secondaryLabelColor
        footer.lineBreakMode = .byTruncatingTail
        let line = NSBox()
        line.boxType = .separator

        for view in [search, gear, line, scroll, emptyNote, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            listPage.addSubview(view)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: listPage.topAnchor, constant: 12),
            search.leadingAnchor.constraint(equalTo: listPage.leadingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: gear.leadingAnchor, constant: -8),
            gear.trailingAnchor.constraint(equalTo: listPage.trailingAnchor, constant: -12),
            gear.centerYAnchor.constraint(equalTo: search.centerYAnchor),
            gear.widthAnchor.constraint(equalToConstant: 24),
            gear.heightAnchor.constraint(equalToConstant: 24),
            line.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10),
            line.leadingAnchor.constraint(equalTo: listPage.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: listPage.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: line.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: listPage.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: listPage.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -6),
            emptyNote.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyNote.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            footer.leadingAnchor.constraint(equalTo: listPage.leadingAnchor, constant: 14),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: listPage.trailingAnchor, constant: -14),
            footer.bottomAnchor.constraint(equalTo: listPage.bottomAnchor, constant: -8),
        ])
    }

    private func buildSettings() {
        let back = iconButton("chevron.left", label: "Back", action: #selector(closeSettings))
        let title = NSTextField(labelWithString: "Settings")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let line = NSBox()
        line.boxType = .separator

        for (control, action) in [
            (keepSwitch, #selector(keepChanged)), (pasteSwitch, #selector(pasteChanged)),
            (lineBreaksSwitch, #selector(lineBreaksChanged)), (noticeSwitch, #selector(noticeChanged)),
        ] {
            control.target = self
            control.action = action
        }
        connect(historyShortcut, to: .history, message: historyShortcutMessage)
        connect(captureShortcut, to: .capture, message: captureShortcutMessage)

        let permissionText = NSTextField(wrappingLabelWithString: "Pasting needs Accessibility permission.")
        let allowButton = NSButton(title: "Allow in System Settings", target: self, action: #selector(allowPastingClicked))
        allowButton.controlSize = .small
        allowButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
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
        clearButton.bezelStyle = .rounded
        clearButton.hasDestructiveAction = true
        clearButton.target = self
        clearButton.action = #selector(clearClicked)

        let note = NSTextField(wrappingLabelWithString: """
            SnapText keeps at most \(ClipboardHistory.capacity.formatted()) copies, on this Mac only. \
            Lowering the limit deletes the older copies straight away. Copies that password managers mark \
            as private are never saved.
            """)

        for message in [permissionText, historyShortcutMessage, limitWarning, captureShortcutMessage, note] {
            message.font = .systemFont(ofSize: 11)
            if message !== limitWarning { message.textColor = .secondaryLabelColor }
        }
        for message in [permissionText, historyShortcutMessage, limitWarning, captureShortcutMessage] {
            message.preferredMaxLayoutWidth = 190
        }
        note.preferredMaxLayoutWidth = 330

        let value = NSStackView(views: [limitField, limitStepper, limitUnit])
        value.spacing = 4
        let historyHeading = Self.heading("Clipboard History")
        let captureHeading = Self.heading("Capture Text")
        let none = NSGridCell.emptyContentView
        let grid = settingsGrid
        for row in [
            [historyHeading],
            [Self.label("Shortcut"), historyShortcut],
            [none, historyShortcutMessage],
            [Self.label("Save history"), keepSwitch],
            [Self.label("Paste into text fields"), pasteSwitch],
            [none, permissionNote],
            [Self.label("Limit by"), limitKind],
            [Self.label("Keep the last"), value],
            [none, limitWarning],
            [none, defaultLimitButton],
            [note],
            [clearButton],
            [captureHeading],
            [Self.label("Shortcut"), captureShortcut],
            [none, captureShortcutMessage],
            [Self.label("Keep line breaks"), lineBreaksSwitch],
            [Self.label("Show copied notice"), noticeSwitch],
        ] {
            grid.addRow(with: row)
        }
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.yPlacement = .center
        grid.column(at: 0).xPlacement = .trailing
        // Headings, the note and the button run across both columns.
        for view in [historyHeading, captureHeading, note, clearButton] {
            guard let row = grid.cell(for: view)?.row else { continue }
            row.mergeCells(in: NSRange(location: 0, length: 2))
            row.cell(at: 0).xPlacement = view === clearButton ? .center : .leading
        }
        grid.cell(for: captureHeading)?.row?.topPadding = 14
        grid.cell(for: historyShortcutMessage)?.row?.topPadding = -4
        grid.cell(for: captureShortcutMessage)?.row?.topPadding = -4
        grid.cell(for: limitWarning)?.row?.topPadding = -4
        grid.cell(for: defaultLimitButton)?.row?.topPadding = -4
        for message in [historyShortcutMessage, permissionNote, limitWarning, captureShortcutMessage] {
            show(message, false)
        }

        // The settings are taller than the panel, so they scroll.
        let content = FlippedView()
        content.addSubview(grid)
        let scroll = NSScrollView()
        scroll.documentView = content
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        for view in [back, title, line, scroll, content, grid] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        for view in [back, title, line, scroll] {
            settingsPage.addSubview(view)
        }
        NSLayoutConstraint.activate([
            back.topAnchor.constraint(equalTo: settingsPage.topAnchor, constant: 12),
            back.leadingAnchor.constraint(equalTo: settingsPage.leadingAnchor, constant: 10),
            back.widthAnchor.constraint(equalToConstant: 24),
            back.heightAnchor.constraint(equalToConstant: 24),
            title.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            title.centerXAnchor.constraint(equalTo: settingsPage.centerXAnchor),
            line.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 10),
            line.leadingAnchor.constraint(equalTo: settingsPage.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: settingsPage.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: line.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: settingsPage.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: settingsPage.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: settingsPage.bottomAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            content.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            grid.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            limitField.widthAnchor.constraint(equalToConstant: 56),
            historyShortcut.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            captureShortcut.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
        ])
    }

    private func iconButton(_ symbol: String, label: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = label
        button.target = self
        button.action = action
        return button
    }

    private static func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    private static func heading(_ text: String) -> NSTextField {
        let heading = NSTextField(labelWithString: text)
        heading.font = .systemFont(ofSize: 12, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        return heading
    }
}

/// A panel that takes key presses without making SnapText the active app, so the app the user was in stays
/// in front, ready to paste into.
private final class KeyPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Lays out its subviews from the top, as a scrolling page of settings reads.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A row that stays blue when selected, although the search field has the focus rather than the list, and
/// lights up under the pointer.
private final class EntryRowView: NSTableRowView {
    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    override var isEmphasized: Bool {
        get { true }
        set {}
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        // Always active, since SnapText is never the active app.
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard isHovered, !isSelected else { return }
        NSColor.labelColor.withAlphaComponent(0.07).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 10, dy: 0), xRadius: 6, yRadius: 6).fill()
    }
}

/// A row of the list: the start of the copied text on one line, when it was copied, and a button that copies it.
private final class EntryCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("entry")

    let copyButton = NSButton()
    private let preview = NSTextField(labelWithString: "")
    private let date = NSTextField(labelWithString: "")
    private var isShowingCopied = false
    private var copiedTimer: Timer?

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        preview.font = .systemFont(ofSize: 13)
        preview.lineBreakMode = .byTruncatingTail
        preview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        date.font = .systemFont(ofSize: 11)
        date.textColor = .secondaryLabelColor
        copyButton.isBordered = false
        copyButton.imagePosition = .imageOnly
        copyButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        copyButton.toolTip = "Copy"
        copyButton.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [preview, date])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        for view in [stack, copyButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            copyButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            copyButton.widthAnchor.constraint(equalToConstant: 24),
            copyButton.heightAnchor.constraint(equalToConstant: 24),
        ])
        updateCopyButton()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateColors() }
    }

    func show(_ text: String, copiedAt date: String) {
        // Show the start of the text on one line, however it was laid out.
        preview.stringValue = text.prefix(300).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        toolTip = String(text.prefix(1000))
        self.date.stringValue = date
        setShowingCopied(false)
    }

    /// Turns the copy button into a tick for a moment.
    func showCopied() {
        setShowingCopied(true)
        let timer = Timer(timeInterval: 1.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.setShowingCopied(false) }
        }
        RunLoop.main.add(timer, forMode: .common)
        copiedTimer = timer
    }

    private func setShowingCopied(_ isShowing: Bool) {
        copiedTimer?.invalidate()
        copiedTimer = nil
        isShowingCopied = isShowing
        updateCopyButton()
    }

    private func updateCopyButton() {
        copyButton.image = isShowingCopied
            ? NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Copied")
            : NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
        updateColors()
    }

    private func updateColors() {
        let selected = backgroundStyle == .emphasized
        preview.textColor = selected ? .alternateSelectedControlTextColor : .labelColor
        date.textColor = selected ? .alternateSelectedControlTextColor.withAlphaComponent(0.75) : .secondaryLabelColor
        copyButton.contentTintColor = selected
            ? .alternateSelectedControlTextColor
            : isShowingCopied ? .systemGreen : .secondaryLabelColor
    }
}
