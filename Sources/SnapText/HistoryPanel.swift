import AppKit

/// The clipboard history popup: a searchable list of what the user copied, with the app's settings behind the
/// gear button. Picking an entry pastes it, and its copy button puts it back on the clipboard.
final class HistoryPanel: NSObject, NSWindowDelegate, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
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
    private let settings: SettingsView

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    init(history: ClipboardHistory) {
        self.history = history
        settings = SettingsView(history: history, width: 400, margin: 16)
        super.init()
        settings.onChangeShortcut = { [weak self] shortcut, purpose in self?.onChangeShortcut(shortcut, purpose) ?? nil }
        settings.onPauseShortcuts = { [weak self] paused in self?.onPauseShortcuts(paused) }
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

    var isVisible: Bool { panel.isVisible }

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
        settings.stopRecording()
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
        footer.stringValue = Preferences.keepsHistory
            ? "\(saved)  ·  ↩ to paste  ·  esc to close"
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
        reload()
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

    @objc private func closeClicked() {
        close()
    }

    private func showPage(settings showsSettings: Bool) {
        listPage.isHidden = showsSettings
        settingsPage.isHidden = !showsSettings
        settings.reset()
        if showsSettings {
            panel.makeFirstResponder(nil)
        } else {
            panel.makeFirstResponder(search)
        }
    }

    // MARK: - Layout

    private func makeContent() -> NSView {
        // The pages sit beside the background rather than in it, so its opacity leaves them alone.
        let content = NSView()
        let blur = NSVisualEffectView(frame: .zero)
        blur.material = .popover
        blur.state = .active
        blur.maskImage = HUD.roundedMask(radius: 12)
        blur.autoresizingMask = [.width, .height]
        // The blur always stays, like frosted glass. A solid fill over it fades in as the opacity goes up, so
        // at full opacity a white window behind no longer shows through.
        let fill = Backdrop(frame: .zero)
        fill.wantsLayer = true
        fill.autoresizingMask = [.width, .height]
        let background = NSView()
        background.addSubview(blur)
        background.addSubview(fill)
        fill.opacity = Preferences.historyOpacity
        NotificationCenter.default.addObserver(forName: .historyOpacityChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { fill.opacity = Preferences.historyOpacity }
        }
        for page in [background, listPage, settingsPage] {
            page.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(page)
            NSLayoutConstraint.activate([
                page.topAnchor.constraint(equalTo: content.topAnchor),
                page.bottomAnchor.constraint(equalTo: content.bottomAnchor),
                page.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            ])
        }
        buildList()
        buildSettings()
        return content
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
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [table] _ in
            MainActor.assumeIsolated {
                table.enumerateAvailableRowViews { row, _ in (row as? EntryRowView)?.updateHover() }
            }
        }

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
        let close = iconButton("xmark", label: "Close", action: #selector(closeClicked))
        let title = NSTextField(labelWithString: "Settings")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let line = NSBox()
        line.boxType = .separator

        // The settings are taller than the panel, so they scroll.
        let scroll = NSScrollView()
        scroll.documentView = settings
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        for view in [back, close, title, line, scroll, settings] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        for view in [back, close, title, line, scroll] {
            settingsPage.addSubview(view)
        }
        NSLayoutConstraint.activate([
            back.topAnchor.constraint(equalTo: settingsPage.topAnchor, constant: 12),
            back.leadingAnchor.constraint(equalTo: settingsPage.leadingAnchor, constant: 10),
            back.widthAnchor.constraint(equalToConstant: 24),
            back.heightAnchor.constraint(equalToConstant: 24),
            close.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: settingsPage.trailingAnchor, constant: -10),
            close.widthAnchor.constraint(equalToConstant: 24),
            close.heightAnchor.constraint(equalToConstant: 24),
            title.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            title.centerXAnchor.constraint(equalTo: settingsPage.centerXAnchor),
            line.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 10),
            line.leadingAnchor.constraint(equalTo: settingsPage.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: settingsPage.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: line.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: settingsPage.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: settingsPage.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: settingsPage.bottomAnchor),
            settings.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            settings.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            settings.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
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

/// The popup's background colour over the blur, with rounded corners and a hairline edge that keeps it apart
/// from what is behind it.
private final class Backdrop: NSView {
    /// The popup opacity setting. At its lowest the colour is gone and only the blur shows.
    var opacity = 1.0 {
        didSet { needsDisplay = true }
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = 12
        layer.borderWidth = 1
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let range = Preferences.historyOpacityRange
            let share = (opacity - range.lowerBound) / (range.upperBound - range.lowerBound)
            layer.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92 * share).cgColor
            layer.borderColor = NSColor.separatorColor.cgColor
        }
    }
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
        updateHover()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    /// Scrolling moves rows under a still pointer without telling them, and reuses them for other copies,
    /// so a row checks where the pointer is whenever its visible part changes.
    func updateHover() {
        guard let window else { return isHovered = false }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        isHovered = visibleRect.contains(point)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
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
