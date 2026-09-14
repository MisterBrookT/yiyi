import AppKit
import YiyiCore

@MainActor enum Theme {
    static let paper = adaptive(light: 0xFCFCFC, dark: 0x181818)
    static let surface = adaptive(light: 0xF2F2F2, dark: 0x242424)
    static let settingsBackground = adaptive(light: 0xF5F5F7, dark: 0x202023)
    static let settingsSurface = adaptive(light: 0xFFFFFF, dark: 0x29292C)
    static let settingsBorder = adaptive(light: 0xE0E0E3, dark: 0x3C3C40)
    static let ink = adaptive(light: 0x171717, dark: 0xF5F5F5)
    static let muted = adaptive(light: 0x707070, dark: 0xAAAAAA)
    static let line = adaptive(light: 0xD8D8D8, dark: 0x3A3A3A)
    static let active = NSColor.controlAccentColor
    static let attention = adaptive(light: 0xB25E09, dark: 0xD98C3A)
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
private final class ReadingDocument: NSView { override var isFlipped: Bool { true } }

/// A reading surface, not a status console. The result owns the hierarchy.
@MainActor final class ResultPanelController: NSObject, NSWindowDelegate {
    private let panel: ResultPanel
    private let root = NSView()
    private let commandLabel = NSTextField(labelWithString: "")
    private let textView = NSTextView()
    private let originalView = NSTextView()
    private let scroll = NSScrollView()
    private let document = ReadingDocument()
    private let separator = NSBox()
    private let sourceButton = NSButton()
    private let copyButton = NSButton()
    private let closeButton = NSButton()
    private let pinButton = NSButton()
    private(set) var isPinned = false
    private let actionButton = NSButton()
    private let spinner = NSProgressIndicator()
    private var keyMonitor: Any?
    private var shownAt = Date.distantPast
    private var confirm: (() -> Void)?
    private var original = ""
    private var result = ""
    private var originalExpanded = false
    private var sourceTitle = "Original"
    private let closesOnResign: Bool
    private let width: CGFloat = 440
    private var contentWidth: CGFloat { width - 48 }
    var window: NSWindow { panel }

