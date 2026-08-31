import AppKit

@MainActor enum Theme {
    static let paper = adaptive(light: 0xF7F6F2, dark: 0x171816)
    static let surface = adaptive(light: 0xEFEEE9, dark: 0x22231F)
    static let ink = adaptive(light: 0x171816, dark: 0xF7F6F2)
    static let muted = adaptive(light: 0x6F716C, dark: 0xA8AAA4)
    static let line = adaptive(light: 0xD7D6D0, dark: 0x393A36)
    static let active = adaptive(light: 0x2F6F50, dark: 0x68A884)
    static let attention = adaptive(light: 0x9A5B24, dark: 0xC98A4F)
    static let danger = adaptive(light: 0x9B3A34, dark: 0xE07870)
    static let radiusWindow: CGFloat = 22
    static let radiusControl: CGFloat = 8
    static let space: CGFloat = 4

    private static func adaptive(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in color(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light) }
    }
    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

private final class ResultPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
private final class ThemeFillView: NSView {
    let fillColor: NSColor
    let radius: CGFloat

    init(color: NSColor, radius: CGFloat = 0) {
        self.fillColor = color
        self.radius = radius
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fillColor.cgColor
        }
        layer?.cornerRadius = radius
        layer?.masksToBounds = radius > 0
    }
}

@MainActor final class ResultPanelController: NSObject, NSWindowDelegate {
    private let panel: ResultPanel
    private let commandLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "")
    private let textView = NSTextView()
    private let providerLabel = NSTextField(labelWithString: "")
    private var keyMonitor: Any?
    private let closesOnResign: Bool

    init(closesOnResign: Bool = true) {
        self.closesOnResign = closesOnResign
        panel = ResultPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 160), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.delegate = self; panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false; panel.hasShadow = false; panel.backgroundColor = .clear
        panel.isOpaque = false

        commandLabel.font = .systemFont(ofSize: 11, weight: .medium); commandLabel.textColor = Theme.muted
        statusLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium); statusLabel.alignment = .right
        let header = row([commandLabel, statusLabel], height: 22)

        sourceLabel.font = .systemFont(ofSize: 12); sourceLabel.textColor = Theme.muted; sourceLabel.alignment = .left; sourceLabel.lineBreakMode = .byTruncatingTail; sourceLabel.maximumNumberOfLines = 1
        sourceLabel.widthAnchor.constraint(equalToConstant: 388).isActive = true
        textView.isEditable = false; textView.isSelectable = true; textView.drawsBackground = false; textView.textContainerInset = .zero
        textView.font = .systemFont(ofSize: 15); textView.textColor = Theme.ink
        textView.textContainer?.lineFragmentPadding = 0
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 7.5
        textView.defaultParagraphStyle = paragraph
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.documentView = textView
        scroll.widthAnchor.constraint(equalToConstant: 388).isActive = true
        let body = NSStackView(views: [sourceLabel, scroll]); body.orientation = .vertical; body.alignment = .leading; body.spacing = 8; body.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let hints = NSTextField(labelWithString: "esc close   ⌘c copy"); hints.font = .monospacedSystemFont(ofSize: 10, weight: .regular); hints.textColor = Theme.muted
        providerLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular); providerLabel.textColor = Theme.muted; providerLabel.alignment = .right
        let footer = row([hints, providerLabel], height: 24)
        let stack = NSStackView(views: [header, divider(), body, divider(), footer]); stack.orientation = .vertical; stack.alignment = .width; stack.spacing = 0
        let background = ThemeFillView(color: Theme.paper, radius: Theme.radiusWindow)
        background.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: background.leadingAnchor), stack.trailingAnchor.constraint(equalTo: background.trailingAnchor), stack.topAnchor.constraint(equalTo: background.topAnchor), stack.bottomAnchor.constraint(equalTo: background.bottomAnchor)])
        panel.contentView = background
    }

    func showLoading(command: String, source: String, provider: String, model: String) {
        configure(command: command, source: source, provider: provider, model: model)
        statusLabel.stringValue = "working"; statusLabel.textColor = Theme.active; textView.string = ""; resizeAndShow()
    }

    func showResult(_ text: String) {
        statusLabel.stringValue = "done"; statusLabel.textColor = Theme.ink; setBody(text, color: Theme.ink, font: .systemFont(ofSize: 15)); resizeAndShow()
    }

    func showError(command: String = "yiyi", provider: String = "", model: String = "", message: String, detail: String? = nil) {
        configure(command: command, source: "", provider: provider, model: model)
        statusLabel.stringValue = "failed"; statusLabel.textColor = Theme.danger
        let value = detail.map { "\(message)\n\n\($0)" } ?? message
        setBody(value, color: Theme.danger, font: .systemFont(ofSize: 15)); resizeAndShow()
    }

    private func configure(command: String, source: String, provider: String, model: String) {
        commandLabel.stringValue = command.uppercased(); sourceLabel.stringValue = source.replacingOccurrences(of: "\n", with: " ")
        sourceLabel.isHidden = source.isEmpty; providerLabel.stringValue = [provider, model].filter { !$0.isEmpty }.joined(separator: "/")
    }
    private func setBody(_ text: String, color: NSColor, font: NSFont) {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 7.5
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]))
    }
    private func row(_ views: [NSView], height: CGFloat) -> NSView {
        let spacer = NSView()
        let row = NSStackView(views: [views[0], spacer, views[1]]); row.orientation = .horizontal; row.distribution = .fill; row.alignment = .centerY
        views[0].setContentHuggingPriority(.required, for: .horizontal); views[1].setContentHuggingPriority(.required, for: .horizontal)
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12); row.heightAnchor.constraint(equalToConstant: height).isActive = true
        return row
    }
    private func divider() -> NSView { let view = ThemeFillView(color: Theme.line); view.heightAnchor.constraint(equalToConstant: 1).isActive = true; return view }

    private func resizeAndShow() {
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let measured = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 24
        let sourceHeight: CGFloat = sourceLabel.isHidden ? 0 : 20
        let bodyHeight = min(292, max(48, measured + sourceHeight + 32))
        panel.setContentSize(NSSize(width: 420, height: 22 + 1 + bodyHeight + 1 + 24))
        let mouse = NSEvent.mouseLocation; let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        if let visibleFrame = screen?.visibleFrame {
            let safeFrame = visibleFrame.insetBy(dx: 16, dy: 16)
            let x = min(max(mouse.x - panel.frame.width / 2, safeFrame.minX), safeFrame.maxX - panel.frame.width)
            let y = min(max(mouse.y - panel.frame.height / 3, safeFrame.minY), safeFrame.maxY - panel.frame.height)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        NSApp.activate(ignoringOtherApps: true); panel.alphaValue = 0; panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { self?.panel.orderOut(nil); return nil }
                if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" { self?.copy(); return nil }
                return event
            }
        }
    }
    private func copy() { guard !textView.string.isEmpty else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(textView.string, forType: .string) }
    func windowDidResignKey(_ notification: Notification) { if closesOnResign { panel.orderOut(nil) } }
}
