import AppKit

/// A small floating notice near the bottom of the screen. It never takes focus.
final class HUD {
    enum Message {
        case working
        case copied(String)
        case noText
        case failed(String)
    }

    private let panel = NSPanel(
        contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private let icon = NSImageView()
    private let spinner = NSProgressIndicator()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    /// Counts messages shown, so a pending dismissal can tell when a newer message has replaced its own.
    private var generation = 0
    /// Whether the "Reading text…" notice is the one on screen.
    private(set) var isShowingProgress = false

    init() {
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        // Panels hide while their app is inactive by default, and this app is never active.
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = makeContent()
    }

    func show(_ message: Message) {
        generation += 1
        let shown = generation
        isShowingProgress = false

        switch message {
        case .working:
            isShowingProgress = true
            set(symbol: nil, title: "Reading text…")
        case .copied(let text):
            // Show the start of the text on one line, however it was laid out.
            let preview = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            set(symbol: "checkmark.circle.fill", tint: .systemGreen, title: "Copied", detail: preview)
        case .noText:
            set(symbol: "text.magnifyingglass", title: "No text found")
        case .failed(let reason):
            set(symbol: "exclamationmark.triangle.fill", tint: .systemYellow, title: "Couldn’t read text", detail: reason)
        }

        placeOnScreen()
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        // The working notice stays until the result replaces it.
        if case .working = message { return }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard shown == generation else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }
            if shown == generation { panel.orderOut(nil) }
        }
    }

    /// Fills in the notice. A nil `symbol` shows the progress spinner instead of an icon.
    private func set(symbol: String?, tint: NSColor = .labelColor, title: String, detail: String = "") {
        icon.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        icon.contentTintColor = tint
        icon.isHidden = symbol == nil
        spinner.isHidden = symbol != nil
        if symbol == nil { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }

        self.title.stringValue = title
        self.detail.stringValue = detail
        self.detail.isHidden = detail.isEmpty
    }

    /// Sizes the panel to its content and centers it low on the screen the pointer is on.
    private func placeOnScreen() {
        guard let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize

        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let origin = CGPoint(x: area.midX - size.width / 2, y: area.minY + 96)
        panel.setFrame(NSRect(origin: origin, size: size).integral, display: true)
    }

    private func makeContent() -> NSView {
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        spinner.style = .spinning
        spinner.controlSize = .small
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail

        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.appearance = NSAppearance(named: .vibrantDark)
        background.maskImage = Self.roundedMask(radius: 14)
        for view in [icon, spinner, text] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        // The text sets the height; the icon and the spinner share one spot beside it.
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
            spinner.centerXAnchor.constraint(equalTo: icon.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            text.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -18),
            text.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
            text.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -12),
            detail.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
        ])
        return background
    }

    /// A stretchable rounded rectangle, used to clip the blurred background.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let mask = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        return mask
    }
}