    init(closesOnResign: Bool = true) {
        self.closesOnResign = closesOnResign
        panel = ResultPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 150), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.delegate = self; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false; panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear; panel.isOpaque = false
        panel.appearance = NSAppearance(named: .aqua)
        panel.isMovableByWindowBackground = true
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.white.cgColor
        root.layer?.cornerRadius = 16; root.layer?.masksToBounds = true
        root.layer?.borderWidth = 1; root.layer?.borderColor = NSColor(white: 0.89, alpha: 1).cgColor
        panel.contentView = root
        commandLabel.font = .systemFont(ofSize: 12, weight: .medium)
        commandLabel.textColor = .secondaryLabelColor
        commandLabel.lineBreakMode = .byTruncatingTail
        commandLabel.setAccessibilityIdentifier("result.command")
        for editor in [textView, originalView] {
            editor.isEditable = false; editor.isSelectable = true; editor.drawsBackground = false
            editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
            editor.textContainerInset = .zero; editor.textContainer?.lineFragmentPadding = 0
            editor.textContainer?.widthTracksTextView = true
            editor.textContainer?.containerSize = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
            editor.setFrameSize(NSSize(width: contentWidth, height: 1))
            document.addSubview(editor)
        }
        panel.initialFirstResponder = textView
        textView.setAccessibilityIdentifier("result.text")
        originalView.setAccessibilityIdentifier("result.original")
        separator.boxType = .separator; document.addSubview(separator)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.documentView = document
        scroll.setAccessibilityIdentifier("result.scroll")
        configureButton(sourceButton, title: "Original", symbol: "chevron.down", action: #selector(toggleOriginal), id: "result.show-original")
        configureButton(copyButton, title: "Copy", symbol: "doc.on.doc", action: #selector(copyResult), id: "result.copy")
        configureButton(closeButton, title: "", symbol: "xmark", action: #selector(close), id: "result.close")
        configureButton(pinButton, title: "", symbol: "pin", action: #selector(togglePin), id: "result.pin")
        updatePinButton()
        closeButton.setAccessibilityLabel("Close translation"); closeButton.toolTip = "Close (Esc)"
        copyButton.toolTip = "Copy translation (⌘C)"
        configureButton(actionButton, title: "Continue", symbol: nil, action: #selector(confirmAction), id: "result.action")
        spinner.style = .spinning; spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false; spinner.setAccessibilityLabel("Translating")
        for view in [commandLabel, scroll, sourceButton, copyButton, pinButton, closeButton, actionButton, spinner] { root.addSubview(view) }
        reset()
    }

    private func configureButton(_ button: NSButton, title: String, symbol: String?, action: Selector, id: String) {
        button.title = title; button.bezelStyle = .inline
        button.font = .systemFont(ofSize: 12); button.target = self; button.action = action
        if let symbol { button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading }
        button.setAccessibilityIdentifier(id)
    }
    private func reset() {
        confirm = nil; original = ""; result = ""; originalExpanded = false
        sourceTitle = "Original"; sourceButton.isHidden = true; copyButton.isHidden = true
        actionButton.isHidden = true; spinner.stopAnimation(nil)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
    }
    func showLoading(command: String, source: String) {
        showLoading(command: command, capture: CaptureDecision(text: source, source: .selection))
    }
    func showLoading(command: String, capture: CaptureDecision, relaunch: (() -> Void)? = nil) {
        isPinned = false; updatePinButton()
        reset(); commandLabel.stringValue = command
        original = capture.text ?? ""; sourceTitle = capture.source == .clipboard ? "Clipboard" : "Original"
        sourceButton.toolTip = capture.hint ?? "Show the full original text"
        sourceButton.isHidden = original.isEmpty
        confirm = relaunch; actionButton.title = "Relaunch"; actionButton.isHidden = relaunch == nil
        setBody("Translating…", color: .secondaryLabelColor, markdown: false)
        spinner.startAnimation(nil); resizeAndShow()
    }
    func showResult(_ text: String) {
        result = text; spinner.stopAnimation(nil)
        copyButton.title = "Copy"; copyButton.isHidden = text.isEmpty
        setBody(text, color: .labelColor, markdown: true); resizeAndShow()
    }
    func showError(command: String = "yiyi", provider: String = "", model: String = "", message: String, detail: String? = nil) {
        reset(); commandLabel.stringValue = command
        sourceTitle = "Details"
        original = ([provider, model].filter { !$0.isEmpty } + [detail ?? ""].filter { !$0.isEmpty }).joined(separator: "\n")
        sourceButton.isHidden = original.isEmpty; sourceButton.toolTip = "Show error details"
        setBody(message, color: Theme.danger, markdown: false); resizeAndShow()
    }
    func showNotice(command: String, message: String, actionTitle: String, confirm: (() -> Void)?) {
        reset(); commandLabel.stringValue = command; self.confirm = confirm
        actionButton.title = actionTitle; actionButton.isHidden = confirm == nil
        setBody(message, color: .labelColor, markdown: false); resizeAndShow()
    }
    private func setBody(_ text: String, color: NSColor, markdown: Bool) {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 3
        let rendered = NSMutableAttributedString(string: "")
        if markdown, let parsed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            for run in parsed.runs {
                let intent = run.inlinePresentationIntent ?? []
                var font = intent.contains(.code) ? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular) : NSFont.systemFont(ofSize: 17)
                if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                rendered.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]))
            }
        } else {
            rendered.append(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: color, .paragraphStyle: paragraph]))
        }
        textView.textStorage?.setAttributedString(rendered)
    }
    @objc private func togglePin() {
        isPinned.toggle()
        updatePinButton()
    }
    private func updatePinButton() {
        pinButton.state = isPinned ? .on : .off
        pinButton.image = NSImage(systemSymbolName: isPinned ? "pin.fill" : "pin", accessibilityDescription: nil)
        pinButton.contentTintColor = isPinned ? .controlAccentColor : .secondaryLabelColor
        pinButton.setAccessibilityLabel(isPinned ? "Unpin window" : "Pin window")
        pinButton.setAccessibilityValue(isPinned ? "Pinned" : "Unpinned")
        pinButton.toolTip = isPinned ? "Pinned: stays open when switching apps. Click to unpin." : "Pin this window to keep it open when switching apps."
    }
    @objc private func toggleOriginal() {
        originalExpanded.toggle()
        if !originalExpanded { panel.makeFirstResponder(textView) }
        resizeAndShow()
    }
    private func measure(_ editor: NSTextView) -> CGFloat {
        editor.setFrameSize(NSSize(width: contentWidth, height: max(1, editor.frame.height)))
        editor.layoutManager?.ensureLayout(for: editor.textContainer!)
        return ceil(editor.layoutManager?.usedRect(for: editor.textContainer!).height ?? 22)
    }
    private func resizeAndShow() {
        let wasVisible = panel.isVisible; let previousTop = panel.frame.maxY
        originalView.isHidden = !originalExpanded; separator.isHidden = !originalExpanded
        sourceButton.title = originalExpanded ? "Hide \(sourceTitle.lowercased())" : sourceTitle
        sourceButton.image = NSImage(systemSymbolName: originalExpanded ? "chevron.up" : "chevron.down", accessibilityDescription: nil)
        originalView.textStorage?.setAttributedString(NSAttributedString(string: original, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor]))
        let originalHeight = originalExpanded ? measure(originalView) : 0
        originalView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: originalHeight)
        separator.frame = NSRect(x: 0, y: originalHeight + 12, width: contentWidth, height: 1)
        let offset = originalExpanded ? originalHeight + 28 : 0
        let resultHeight = max(24, measure(textView))
        textView.frame = NSRect(x: 0, y: offset, width: contentWidth, height: resultHeight)
        let total = offset + resultHeight
        document.frame = NSRect(x: 0, y: 0, width: contentWidth, height: total)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        let safeFrame = screen?.visibleFrame.insetBy(dx: 16, dy: 16) ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let bodyHeight = min(max(24, safeFrame.height - 108), min(420, total))
        let height = 56 + bodyHeight + 52
        panel.setContentSize(NSSize(width: width, height: height))
        commandLabel.frame = NSRect(x: 24, y: height - 39, width: width - 140, height: 18)
        closeButton.frame = NSRect(x: width - 48, y: height - 44, width: 28, height: 28)
        pinButton.frame = NSRect(x: width - 80, y: height - 44, width: 28, height: 28)
        spinner.frame = NSRect(x: width - 104, y: height - 36, width: 14, height: 14)
        scroll.frame = NSRect(x: 24, y: 52, width: contentWidth, height: bodyHeight)
        func fit(_ button: NSButton) -> CGFloat { max(64, ceil(button.fittingSize.width) + 20) }
        sourceButton.frame = NSRect(x: 18, y: 12, width: fit(sourceButton), height: 28)
        let copyWidth = fit(copyButton)
        copyButton.frame = NSRect(x: width - 18 - copyWidth, y: 12, width: copyWidth, height: 28)
        let actionWidth = fit(actionButton)
        actionButton.frame = NSRect(x: width - 18 - (copyButton.isHidden ? 0 : copyWidth + 8) - actionWidth, y: 12, width: actionWidth, height: 28)
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
        let proposedX = wasVisible ? panel.frame.minX : mouse.x - width / 2
        let proposedY = wasVisible ? previousTop - height : mouse.y - height / 3
        panel.setFrameOrigin(NSPoint(x: min(max(proposedX, safeFrame.minX), safeFrame.maxX - width), y: min(max(proposedY, safeFrame.minY), safeFrame.maxY - height)))
        if !wasVisible {
            shownAt = Date(); NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
        }
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }; return self.handleKey(event)
            }
        }
    }
    func handleKey(_ event: NSEvent) -> NSEvent? {
        guard panel.isKeyWindow, event.window === panel else { return event }
        if event.keyCode == 53 { close(); return nil }
        if event.keyCode == 36, confirm != nil { confirmAction(); return nil }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c", !result.isEmpty {
            writeClipboard(textForCopy(useSelection: true)); return nil
        }
        return event
    }
    func textForCopy(useSelection: Bool) -> String {
        let editor = panel.firstResponder === originalView ? originalView : textView
        let range = editor.selectedRange()
        if useSelection, range.length > 0 { return (editor.string as NSString).substring(with: range) }
        return result
    }
    @objc private func copyResult() { guard !result.isEmpty else { return }; writeClipboard(result); copyButton.title = "Copied" }
    private func writeClipboard(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    @objc private func confirmAction() { let action = confirm; close(); action?() }
    @objc func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        confirm = nil; panel.orderOut(nil)
        isPinned = false; updatePinButton()
    }
    func control(_ id: String) -> NSView? {
        func find(_ view: NSView) -> NSView? { if view.accessibilityIdentifier() == id { return view }; return view.subviews.lazy.compactMap(find).first }
        return find(root)
    }
    func renderPNG(to url: URL) throws {
        root.layoutSubtreeIfNeeded(); root.displayIfNeeded()
        guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
        root.cacheDisplay(in: root.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try png.write(to: url)
    }
    func windowDidResignKey(_ notification: Notification) {
        guard closesOnResign, !isPinned, Date().timeIntervalSince(shownAt) > 0.6 else { return }; close()
    }
}
