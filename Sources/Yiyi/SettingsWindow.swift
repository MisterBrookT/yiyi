import AppKit
import Carbon
import YiyiCore

@MainActor final class SettingsWindowController: NSWindowController, NSTextViewDelegate {
    private let configs: ConfigManager
    private let superKeyStatus: () -> String
    private let contentStack = NSStackView()
    private let settingsDocumentView = SettingsDocumentView(frame: NSRect(x: 0, y: 0, width: 512, height: 1))
    private var selectedProvider: String

    init(configs: ConfigManager, superKeyStatus: @escaping () -> String) {
        self.configs = configs
        self.superKeyStatus = superKeyStatus
        self.selectedProvider = configs.config.defaultProvider
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "yiyi Settings"; window.minSize = NSSize(width: 560, height: 560); window.isReleasedWhenClosed = false
        super.init(window: window)
        buildChrome(); rebuild()
    }
    required init?(coder: NSCoder) { nil }

    func show() {
        rebuild()
        window?.setContentSize(NSSize(width: 560, height: 720))
        window?.center(); showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }

    private func buildChrome() {
        let background = SettingsFillView(color: Theme.paper)
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        contentStack.orientation = .vertical; contentStack.alignment = .width; contentStack.spacing = 0; contentStack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        settingsDocumentView.addSubview(contentStack); contentStack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = settingsDocumentView
        NSLayoutConstraint.activate([contentStack.leadingAnchor.constraint(equalTo: settingsDocumentView.leadingAnchor), contentStack.trailingAnchor.constraint(equalTo: settingsDocumentView.trailingAnchor), contentStack.topAnchor.constraint(equalTo: settingsDocumentView.topAnchor), contentStack.bottomAnchor.constraint(equalTo: settingsDocumentView.bottomAnchor)])
        background.addSubview(scroll); scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor), scroll.topAnchor.constraint(equalTo: background.topAnchor), scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor)])
        window?.contentView = background
    }

    private func rebuild() {
        contentStack.arrangedSubviews.forEach { contentStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        addSection(title: "Provider", body: providerSection())
        addDivider(); addSection(title: "Shortcuts", body: shortcutsSection())
        addDivider(); addSection(title: "Superkey", body: superKeySection())
        addDivider(); addSection(title: "Behavior", body: behaviorSection())
        contentStack.layoutSubtreeIfNeeded()
        settingsDocumentView.setFrameSize(NSSize(width: 512, height: max(contentStack.fittingSize.height, 1)))
    }

    private func providerSection() -> NSView {
        if configs.config.providers[selectedProvider] == nil { selectedProvider = configs.config.defaultProvider }
        let names = configs.config.providers.keys.sorted()
        let choices = NSStackView(); choices.orientation = .vertical; choices.alignment = .leading; choices.spacing = 4
        for name in names {
            let button = NSButton(radioButtonWithTitle: name, target: self, action: #selector(selectProvider(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(name); button.state = name == configs.config.defaultProvider ? .on : .off
            choices.addArrangedSubview(button)
        }
        guard let provider = configs.config.providers[selectedProvider] else { return choices }
        let selected = popup(names, selected: selectedProvider, action: #selector(showProvider(_:))); selected.setAccessibilityIdentifier("provider.selector")
        let model = field(provider.model, id: "provider.model", mono: true)
        let key = NSSecureTextField(string: ""); style(key); key.placeholderString = provider.apiKey == nil ? "env var / .env / apikey" : "stored — type to replace"; key.identifier = NSUserInterfaceItemIdentifier("provider.key.\(selectedProvider)"); key.setAccessibilityIdentifier("provider.apikey"); key.target = self; key.action = #selector(commitField(_:))
        let temperature = field(provider.temperature.map { String($0) } ?? "", id: "provider.temperature", mono: true); temperature.placeholderString = "empty = omit"
        let effort = popup(ReasoningEffort.allCases.map(\.rawValue), selected: provider.reasoningEffort.rawValue, action: #selector(providerEffort(_:))); effort.identifier = NSUserInterfaceItemIdentifier(selectedProvider); effort.setAccessibilityIdentifier("provider.reasoning")
        let status = label(configs.apiKeyStatus(for: selectedProvider), mono: true, secondary: true); status.maximumNumberOfLines = 4; status.lineBreakMode = .byWordWrapping
        return column([row("Default", choices), row("Edit", selected), row("Model", model), row("API key", key), row("Temperature", temperature), row("Reasoning effort", effort), row("Key status", status)], spacing: 8)
    }

    private func shortcutsSection() -> NSView {
        var views: [NSView] = []
        for (index, command) in configs.config.commands.enumerated() {
            let name = field(command.name, id: "command.name.\(index)")
            let hotkey = HotkeyRecorder(value: command.hotkey); hotkey.onCommit = { [weak self] value in try? self?.configs.setCommand(index, hotkey: value) }
            hotkey.setAccessibilityIdentifier("command.\(index).hotkey")
            let remove = NSButton(title: "Remove command", target: self, action: #selector(removeCommand(_:))); remove.tag = index; remove.isBordered = false; remove.contentTintColor = Theme.danger; remove.font = .systemFont(ofSize: 11); remove.alignment = .right
            let providerNames = ["inherit"] + configs.config.providers.keys.sorted()
            let provider = popup(providerNames, selected: command.provider ?? "inherit", action: #selector(commandProvider(_:))); provider.tag = index
            let model = field(command.model ?? "", id: "command.model.\(index)", mono: true); model.placeholderString = "inherit"
            let efforts = ["inherit"] + ReasoningEffort.allCases.map(\.rawValue)
            let effort = popup(efforts, selected: command.reasoningEffort?.rawValue ?? "inherit", action: #selector(commandEffort(_:))); effort.tag = index
            let prompt = NSTextView(); prompt.string = command.prompt; prompt.font = .systemFont(ofSize: 13); prompt.textColor = Theme.ink; prompt.backgroundColor = Theme.surface; prompt.textContainerInset = NSSize(width: 8, height: 8); prompt.delegate = self; prompt.identifier = NSUserInterfaceItemIdentifier("prompt.\(index)"); prompt.setAccessibilityIdentifier("command.\(index).prompt")
            let promptScroll = NSScrollView(); promptScroll.documentView = prompt; promptScroll.hasVerticalScroller = true; promptScroll.drawsBackground = false; promptScroll.heightAnchor.constraint(equalToConstant: 100).isActive = true; promptScroll.wantsLayer = true; promptScroll.layer?.cornerRadius = Theme.radiusControl; promptScroll.layer?.borderWidth = 1; promptScroll.layer?.borderColor = Theme.line.cgColor
            var cardViews: [NSView] = [row("Name", name), row("Shortcut", hotkey), row("Provider", provider), row("Model override", model), row("Reasoning override", effort), row("Prompt template", promptScroll), row("", remove)]
            if !command.prompt.contains("{selection}") && !command.prompt.contains("{input}") { let warning = label("Prompt must contain {selection} or {input}."); warning.textColor = Theme.danger; warning.setAccessibilityIdentifier("command.\(index).prompt-error"); cardViews.append(row("", warning)) }
            let card = SettingsCardView(); let body = column(cardViews, spacing: 8); card.addSubview(body); body.translatesAutoresizingMaskIntoConstraints = false; NSLayoutConstraint.activate([body.leadingAnchor.constraint(equalTo: card.leadingAnchor), body.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16), body.topAnchor.constraint(equalTo: card.topAnchor, constant: 16), body.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)])
            card.widthAnchor.constraint(equalToConstant: 464).isActive = true
            views.append(card)
        }
        let add = NSButton(title: "Add command", target: self, action: #selector(addCommand)); add.bezelStyle = .rounded; views.append(add)
        return column(views, spacing: 12)
    }

    private func superKeySection() -> NSView {
        let values = SuperKey.allCases
        let popup = popup(values.map(\.displayName), selected: configs.config.superKey.displayName, action: #selector(changeSuperKey(_:)))
        let hint = label("Bind a command as super+t. Requires Accessibility. Status: \(superKeyStatus())", mono: true, secondary: true); hint.maximumNumberOfLines = 3; hint.lineBreakMode = .byWordWrapping
        popup.setAccessibilityIdentifier("superkey.popup")
        return column([row("Leader modifier", popup), hint], spacing: 8)
    }

    private func behaviorSection() -> NSView {
        let copy = NSButton(checkboxWithTitle: "Copy translations to the clipboard", target: self, action: #selector(changeAutoCopy(_:))); copy.state = configs.config.autoCopy ? .on : .off
        return copy
    }

    private func addSection(title: String, body: NSView) {
        let heading = label(title.uppercased(), secondary: true); heading.font = .systemFont(ofSize: 11, weight: .medium); heading.widthAnchor.constraint(equalToConstant: 464).isActive = true; heading.setAccessibilityIdentifier("section.\(title.lowercased())")
        body.widthAnchor.constraint(equalToConstant: 464).isActive = true
        contentStack.addArrangedSubview(column([heading, body], spacing: 12))
    }
    private func addDivider() { let line = SettingsFillView(color: Theme.line); line.widthAnchor.constraint(equalToConstant: 464).isActive = true; line.heightAnchor.constraint(equalToConstant: 1).isActive = true; contentStack.addArrangedSubview(line); contentStack.setCustomSpacing(24, after: line); if contentStack.arrangedSubviews.count > 1 { contentStack.setCustomSpacing(24, after: contentStack.arrangedSubviews[contentStack.arrangedSubviews.count - 2]) } }

    private func column(_ views: [NSView], spacing: CGFloat) -> NSStackView { let stack = NSStackView(views: views); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing; return stack }
    private func row(_ title: String, _ control: NSView) -> NSView {
        let titleField = label(title, secondary: true); titleField.font = .systemFont(ofSize: 12); titleField.alignment = .right
        titleField.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let value = NSView(); value.addSubview(control); control.translatesAutoresizingMaskIntoConstraints = false
        value.widthAnchor.constraint(equalToConstant: 260).isActive = true
        NSLayoutConstraint.activate([control.leadingAnchor.constraint(equalTo: value.leadingAnchor), control.trailingAnchor.constraint(equalTo: value.trailingAnchor), control.topAnchor.constraint(equalTo: value.topAnchor), control.bottomAnchor.constraint(equalTo: value.bottomAnchor)])
        let grid = NSGridView(views: [[titleField, value]]); grid.columnSpacing = 12; grid.rowSpacing = 0; grid.xPlacement = .fill; grid.yPlacement = .center
        grid.widthAnchor.constraint(equalToConstant: 422).isActive = true
        return grid
    }
    private func label(_ text: String, mono: Bool = false, secondary: Bool = false) -> NSTextField { let value = NSTextField(wrappingLabelWithString: text); value.font = mono ? .monospacedSystemFont(ofSize: 11, weight: .regular) : .systemFont(ofSize: 13); value.textColor = secondary ? Theme.muted : Theme.ink; value.alignment = .left; return value }
    private func field(_ value: String, id: String, mono: Bool = false) -> NSTextField { let field = NSTextField(string: value); style(field); if mono { field.font = .monospacedSystemFont(ofSize: 12, weight: .regular) }; field.identifier = NSUserInterfaceItemIdentifier(id); field.setAccessibilityIdentifier(id); field.target = self; field.action = #selector(commitField(_:)); return field }
    private func style(_ field: NSTextField) { field.font = .systemFont(ofSize: 13); field.textColor = Theme.ink; field.backgroundColor = Theme.surface; field.isBezeled = true; field.bezelStyle = .roundedBezel }
    private func popup(_ values: [String], selected: String, action: Selector) -> NSPopUpButton { let popup = NSPopUpButton(); popup.addItems(withTitles: values); popup.selectItem(withTitle: selected); popup.target = self; popup.action = action; popup.font = .systemFont(ofSize: 13); return popup }

    @objc private func selectProvider(_ sender: NSButton) { guard let name = sender.identifier?.rawValue else { return }; try? configs.setDefaultProvider(name); selectedProvider = name; rebuild() }
    @objc private func showProvider(_ sender: NSPopUpButton) { selectedProvider = sender.titleOfSelectedItem ?? selectedProvider; rebuild() }
    @objc private func providerEffort(_ sender: NSPopUpButton) { guard let name = sender.identifier?.rawValue, let value = sender.titleOfSelectedItem.flatMap(ReasoningEffort.init(rawValue:)) else { return }; try? configs.setProvider(name, reasoningEffort: value); rebuild() }
    @objc private func commandProvider(_ sender: NSPopUpButton) { try? configs.setCommand(sender.tag, provider: sender.titleOfSelectedItem == "inherit" ? .some(nil) : .some(sender.titleOfSelectedItem)); rebuild() }
    @objc private func commandEffort(_ sender: NSPopUpButton) { let raw = sender.titleOfSelectedItem; try? configs.setCommand(sender.tag, reasoningEffort: raw == "inherit" ? .some(nil) : .some(raw.flatMap(ReasoningEffort.init(rawValue:)))); rebuild() }
    @objc private func changeSuperKey(_ sender: NSPopUpButton) { guard let selected = sender.titleOfSelectedItem, let value = SuperKey.allCases.first(where: { $0.displayName == selected }) else { return }; try? configs.setSuperKey(value); rebuild() }
    @objc private func changeAutoCopy(_ sender: NSButton) { try? configs.setAutoCopy(sender.state == .on) }
    @objc private func addCommand() { try? configs.addCommand(); rebuild() }
    @objc private func removeCommand(_ sender: NSButton) { try? configs.deleteCommand(at: sender.tag); rebuild() }
    @objc private func commitField(_ sender: NSTextField) {
        let id = sender.identifier?.rawValue ?? ""
        if id == "provider.model" { try? configs.setProvider(selectedProvider, model: sender.stringValue) }
        else if id == "provider.temperature" { try? configs.setProvider(selectedProvider, temperature: .some(Double(sender.stringValue))) }
        else {
            let parts = id.split(separator: ".").map(String.init)
            if parts.count >= 3, parts[0] == "provider", parts[1] == "key", !sender.stringValue.isEmpty { try? configs.setProvider(parts[2], apiKey: .some(sender.stringValue)) }
            if parts.count >= 3, parts[0] == "command", let index = Int(parts[2]) {
                if parts[1] == "name" { try? configs.setCommand(index, name: sender.stringValue) }
                else if parts[1] == "model" { try? configs.setCommand(index, model: .some(sender.stringValue.isEmpty ? nil : sender.stringValue)) }
            }
        }
        rebuild()
    }

    func prepareOffscreen(appearance: NSAppearance) {
        window?.appearance = appearance
        window?.setContentSize(NSSize(width: 560, height: 720))
        rebuild()
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    func control(accessibilityID: String) -> NSView? {
        func find(_ view: NSView) -> NSView? {
            if view.accessibilityIdentifier() == accessibilityID { return view }
            for child in view.subviews { if let match = find(child) { return match } }
            return nil
        }
        return window?.contentView.flatMap(find)
    }

    func renderPNG(to url: URL, bottom: Bool = false) throws {
        guard let content = window?.contentView else { return }
        if let scroll = content.subviews.compactMap({ $0 as? NSScrollView }).first {
            let y = bottom ? max(0, scroll.documentView!.bounds.height - scroll.contentView.bounds.height) : 0
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y)); scroll.reflectScrolledClipView(scroll.contentView)
        }
        content.layoutSubtreeIfNeeded()
        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try png.write(to: url)
    }

    func setRecordedHotkey(_ value: String, index: Int) throws { try configs.setCommand(index, hotkey: value); rebuild() }
    func textDidEndEditing(_ notification: Notification) { guard let text = notification.object as? NSTextView, let id = text.identifier?.rawValue, let index = Int(id.split(separator: ".").last ?? "") else { return }; try? configs.setCommand(index, prompt: text.string); rebuild() }
}
private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private class SettingsFillView: NSView {
    let color: NSColor
    init(color: NSColor) { self.color = color; super.init(frame: .zero); wantsLayer = true }
    required init?(coder: NSCoder) { nil }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = color.cgColor } }
}
private final class SettingsCardView: SettingsFillView {
    init() { super.init(color: Theme.surface); layer?.cornerRadius = Theme.radiusControl }
    required init?(coder: NSCoder) { nil }
}

@MainActor private final class HotkeyRecorder: NSButton {
    var onCommit: ((String) -> Void)?
    private var recording = false
    init(value: String) { super.init(frame: .zero); title = value.isEmpty ? "Record" : value; font = .monospacedSystemFont(ofSize: 11, weight: .regular); bezelStyle = .rounded; target = self; action = #selector(beginRecording) }
    required init?(coder: NSCoder) { nil }
    @objc private func beginRecording() { recording = true; title = "press keys…"; window?.makeFirstResponder(self) }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { recording = false; title = "Record"; return }
        if event.keyCode == 51 || event.keyCode == 117 { recording = false; title = "Record"; onCommit?(""); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }; if flags.contains(.option) { modifiers |= UInt32(optionKey) }; if flags.contains(.control) { modifiers |= UInt32(controlKey) }; if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        guard modifiers != 0 else { NSSound.beep(); return }
        let value = formatHotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers); recording = false; title = value; onCommit?(value)
    }
}
