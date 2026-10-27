import AppKit

/// The window that opens when the user opens SnapText. Its Home tab shows the shortcuts, the permissions SnapText
/// has, a way to support it and who made it; its Settings tab holds every setting. SnapText keeps running in the
/// menu bar once it is closed.
final class MainWindow: NSObject, NSWindowDelegate {
    private static let width: CGFloat = 440

    var onCapture: () -> Void = {}
    var onHistory: () -> Void = {}

    private let window = CommandWWindow(
        contentRect: NSRect(x: 0, y: 0, width: MainWindow.width, height: 600),
        styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: true)

    private let tabs = NSSegmentedControl(labels: ["Home", "Settings"], trackingMode: .selectOne, target: nil, action: nil)
    private let homePage = NSView()
    private let settingsPage = NSScrollView()
    let settings: SettingsView

    private let captureShortcut = MainWindow.shortcutLabel()
    private let historyShortcut = MainWindow.shortcutLabel()
    private let screenRecordingStatus = PermissionStatus()
    private let accessibilityStatus = PermissionStatus()

    init(history: ClipboardHistory) {
        settings = SettingsView(history: history, width: Self.width, margin: 24)
        super.init()
        window.title = "SnapText"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = makeContent()
        // As tall as the Home tab needs. The settings scroll within the same size.
        window.setContentSize(NSSize(width: Self.width, height: window.contentView!.fittingSize.height))
        window.center()
    }

