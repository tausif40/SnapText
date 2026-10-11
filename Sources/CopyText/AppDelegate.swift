import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private lazy var hud = HUD()
    /// True while a capture or one of its alerts is in progress, so the shortcut cannot start a second one.
    private var isBusy = false

    private let captureItem = NSMenuItem(title: "Capture Text", action: #selector(captureText), keyEquivalent: "")
    private let lineBreaksItem = NSMenuItem(
        title: "Keep Line Breaks", action: #selector(toggleLineBreaks), keyEquivalent: "")
    private let shortcutItem = NSMenuItem(
        title: "Change Shortcut…", action: #selector(changeShortcut), keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(
        title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let coffeeItem = NSMenuItem(title: "Buy Me a Coffee", action: #selector(buyMeACoffee), keyEquivalent: "")

    /// The page where people can chip in towards the app's upkeep.
    private static let supportPage = URL(string: "https://tausif.info/OCRpay")!

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "CopyText")
        item.button?.toolTip = "CopyText"
        item.menu = makeMenu()
        statusItem = item

        listen(for: Preferences.shortcut)
        TextRecognizer.warmUp()
        showWelcomeIfNeeded()
        // Nothing works without Screen Recording permission, so ask on every launch that lacks it. macOS only
        // shows its prompt until the user has answered once; after that this keeps CopyText in its list.
        if !ScreenCapture.hasPermission {
            ScreenCapture.requestPermission()
        }
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
                // An instant copy needs no notice. One that kept the user waiting is confirmed.
                if hud.isShowingProgress {
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
        alert.messageText = "CopyText needs Screen Recording permission"
        alert.informativeText = """
            Turn on CopyText in System Settings → Privacy & Security → \(pane), then try again.

            If it is already on, quit CopyText and open it again.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let settings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(settings)
        }
    }

    private func showWelcomeIfNeeded() {
        guard !Preferences.hasShownWelcome else { return }
        Preferences.hasShownWelcome = true

        let alert = NSAlert()
        alert.messageText = "CopyText is ready"
        alert.informativeText = """
            Press \(Preferences.shortcut.title) and drag over any text on screen. The text is copied to the clipboard.

            CopyText lives in the menu bar, where you can change the shortcut.
            """
        if !ScreenCapture.hasPermission {
            alert.informativeText += """


                macOS will now ask for Screen Recording permission, which CopyText needs to see the text you select.
                """
        }

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Menu

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        for item in [captureItem, lineBreaksItem, shortcutItem, launchAtLoginItem, coffeeItem] {
            item.target = self
        }
        for item in [
            captureItem, .separator(), lineBreaksItem, shortcutItem, launchAtLoginItem, .separator(),
            coffeeItem, .separator(),
        ] {
            menu.addItem(item)
        }
        menu.addItem(withTitle: "Quit CopyText", action: #selector(NSApplication.terminate), keyEquivalent: "q")
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let shortcut = Preferences.shortcut
        captureItem.keyEquivalent = shortcut.key
        captureItem.keyEquivalentModifierMask = shortcut.modifiers
        lineBreaksItem.state = Preferences.keepLineBreaks ? .on : .off
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleLineBreaks() {
        Preferences.keepLineBreaks.toggle()
    }

    // MARK: - Shortcut

    /// Makes `shortcut` start a capture from anywhere. Returns false if the system refuses the combination.
    @discardableResult
    private func listen(for shortcut: Shortcut) -> Bool {
        GlobalHotKey.register(shortcut) { [weak self] in self?.captureText() }
    }

    @objc private func changeShortcut() {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        // Stop listening while the dialog is open, so the current shortcut can be pressed like any other.
        GlobalHotKey.unregister()
        let previous = Preferences.shortcut
        NSApp.activate(ignoringOtherApps: true)
        let chosen = ShortcutRecorder(current: previous).runModal() ?? previous

        if listen(for: chosen) {
            Preferences.shortcut = chosen
        } else {
            listen(for: previous)
            let alert = NSAlert()
            alert.messageText = "\(chosen.title) can’t be used as a shortcut"
            alert.informativeText = "macOS did not accept it. CopyText still uses \(previous.title)."
            alert.runModal()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    @objc private func buyMeACoffee() {
        NSWorkspace.shared.open(Self.supportPage)
    }
}
