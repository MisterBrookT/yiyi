import AppKit
import Carbon
import YiyiCore
import OSLog

private let settingsLogger = Logger(subsystem: "cc.blackblue.yiyi", category: "settings")

@MainActor final class SettingsWindowController: NSWindowController, NSTextViewDelegate, NSWindowDelegate {
    private let configs: ConfigManager
    private let accessibilityStatus: () -> AccessibilityStatus
    private let requestAccessibility: () -> Void
    private let repairAccessibility: () -> Void
    private let reloadFromDisk: () -> Void
    private let detail = SettingsBackgroundView()
    private var paneView: NSView?
    private var selectedProvider: String
    private var fieldErrors: [String: String] = [:]
    /// Advanced rows collapse again every time Settings reopens: the plain view is the default.
    private var expandedAdvanced: Set<String> = []
    private var centered = false
    private let contentWidth: CGFloat = 590
    private let labelWidth: CGFloat = 150
    private let controlWidth: CGFloat = 370

    init(
        configs: ConfigManager,
        accessibilityStatus: @escaping () -> AccessibilityStatus,
        requestAccessibility: @escaping () -> Void,
        repairAccessibility: @escaping () -> Void,
        reloadFromDisk: @escaping () -> Void
    ) {
        self.configs = configs
        self.accessibilityStatus = accessibilityStatus
        self.requestAccessibility = requestAccessibility
        self.repairAccessibility = repairAccessibility
        self.reloadFromDisk = reloadFromDisk
        selectedProvider = configs.config.defaultProvider
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 646, height: 500), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildChrome()
        rebuild(resize: true, animate: false)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        rebuild(resize: true, animate: false)
        if !centered { window?.center(); centered = true }
        logWindowState("requested")
        // A status-item menu is still tracking while its action runs. Activating an
        // accessory app here is undone when AppKit closes the menu and restores the
        // previously active application, leaving this visible window non-key.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            self.logWindowState("presented")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.logWindowState("settled")
            }
        }
    }

    private func logWindowState(_ phase: String) {
        guard let window else { return }
        let keyWindow = NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "nil"
        let responder = window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
        settingsLogger.notice("\(phase, privacy: .public) active=\(NSApp.isActive) key=\(window.isKeyWindow) main=\(window.isMainWindow) appKeyWindow=\(keyWindow, privacy: .public) firstResponder=\(responder, privacy: .public)")
    }

    private func buildChrome() {
        guard let window else { return }
        detail.wantsLayer = true
        window.contentView = detail
        window.titlebarSeparatorStyle = .line
    }


    private func rebuild(resize: Bool = true, animate: Bool = false) {
        paneView?.removeFromSuperview()
        let document = paneDocument()
        let documentSize = document.fittingSize
        document.frame = NSRect(origin: .zero, size: documentSize)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = documentSize.height > pageHeightLimit
        scroll.autohidesScrollers = true
        scroll.documentView = document
        detail.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: detail.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: detail.trailingAnchor), scroll.topAnchor.constraint(equalTo: detail.topAnchor), scroll.bottomAnchor.constraint(equalTo: detail.bottomAnchor)])
        paneView = scroll
        document.layoutSubtreeIfNeeded()
        let desiredHeight = min(pageHeightLimit, max(300, documentSize.height))
        window?.title = "yiyi Settings"
        window?.minSize = NSSize(width: 646, height: min(desiredHeight, 400))
        if resize { resizeWindow(to: desiredHeight, animate: animate) }
        configureKeyLoop(in: document)
    }

    /// One page: show all of it whenever the display allows, and only then scroll.
    private var pageHeightLimit: CGFloat {
        let screen = window?.screen ?? NSScreen.main
        return max(400, (screen?.visibleFrame.height ?? 900) - 80)
    }

    private func resizeWindow(to height: CGFloat, animate: Bool) {
        guard let window else { return }
        var frame = window.frame
        let delta = height - window.contentLayoutRect.height
        frame.origin.y -= delta
        frame.size.height += delta
        window.setFrame(frame, display: true, animate: animate && window.isVisible)
    }

    private func paneDocument() -> NSView {
        let content = sections([servicePane(), shortcutsPane(), systemPane()])
        let document = SettingsDocumentView()
        document.setAccessibilityIdentifier("settings.page")
        document.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -28),
            document.widthAnchor.constraint(equalToConstant: contentWidth)
        ])
        return document
    }

    private func servicePane() -> NSView {
        if configs.config.providers[selectedProvider] == nil { selectedProvider = configs.config.defaultProvider }
        let names = configs.config.providers.keys.sorted()
        let choices = NSStackView()
        choices.orientation = .vertical; choices.alignment = .leading; choices.spacing = 4
        for name in names {
            let button = NSButton(radioButtonWithTitle: name, target: self, action: #selector(selectProvider(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(name)
            button.setAccessibilityIdentifier("provider.default.\(name)")
            button.state = name == configs.config.defaultProvider ? .on : .off
            choices.addArrangedSubview(button)
        }
        guard let provider = configs.config.providers[selectedProvider] else {
            return section("Service", rows: [row("Translate with", choices)])
        }
        let key = NSSecureTextField(string: "")
        style(key); key.placeholderString = provider.apiKey == nil ? "Paste your API key" : "Stored — empty clears"
        key.identifier = NSUserInterfaceItemIdentifier("provider.api-key"); key.setAccessibilityIdentifier("provider.api-key"); key.target = self; key.action = #selector(commitField(_:)); stretch(key)
        let ready = configs.providerAvailability(selectedProvider).usable
        let status = label(ready ? "Ready" : "No key yet — paste one above", secondary: !ready)
        status.maximumNumberOfLines = 0; status.usesSingleLineMode = false; status.lineBreakMode = .byWordWrapping
        status.preferredMaxLayoutWidth = controlWidth
        if !ready { status.textColor = Theme.attention }
        status.setAccessibilityIdentifier("provider.key-status")
        status.setAccessibilityValue(ready ? "ready" : "missing")
        stretch(status); status.heightAnchor.constraint(greaterThanOrEqualToConstant: 18).isActive = true
        var rows = [row("Translate with", choices), row("API key", key), row("", status)]
        rows.append(advancedToggle("provider"))
        if expandedAdvanced.contains("provider") {
            let selected = popup(names, selected: selectedProvider, id: "provider.selector", action: #selector(showProvider(_:)))
            let baseURL = field(provider.baseURL, id: "provider.base-url", mono: true)
            let env = field(provider.apiKeyEnv, id: "provider.api-key-env", mono: true)
            let model = field(provider.model, id: "provider.model", mono: true)
            let temperature = field(provider.temperature.map { String($0) } ?? "", id: "provider.temperature", mono: true); prosePlaceholder("Empty to omit", in: temperature)
            let effort = popup(ReasoningEffort.allCases.map(\.rawValue), selected: provider.reasoningEffort.rawValue, id: "provider.reasoning-effort", action: #selector(providerEffort(_:))); effort.identifier = NSUserInterfaceItemIdentifier(selectedProvider)
            let addName = field("", id: "provider.add-name"); prosePlaceholder("New provider name", in: addName)
            let add = NSButton(title: "Add Provider", target: self, action: #selector(addProvider(_:))); add.setAccessibilityIdentifier("provider.add")
            let remove = NSButton(title: "Remove Provider", target: self, action: #selector(removeProvider)); remove.setAccessibilityIdentifier("provider.remove")
            let source = label(configs.apiKeyStatus(for: selectedProvider), mono: true, secondary: true)
            source.maximumNumberOfLines = 0; source.usesSingleLineMode = false; source.lineBreakMode = .byWordWrapping
            source.preferredMaxLayoutWidth = controlWidth
            source.setAccessibilityIdentifier("provider.key-source")
            stretch(source); source.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
            rows += [row("Editing", selected), row("Base URL", baseURL), row("API key env", env), row("Model", model), row("Temperature", temperature), row("Reasoning effort", effort), row("Key source", source), row("", remove), row("New provider", addName), row("", add)]
        }
        appendError(for: "provider", to: &rows)
        return section("Service", rows: rows)
    }

    private func shortcutsPane() -> NSView {
        let leader = popup(SuperKey.allCases.map(\.displayName), selected: configs.config.superKey.displayName, id: "superkey.popup", action: #selector(changeSuperKey(_:)))
        var sectionsList: [NSView] = [section("Shortcuts", rows: [row("Leader key", leader)])]
        for (index, command) in configs.config.commands.enumerated() {
            let name = field(command.name, id: "command.\(index).name")
            let hotkey = HotkeyRecorder(value: command.hotkey, recordsSuperKey: true); hotkey.onCommit = { [weak self] value in self?.commitHotkey(value, index: index) }; hotkey.setAccessibilityIdentifier("command.\(index).hotkey")
            let prompt = NSTextView(); prompt.string = command.prompt; prompt.font = .systemFont(ofSize: 13); prompt.textContainerInset = NSSize(width: 8, height: 8); prompt.delegate = self; prompt.identifier = NSUserInterfaceItemIdentifier("command.\(index).prompt"); prompt.setAccessibilityIdentifier("command.\(index).prompt")
            let promptScroll = NSScrollView(); promptScroll.documentView = prompt; promptScroll.hasVerticalScroller = true; promptScroll.borderType = .bezelBorder; promptScroll.heightAnchor.constraint(equalToConstant: 92).isActive = true; stretch(promptScroll)
            var rows = [row("Name", name), row("Shortcut", hotkey), row("Prompt", promptScroll)]
            rows.append(advancedToggle("command.\(index)"))
            if expandedAdvanced.contains("command.\(index)") {
                let provider = popup(["inherit"] + configs.config.providers.keys.sorted(), selected: command.provider ?? "inherit", id: "command.\(index).provider", action: #selector(commandProvider(_:))); provider.tag = index
                let model = field(command.model ?? "", id: "command.\(index).model", mono: true); prosePlaceholder("Inherit", in: model)
                let effort = popup(["inherit"] + ReasoningEffort.allCases.map(\.rawValue), selected: command.reasoningEffort?.rawValue ?? "inherit", id: "command.\(index).reasoning-effort", action: #selector(commandEffort(_:))); effort.tag = index
                let remove = NSButton(title: "Remove Command", target: self, action: #selector(removeCommand(_:))); remove.tag = index; remove.setAccessibilityIdentifier("command.\(index).remove")
                rows += [row("Service", provider), row("Model override", model), row("Reasoning override", effort), row("", remove)]
            }
            appendError(for: "command.\(index)", to: &rows)
            sectionsList.append(section(command.name.isEmpty ? "Command \(index + 1)" : command.name, rows: rows))
        }
        let add = NSButton(title: "Add Command", target: self, action: #selector(addCommand)); add.setAccessibilityIdentifier("commands.add")
        sectionsList.append(row("", add))
        return sections(sectionsList)
    }

    private func systemPane() -> NSView {
        let copy = NSButton(checkboxWithTitle: "Copy translations to the clipboard", target: self, action: #selector(changeAutoCopy(_:))); copy.state = configs.config.autoCopy ? .on : .off; copy.setAccessibilityIdentifier("provider.auto-copy")
        let status = accessibilityStatus()
        let trusted = label(status.trusted ? "Accessibility trusted" : "Accessibility not granted", secondary: status.trusted); trusted.setAccessibilityIdentifier("permission.trusted"); trusted.setAccessibilityValue(status.trusted ? "yes" : "no")
        var rows = [row("", copy), row("", trusted)]
        if status.advice == .repairStaleGrant {
            let warning = label("The existing grant belongs to an older yiyi build and will be re-requested."); warning.maximumNumberOfLines = 0; warning.usesSingleLineMode = false; warning.lineBreakMode = .byWordWrapping; warning.textColor = Theme.attention; warning.setAccessibilityIdentifier("permission.stale-grant"); stretch(warning); warning.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true; rows.append(row("", warning))
            let repair = NSButton(title: "Repair Accessibility Permission…", target: self, action: #selector(repairAccessibilityPermission)); repair.setAccessibilityIdentifier("permission.repair"); rows.append(row("", repair))
        } else if !status.trusted {
            let enable = NSButton(title: "Enable Accessibility…", target: self, action: #selector(enableAccessibility)); enable.setAccessibilityIdentifier("permission.enable"); rows.append(row("", enable))
        }
        rows.append(advancedToggle("system"))
        if expandedAdvanced.contains("system") {
            let tapStatus = status.superKeyTapStatus
            let tap = label(tapStatus, mono: true)
            tap.maximumNumberOfLines = 0; tap.usesSingleLineMode = false; tap.lineBreakMode = .byWordWrapping
            tap.preferredMaxLayoutWidth = controlWidth
            tap.setAccessibilityIdentifier("superkey.tap"); tap.setAccessibilityValue(tapStatus)
            stretch(tap); tap.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
            let signature = label(status.signatureIdentity, mono: true); signature.maximumNumberOfLines = 3; signature.lineBreakMode = .byWordWrapping; signature.setAccessibilityIdentifier("permission.signature"); signature.setAccessibilityValue(status.signatureIdentity); stretch(signature)
            let edit = NSButton(title: "Edit config file…", target: self, action: #selector(editConfigFile)); edit.setAccessibilityIdentifier("system.edit-config")
            let reload = NSButton(title: "Reload from file", target: self, action: #selector(reloadFromFile)); reload.setAccessibilityIdentifier("system.reload-config")
            let files = NSStackView(views: [edit, reload]); files.orientation = .horizontal; files.spacing = 8; files.alignment = .centerY
            rows += [row("Leader key tap", tap), row("Signing identity", signature), row("Config file", files)]
        }
        return section("System", rows: rows)
    }

    /// Disclosure row: power-user fields exist, but never greet a new user.
    private func advancedToggle(_ id: String) -> NSView {
        let expanded = expandedAdvanced.contains(id)
        let triangle = NSButton()
        triangle.bezelStyle = .disclosure
        triangle.setButtonType(.onOff)
        triangle.title = ""
        triangle.state = expanded ? .on : .off
        triangle.target = self
        triangle.action = #selector(toggleAdvanced(_:))
        triangle.identifier = NSUserInterfaceItemIdentifier(id)
        triangle.setAccessibilityIdentifier("\(id).advanced")
        let caption = label("Advanced", secondary: true)
        caption.font = .systemFont(ofSize: 12)
        let stack = NSStackView(views: [triangle, caption])
        stack.orientation = .horizontal; stack.spacing = 6; stack.alignment = .centerY
        return row("", stack)
    }

    private func sections(_ views: [NSView]) -> NSView {
        var arranged: [NSView] = []
        for (index, view) in views.enumerated() {
            if index > 0 { let line = NSBox(); line.boxType = .separator; line.heightAnchor.constraint(equalToConstant: 1).isActive = true; arranged.append(line) }
            arranged.append(view)
        }
        return column(arranged, spacing: 20)
    }

    private func section(_ title: String, rows: [NSView]) -> NSView {
        let heading = label("", secondary: true)
        heading.attributedStringValue = NSAttributedString(string: title.uppercased(), attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: Theme.muted, .kern: 1.1])
        let slug = title.lowercased().replacingOccurrences(of: " ", with: "-")
        heading.setAccessibilityIdentifier("section.\(slug)"); heading.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true; heading.heightAnchor.constraint(equalToConstant: 16).isActive = true
        var grouped: [NSView] = []
        for (index, value) in rows.enumerated() {
            if index > 0 { let line = NSBox(); line.boxType = .separator; line.heightAnchor.constraint(equalToConstant: 1).isActive = true; grouped.append(line) }
            grouped.append(value)
        }
        let rowStack = column(grouped, spacing: 9)
        let panel = SettingsGroupView(); panel.addSubview(rowStack); rowStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([rowStack.leadingAnchor.constraint(equalTo: panel.leadingAnchor), rowStack.trailingAnchor.constraint(equalTo: panel.trailingAnchor), rowStack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12), rowStack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12), panel.widthAnchor.constraint(equalToConstant: labelWidth + 16 + controlWidth)])
        return column([heading, panel], spacing: 6)
    }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let titleField = label(title.isEmpty ? "\u{00a0}" : title, secondary: true)
        titleField.font = .systemFont(ofSize: 12)
        titleField.alignment = .right
        titleField.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
        let grid = NSGridView(views: [[titleField, control]])
        grid.columnSpacing = 16
        grid.xPlacement = .leading
        grid.yPlacement = .center
        grid.column(at: 1).width = controlWidth
        grid.heightAnchor.constraint(greaterThanOrEqualToConstant: max(18, control.fittingSize.height)).isActive = true
        return grid
    }

    private func column(_ views: [NSView], spacing: CGFloat) -> NSStackView { let stack = NSStackView(views: views); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing; return stack }
    private func label(_ text: String, mono: Bool = false, secondary: Bool = false) -> NSTextField { let value = NSTextField(wrappingLabelWithString: text); value.font = mono ? .monospacedSystemFont(ofSize: 11, weight: .regular) : .systemFont(ofSize: 13); value.textColor = secondary ? Theme.muted : Theme.ink; return value }
    private func stretch(_ view: NSView) { view.widthAnchor.constraint(equalToConstant: controlWidth).isActive = true }
    private func field(_ value: String, id: String, mono: Bool = false) -> NSTextField { let field = NSTextField(string: value); style(field); if mono { field.font = .monospacedSystemFont(ofSize: 12, weight: .regular) }; field.identifier = NSUserInterfaceItemIdentifier(id); field.setAccessibilityIdentifier(id); field.target = self; field.action = #selector(commitField(_:)); stretch(field); return field }
    private func style(_ field: NSTextField) { field.font = .systemFont(ofSize: 13); field.isBezeled = true; field.bezelStyle = .roundedBezel }
    private func popup(_ values: [String], selected: String, id: String, action: Selector) -> NSPopUpButton { let popup = NSPopUpButton(); popup.addItems(withTitles: values); popup.selectItem(withTitle: selected); popup.target = self; popup.action = action; popup.setAccessibilityIdentifier(id); return popup }

    private func prosePlaceholder(_ value: String, in field: NSTextField) {
        field.placeholderAttributedString = NSAttributedString(string: value, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.placeholderTextColor
        ])
    }

    private func appendError(for prefix: String, to rows: inout [NSView]) {
        for match in fieldErrors.filter({ $0.key == prefix || $0.key.hasPrefix(prefix + ".") }).sorted(by: { $0.key < $1.key }) {
            let warning = label(match.value); warning.textColor = .systemRed; warning.setAccessibilityIdentifier("\(match.key).error"); stretch(warning)
            rows.append(row("", warning))
        }
    }

    private func reject(_ error: Error, at id: String) {
        fieldErrors[id] = error.localizedDescription
        rebuild()
    }

    private func commitHotkey(_ value: String, index: Int) {
        do { try configs.setCommand(index, hotkey: value); fieldErrors.removeValue(forKey: "command.\(index).hotkey") }
        catch { fieldErrors["command.\(index).hotkey"] = error.localizedDescription }
        rebuild()
    }

    private func configureKeyLoop(in root: NSView) {
        let controls = root.allSubviews.filter { ($0 as? NSControl)?.isEnabled == true || $0 is NSTextView }
        for (current, next) in zip(controls, controls.dropFirst() + controls.prefix(1)) { current.nextKeyView = next }
        window?.initialFirstResponder = controls.first
    }

    @objc private func selectProvider(_ sender: NSButton) { guard let name = sender.identifier?.rawValue else { return }; do { try configs.setDefaultProvider(name); selectedProvider = name; fieldErrors.removeValue(forKey: "provider.default") } catch { fieldErrors["provider.default"] = error.localizedDescription }; rebuild() }
    @objc private func showProvider(_ sender: NSPopUpButton) { selectedProvider = sender.titleOfSelectedItem ?? selectedProvider; rebuild() }
    @objc private func providerEffort(_ sender: NSPopUpButton) { guard let name = sender.identifier?.rawValue, let value = sender.titleOfSelectedItem.flatMap(ReasoningEffort.init(rawValue:)) else { return }; do { try configs.setProvider(name, reasoningEffort: value) } catch { reject(error, at: "provider.reasoning-effort"); return }; rebuild() }
    @objc private func commandProvider(_ sender: NSPopUpButton) { do { try configs.setCommand(sender.tag, provider: sender.titleOfSelectedItem == "inherit" ? .some(nil) : .some(sender.titleOfSelectedItem)) } catch { reject(error, at: "command.\(sender.tag).provider"); return }; rebuild() }
    @objc private func commandEffort(_ sender: NSPopUpButton) { let raw = sender.titleOfSelectedItem; do { try configs.setCommand(sender.tag, reasoningEffort: raw == "inherit" ? .some(nil) : .some(raw.flatMap(ReasoningEffort.init(rawValue:)))) } catch { reject(error, at: "command.\(sender.tag).reasoning-effort"); return }; rebuild() }
    @objc private func changeSuperKey(_ sender: NSPopUpButton) { guard let selected = sender.titleOfSelectedItem, let value = SuperKey.allCases.first(where: { $0.displayName == selected }) else { return }; try? configs.setSuperKey(value); rebuild() }
    @objc private func changeAutoCopy(_ sender: NSButton) { try? configs.setAutoCopy(sender.state == .on) }
    @objc private func toggleAdvanced(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        if expandedAdvanced.contains(id) { expandedAdvanced.remove(id) } else { expandedAdvanced.insert(id) }
        rebuild()
    }
    @objc private func enableAccessibility() { requestAccessibility(); rebuild() }
    @objc private func editConfigFile() { NSWorkspace.shared.open(configs.fileURL) }
    @objc private func reloadFromFile() { reloadFromDisk(); rebuild() }
    @objc private func repairAccessibilityPermission() { repairAccessibility(); rebuild() }
    @objc private func addProvider(_ sender: NSButton) {
        guard let name = control(accessibilityID: "provider.add-name") as? NSTextField else { return }
        do { try configs.addProvider(named: name.stringValue); selectedProvider = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); fieldErrors.removeValue(forKey: "provider.add-name") }
        catch { reject(error, at: "provider.add-name"); return }
        rebuild()
    }
    @objc private func removeProvider() { do { try configs.deleteProvider(named: selectedProvider); selectedProvider = configs.config.defaultProvider; fieldErrors.removeValue(forKey: "provider.remove") } catch { reject(error, at: "provider.remove"); return }; rebuild() }
    @objc private func addCommand() { try? configs.addCommand(); rebuild() }
    @objc private func removeCommand(_ sender: NSButton) { try? configs.deleteCommand(at: sender.tag); rebuild() }
    @objc private func commitField(_ sender: NSTextField) {
        let id = sender.identifier?.rawValue ?? ""
        do {
            switch id {
            case "provider.base-url": try configs.setProvider(selectedProvider, baseURL: sender.stringValue)
            case "provider.add-name": return
            case "provider.api-key-env": try configs.setProvider(selectedProvider, apiKeyEnv: sender.stringValue)
            case "provider.model": try configs.setProvider(selectedProvider, model: sender.stringValue)
            case "provider.api-key": try configs.setProvider(selectedProvider, apiKey: .some(sender.stringValue.isEmpty ? nil : sender.stringValue))
            case "provider.temperature": try configs.setProvider(selectedProvider, temperature: .some(try validateTemperature(sender.stringValue)))
            default:
                let parts = id.split(separator: ".").map(String.init)
                if parts.count == 3, parts[0] == "command", let index = Int(parts[1]) {
                    if parts[2] == "name" { try configs.setCommand(index, name: sender.stringValue) }
                    else if parts[2] == "model" { try configs.setCommand(index, model: .some(sender.stringValue.isEmpty ? nil : sender.stringValue)) }
                }
            }
            fieldErrors.removeValue(forKey: id)
        } catch { reject(error, at: id); return }
        rebuild()
    }

    func prepareOffscreen(appearance: NSAppearance) {
        window?.appearance = appearance
        window?.contentView?.appearance = appearance
        rebuild(resize: true, animate: false)
        window?.contentView?.layoutSubtreeIfNeeded()
    }
    func control(accessibilityID: String) -> NSView? { window?.contentView.flatMap { root in ([root] + root.allSubviews).first { $0.accessibilityIdentifier() == accessibilityID } } }
    func renderPNG(to url: URL, bottom: Bool = false) throws {
        guard let content = window?.contentView else { return }
        content.layoutSubtreeIfNeeded()
        if bottom, let scroll = paneView as? NSScrollView, let document = scroll.documentView {
            document.scrollToVisible(NSRect(x: 0, y: max(0, document.bounds.maxY - 1), width: 1, height: 1))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try png.write(to: url)
    }
    func commitRecordedHotkey(accessibilityID: String, value: String) {
        (control(accessibilityID: accessibilityID) as? HotkeyRecorder)?.commitForJourney(value)
    }
    func textDidEndEditing(_ notification: Notification) {
        guard let text = notification.object as? NSTextView, let id = text.identifier?.rawValue, let index = Int(id.split(separator: ".").dropLast().last ?? "") else { return }
        do { try configs.setCommand(index, prompt: text.string); fieldErrors.removeValue(forKey: "command.\(index).prompt") }
        catch { fieldErrors["command.\(index).prompt"] = error.localizedDescription }
        rebuild()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
}
private final class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        Theme.paper.setFill()
        dirtyRect.fill()
    }
}

private final class SettingsBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.paper.setFill()
        dirtyRect.fill()
    }
}

private final class SettingsGroupView: NSView {
    override var intrinsicContentSize: NSSize {
        guard let content = subviews.first else { return .zero }
        let size = content.fittingSize
        return NSSize(width: size.width, height: size.height + 24)
    }
    override func draw(_ dirtyRect: NSRect) {
        Theme.surface.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        Theme.line.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()
    }
}

@MainActor private final class HotkeyRecorder: NSButton {
    var onCommit: ((String) -> Void)?
    private var recording = false
    private let recordsSuperKey: Bool
    init(value: String, recordsSuperKey: Bool = false) { self.recordsSuperKey = recordsSuperKey; super.init(frame: .zero); title = value.isEmpty ? "Record Shortcut" : value; font = .monospacedSystemFont(ofSize: 11, weight: .regular); bezelStyle = .rounded; target = self; action = #selector(beginRecording) }
    override var intrinsicContentSize: NSSize {
        let count = keycapLabels.count
        return NSSize(width: max(74, CGFloat(count) * 27 + CGFloat(max(0, count - 1)) * 4), height: 26)
    }
    override func draw(_ dirtyRect: NSRect) {
        let labels = keycapLabels
        guard !labels.isEmpty, !recording else { super.draw(dirtyRect); return }
        var x: CGFloat = 0
        for value in labels {
            let width = max(23, (value as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)]).width + 12)
            let frame = NSRect(x: x, y: 2, width: width, height: 22)
            Theme.surface.setFill(); NSBezierPath(roundedRect: frame, xRadius: 5, yRadius: 5).fill()
            Theme.line.setStroke(); let border = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5); border.stroke()
            value.draw(in: frame.insetBy(dx: 6, dy: 4), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: Theme.ink])
            x += width + 4
        }
    }
    private var keycapLabels: [String] {
        guard !title.isEmpty, title != "Record Shortcut" else { return [] }
        return title.split(separator: "+", omittingEmptySubsequences: false).enumerated().compactMap { index, token in
            let raw = String(token).lowercased()
            if raw.isEmpty && index > 0 { return "+" }
            switch raw { case "cmd", "command": return "⌘"; case "shift": return "⇧"; case "ctrl", "control": return "⌃"; case "opt", "option", "alt": return "⌥"; case "super", "hyper": return "◆"; default: return raw.uppercased() }
        }
    }
    required init?(coder: NSCoder) { nil }
    @objc private func beginRecording() { recording = true; title = "Press shortcut…"; window?.makeFirstResponder(self) }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { recording = false; title = "Record Shortcut"; return }
        if event.keyCode == 51 || event.keyCode == 117 { recording = false; title = "Record Shortcut"; onCommit?(""); return }
        if recordsSuperKey {
            guard let value = formatSuperKeyBinding(keyCode: UInt32(event.keyCode)) else { NSSound.beep(); return }
            recording = false; title = value; onCommit?(value)
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }; if flags.contains(.option) { modifiers |= UInt32(optionKey) }; if flags.contains(.control) { modifiers |= UInt32(controlKey) }; if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        guard modifiers != 0 else { NSSound.beep(); return }
        let value = formatHotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers); recording = false; title = value; onCommit?(value)
    }
    func commitForJourney(_ value: String) { onCommit?(value) }
}

private extension NSView {
    var allSubviews: [NSView] { subviews + subviews.flatMap(\.allSubviews) }
}