    func show(settings showsSettings: Bool = false) {
        tabs.selectedSegment = showsSettings ? 1 : 0
        showTab()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Permissions may have changed in System Settings while the window was in the background.
    func windowDidBecomeKey(_ notification: Notification) {
        update()
        settings.update()
    }

    func windowWillClose(_ notification: Notification) {
        settings.stopRecording()
    }

    private func update() {
        captureShortcut.stringValue = Preferences.shortcut.title
        historyShortcut.stringValue = Preferences.historyShortcut.title
        screenRecordingStatus.isAllowed = ScreenCapture.hasPermission
        accessibilityStatus.isAllowed = Paster.hasPermission
    }

    @objc private func showTab() {
        let showsSettings = tabs.selectedSegment == 1
        homePage.isHidden = showsSettings
        settingsPage.isHidden = !showsSettings
        settings.reset()
        update()
    }

    // MARK: - Actions

    @objc private func captureClicked() {
        // Out of the way of the text the user wants to capture.
        window.orderOut(nil)
        onCapture()
    }

    @objc private func historyClicked() {
        onHistory()
    }

    @objc private func allowScreenRecordingClicked() {
        ScreenCapture.requestPermission()
        NSWorkspace.shared.open(Constants.screenRecordingSettings)
    }

    @objc private func allowAccessibilityClicked() {
        Paster.requestPermission()
        NSWorkspace.shared.open(Constants.accessibilitySettings)
    }

    @objc private func coffeeClicked() {
        NSWorkspace.shared.open(Constants.supportPage)
    }

    @objc private func emailClicked() {
        if let mail = URL(string: "mailto:\(Constants.developerEmail)") { NSWorkspace.shared.open(mail) }
    }

    @objc private func portfolioClicked() {
        NSWorkspace.shared.open(Constants.portfolio)
    }

    // MARK: - Layout

    private func makeContent() -> NSView {
        tabs.target = self
        tabs.action = #selector(showTab)
        tabs.selectedSegment = 0
        buildHome()

        settingsPage.documentView = settings
        settingsPage.hasVerticalScroller = true
        settingsPage.autohidesScrollers = true
        settingsPage.drawsBackground = false

        let root = NSView()
        for view in [tabs, homePage, settingsPage, settings] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        for view in [tabs, homePage, settingsPage] {
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: root.topAnchor, constant: 36),
            tabs.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            tabs.widthAnchor.constraint(equalToConstant: 200),
            homePage.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 18),
            homePage.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            homePage.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            homePage.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            settingsPage.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 8),
            settingsPage.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            settingsPage.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            settingsPage.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            settings.topAnchor.constraint(equalTo: settingsPage.contentView.topAnchor),
            settings.leadingAnchor.constraint(equalTo: settingsPage.contentView.leadingAnchor),
            settings.widthAnchor.constraint(equalTo: settingsPage.contentView.widthAnchor),
        ])
        return root
    }

    private func buildHome() {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        let name = NSTextField(labelWithString: "SnapText")
        name.font = .systemFont(ofSize: 20, weight: .bold)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .tertiaryLabelColor
        let tagline = NSTextField(labelWithString: "Copy text from anywhere on your screen.")
        tagline.font = .systemFont(ofSize: 12)
        tagline.textColor = .secondaryLabelColor
        let titles = NSStackView(views: [name, tagline, versionLabel])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2
        let header = NSStackView(views: [icon, titles])
        header.spacing = 14

        let shortcuts = Groups.box([
            Self.row(
                symbol: "text.viewfinder", title: "Capture Text", detail: "Drag over text on screen to copy it.",
                trailing: [captureShortcut, button("Capture", action: #selector(captureClicked))]),
            Self.row(
                symbol: "clock.arrow.circlepath", title: "Clipboard History",
                detail: "Find and paste something you copied.",
                trailing: [historyShortcut, button("Open", action: #selector(historyClicked))]),
        ])

        screenRecordingStatus.allowButton.target = self
        screenRecordingStatus.allowButton.action = #selector(allowScreenRecordingClicked)
        accessibilityStatus.allowButton.target = self
        accessibilityStatus.allowButton.action = #selector(allowAccessibilityClicked)
        let permissions = Groups.box([
            Self.row(
                symbol: "rectangle.dashed.badge.record", title: "Screen Recording",
                detail: "Needed to extract text from the screen.", trailing: [screenRecordingStatus]),
            Self.row(
                symbol: "accessibility", title: "Accessibility",
                detail: "Needed to paste from the clipboard history.", trailing: [accessibilityStatus]),
        ])

        let support = Groups.box([
            Self.row(
                symbol: "cup.and.saucer.fill", tint: .systemOrange, title: "Buy Me a Coffee",
                detail: "Enjoying SnapText? Support its upkeep.",
                trailing: [button("Support", action: #selector(coffeeClicked))]),
        ])

        let content = NSStackView(views: [
            header, Groups.heading("Shortcuts"), shortcuts, Groups.heading("Permissions"), permissions, support,
            makeDeveloper(),
        ])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        content.setCustomSpacing(20, after: header)
        content.setCustomSpacing(18, after: shortcuts)
        content.setCustomSpacing(18, after: permissions)
        content.setCustomSpacing(18, after: support)
        let developer = content.arrangedSubviews.last!

        content.translatesAutoresizingMaskIntoConstraints = false
        homePage.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: homePage.topAnchor),
            content.leadingAnchor.constraint(equalTo: homePage.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: homePage.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: homePage.bottomAnchor),
            developer.widthAnchor.constraint(equalTo: content.widthAnchor),
            icon.widthAnchor.constraint(equalToConstant: 60),
            icon.heightAnchor.constraint(equalToConstant: 60),
        ])
    }

    /// Who made SnapText, and how to reach them.
    private func makeDeveloper() -> NSView {
        let label = NSTextField(labelWithString: "Developed by \(Constants.developerName)")
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        let links = NSStackView(views: [
            link(Constants.developerEmail, symbol: "envelope", action: #selector(emailClicked)),
            link(Constants.portfolio.host() ?? Constants.portfolio.absoluteString, symbol: "globe",
                 action: #selector(portfolioClicked)),
        ])
        links.spacing = 16
        let developer = NSStackView(views: [label, links])
        developer.orientation = .vertical
        developer.spacing = 4
        return developer
    }

    private func link(_ title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.contentTintColor = .linkColor
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.linkColor, .font: NSFont.systemFont(ofSize: 12),
        ])
        return button
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        // The same width for each, so the shortcuts beside them line up.
        button.widthAnchor.constraint(equalToConstant: 84).isActive = true
        return button
    }

    private static func shortcutLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    /// A symbol, a title with a line about it underneath, and whatever goes at the end.
    private static func row(
        symbol: String, tint: NSColor = .controlAccentColor, title: String, detail: String, trailing: [NSView]
    ) -> NSView {
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        image.contentTintColor = tint
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let text = NSStackView(views: [titleLabel, detailLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        text.setHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [image] + [text] + trailing)
        // The text takes the spare width, which lines up what follows it at the far end.
        row.distribution = .fill
        row.spacing = 10
        row.setCustomSpacing(12, after: image)
        row.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        image.widthAnchor.constraint(equalToConstant: 24).isActive = true
        return row
    }
}

/// Shows that a permission is allowed, or offers to allow it.
private final class PermissionStatus: NSStackView {
    let allowButton = NSButton(title: "Allow…", target: nil, action: nil)
    private let allowed = NSStackView()

    var isAllowed = false {
        didSet {
            allowed.isHidden = !isAllowed
            allowButton.isHidden = isAllowed
        }
    }

    init() {
        super.init(frame: .zero)
        let tick = NSImageView(image: NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)!)
        tick.contentTintColor = .systemGreen
        let label = NSTextField(labelWithString: "Allowed")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        allowed.setViews([tick, label], in: .leading)
        allowed.spacing = 4
        allowButton.bezelStyle = .rounded
        setViews([allowed, allowButton], in: .trailing)
        // Only as wide as what it shows, so that sits at the end of the row.
        for stack in [self, allowed] {
            stack.setHuggingPriority(.required, for: .horizontal)
        }
        for view in [tick, label] {
            view.setContentHuggingPriority(.required, for: .horizontal)
        }
        isAllowed = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// A window that closes on ⌘W. SnapText has no menu bar of its own to provide that.
private final class CommandWWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
