import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private lazy var hud = HUD()
    /// True while a capture or one of its alerts is in progress, so the shortcut cannot start a second one.
    private var isBusy = false

    private lazy var history = ClipboardHistory(file: ClipboardHistory.standardFile, limit: Preferences.historyLimit)
    private lazy var clipboardWatcher = ClipboardWatcher(history: history)
    private lazy var mainWindow: MainWindow = {
        let window = MainWindow(history: history)
        window.onCapture = { [weak self] in self?.captureText() }
        window.onHistory = { [weak self] in self?.showHistory() }
        window.settings.onChangeShortcut = { [weak self] shortcut, purpose in self?.change(purpose, to: shortcut) }
        window.settings.onPauseShortcuts = { [weak self] paused in self?.pauseShortcuts(paused) }
        return window
    }()
    private lazy var historyPanel: HistoryPanel = {
        let panel = HistoryPanel(history: history)
        panel.onChoose = { [weak self] text in self?.useFromHistory(text) }
        panel.onChangeShortcut = { [weak self] shortcut, purpose in self?.change(purpose, to: shortcut) }
        panel.onPauseShortcuts = { [weak self] paused in self?.pauseShortcuts(paused) }
        return panel
    }()

    private let captureItem = NSMenuItem(title: "Capture Text", action: #selector(captureText), keyEquivalent: "")
    private let historyItem = NSMenuItem(
        title: "Clipboard History", action: #selector(showHistory), keyEquivalent: "")
    private let lineBreaksItem = NSMenuItem(
        title: "Keep Line Breaks", action: #selector(toggleLineBreaks), keyEquivalent: "")
    private let copiedNoticeItem = NSMenuItem(
        title: "Show Copied Notice", action: #selector(toggleCopiedNotice), keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
    private let launchAtLoginItem = NSMenuItem(
        title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let openItem = NSMenuItem(title: "Open SnapText", action: #selector(showMainWindow), keyEquivalent: "")
    private let coffeeItem = NSMenuItem(title: "Buy Me a Coffee", action: #selector(buyMeACoffee), keyEquivalent: "")

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "SnapText")
        item.button?.toolTip = "SnapText"
        item.menu = makeMenu()
        statusItem = item

        listenForShortcuts()
        clipboardWatcher.start()
        TextRecognizer.warmUp()
        // At login, SnapText starts quietly in the menu bar.
        if !wasLaunchedAtLogin {
            mainWindow.show()
        }
        // Nothing works without Screen Recording permission, so ask on every launch that lacks it. macOS only
        // shows its prompt until the user has answered once; after that this keeps SnapText in its list.
        if !ScreenCapture.hasPermission {
            ScreenCapture.requestPermission()
        }
    }

    /// Opening SnapText again while it runs, from Finder, Launchpad or Spotlight, shows its window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        ScreenCapture.cancelSelection()
    }

    // MARK: - Capturing

    @objc private func captureText() {
        guard !isBusy else { return }
        isBusy = true

        guard ScreenCapture.hasPermission else {
            askForScreenRecordingPermission()
            isBusy = false
            return
        }

        Task {
            defer { isBusy = false }
            do {
                guard let image = try await ScreenCapture.captureSelection() else { return }

                // Recognition is usually instant; only mention it when it is not.
                let notice = Task {
                    try await Task.sleep(for: .milliseconds(300))
                    try Task.checkCancellation()
                    hud.show(.working)
                }
                defer { notice.cancel() }

                let fragments = try await TextRecognizer.fragments(in: image)
                let text = TextLayout.text(from: fragments, keepLineBreaks: Preferences.keepLineBreaks)

                guard !text.isEmpty else {
                    hud.show(.noText)
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                // Confirm the copy if the user asked for that. One that kept them waiting is confirmed regardless,
                // since its "Reading text…" notice is still on screen.
                if Preferences.showCopiedNotice || hud.isShowingProgress {
                    hud.show(.copied(text))
                }
            } catch {
                hud.show(.failed(error.localizedDescription))
            }
        }
    }

    private func askForScreenRecordingPermission() {
        let pane = if #available(macOS 15, *) { "Screen & System Audio Recording" } else { "Screen Recording" }
        let alert = NSAlert()
        alert.messageText = "SnapText needs Screen Recording permission"
        alert.informativeText = """
            Turn on SnapText in System Settings → Privacy & Security → \(pane), then try again.

            If it is already on, an older copy of SnapText is the one allowed. Select SnapText in that list, \
            remove it with the − button, then quit SnapText and open it again.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(Constants.screenRecordingSettings)
        }
    }

    /// Whether macOS opened SnapText as a login item, rather than the user opening it.
    private var wasLaunchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    // MARK: - Clipboard history

    @objc private func showHistory() {
        guard !isBusy else { return }
        historyPanel.toggle()
    }

    /// Puts `text` on the clipboard, and pastes it if the user is typing in a text field.
    private func useFromHistory(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        if Preferences.pastesFromHistory {
            if Paster.isTypingInTextField {
                Paster.paste()
                return
            }
            // Ask once. The settings show how to allow it later.
            if !Paster.hasPermission, !Preferences.hasAskedToPaste {
                Preferences.hasAskedToPaste = true
                Paster.requestPermission()
            }
        }
        if Preferences.showCopiedNotice {
            hud.show(.copied(text))
        }
    }

    // MARK: - Menu

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        for item in [
            captureItem, historyItem, lineBreaksItem, copiedNoticeItem, settingsItem, launchAtLoginItem, openItem,
            coffeeItem,
        ] {
            item.target = self
        }
        for item in [
            captureItem, historyItem, .separator(), lineBreaksItem, copiedNoticeItem, settingsItem, launchAtLoginItem, .separator(),
            openItem, coffeeItem, .separator(),
        ] {
            menu.addItem(item)
        }
        menu.addItem(withTitle: "Quit SnapText", action: #selector(NSApplication.terminate), keyEquivalent: "q")
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let shortcut = Preferences.shortcut
        captureItem.keyEquivalent = shortcut.key
        captureItem.keyEquivalentModifierMask = shortcut.modifiers
        historyItem.keyEquivalent = Preferences.historyShortcut.key
        historyItem.keyEquivalentModifierMask = Preferences.historyShortcut.modifiers
        lineBreaksItem.state = Preferences.keepLineBreaks ? .on : .off
        copiedNoticeItem.state = Preferences.showCopiedNotice ? .on : .off
        launchAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func toggleLineBreaks() {
        Preferences.keepLineBreaks.toggle()
    }

    @objc private func toggleCopiedNotice() {
        Preferences.showCopiedNotice.toggle()
    }

    // MARK: - Shortcuts

    private func listenForShortcuts() {
        listen(for: Preferences.shortcut, to: .capture)
        listen(for: Preferences.historyShortcut, to: .history)
    }

    /// Makes `shortcut` do `purpose` from anywhere. Returns false if the system refuses the combination.
    @discardableResult
    private func listen(for shortcut: Shortcut, to purpose: GlobalHotKey.Purpose) -> Bool {
        GlobalHotKey.register(shortcut, for: purpose) { [weak self] in
            switch purpose {
            case .capture: self?.captureText()
            case .history: self?.showHistory()
            }
        }
    }

    /// Stops the shortcuts working while a new one is recorded, so the current ones can be pressed like any others.
    private func pauseShortcuts(_ paused: Bool) {
        if paused {
            GlobalHotKey.unregister(.capture)
            GlobalHotKey.unregister(.history)
        } else {
            listenForShortcuts()
        }
    }

    /// Makes `shortcut` do `purpose` from now on. Returns why it cannot, or nil once it does.
    private func change(_ purpose: GlobalHotKey.Purpose, to shortcut: Shortcut) -> String? {
        switch purpose {
        case .capture where shortcut == Preferences.historyShortcut:
            return "\(shortcut.title) already opens the clipboard history."
        case .history where shortcut == Preferences.shortcut:
            return "\(shortcut.title) already captures text."
        default:
            break
        }
        guard listen(for: shortcut, to: purpose) else { return "macOS did not accept \(shortcut.title). Try another." }
        switch purpose {
        case .capture: Preferences.shortcut = shortcut
        case .history: Preferences.historyShortcut = shortcut
        }
        return nil
    }

    @objc private func showMainWindow() {
        mainWindow.show()
    }

    @objc private func showSettings() {
        mainWindow.show(settings: true)
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
    }

    @objc private func buyMeACoffee() {
        NSWorkspace.shared.open(Constants.supportPage)
    }
}
