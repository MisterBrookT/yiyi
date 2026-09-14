import AppKit
import Carbon
import YiyiCore
import OSLog

private let settingsLogger = Logger(subsystem: "cc.blackblue.yiyi", category: "settings")

private enum SettingsPane: String, CaseIterable {
    case translation = "Translation", commands = "Commands", general = "General"
    var symbol: String {
        switch self { case .translation: "character.bubble"; case .commands: "command"; case .general: "gearshape" }
    }
    var identifier: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue) }
}

@MainActor final class SettingsWindowController: NSWindowController, NSTextViewDelegate, NSTextFieldDelegate, NSWindowDelegate, NSToolbarDelegate {
    private let configs: ConfigManager
    private let liveConfigs: ConfigManager
    private var baseline: YiyiConfig
    private let confirmation: ((String) -> Bool)?
    private let footer = NSView()
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let saveStatus = NSTextField(wrappingLabelWithString: "No changes")
    private var saveError: String?
    private var closingAfterDiscard = false
    private var keyWasEntered = false
    private var keyRevealed = false
    private var approvedKeyDestination: String?
    private let accessibilityStatus: () -> AccessibilityStatus
    private let requestAccessibility: () -> Void
    private let repairAccessibility: () -> Void
    private let reloadFromDisk: () -> Void
    private let pointerStatus: () -> String
    private let launchAtLogin: (get: () -> Bool, set: (Bool) -> Void)?
    private let detail = SettingsBackgroundView()
    private var selectedPane: SettingsPane = .translation
    private var selectedCommand = 0
    private var fieldDrafts: [String: String] = [:]
    private var rebuilding = false
    private var editedFields: Set<ObjectIdentifier> = []
    private var promptSelections: [Int: NSRange] = [:]
    private var paneView: NSView?
    private var selectedProvider: String
    private var fieldErrors: [String: String] = [:]
    private var promptDrafts: [Int: String] = [:]
    /// Keep disclosure and navigation state while this settings session is alive.
    private var expandedAdvanced: Set<String> = []
    private var centered = false
    private let contentWidth: CGFloat = 640
    private let labelWidth: CGFloat = 112
    private let controlWidth: CGFloat = 376
    private var formWidth: CGFloat { labelWidth + 16 + controlWidth + 24 }

    init(
        configs: ConfigManager,
        accessibilityStatus: @escaping () -> AccessibilityStatus,
        requestAccessibility: @escaping () -> Void,
        repairAccessibility: @escaping () -> Void,
        reloadFromDisk: @escaping () -> Void,
        confirmation: ((String) -> Bool)? = nil,
        pointerStatus: @escaping () -> String = { "Off" },
        launchAtLogin: (get: () -> Bool, set: (Bool) -> Void)? = nil
    ) {
        self.liveConfigs = configs
        self.baseline = configs.config
        self.configs = configs.makeDraft()
        self.confirmation = confirmation
        self.pointerStatus = pointerStatus
        self.launchAtLogin = launchAtLogin
        self.accessibilityStatus = accessibilityStatus
        self.requestAccessibility = requestAccessibility
        self.repairAccessibility = repairAccessibility
        self.reloadFromDisk = reloadFromDisk
        selectedProvider = configs.config.defaultProvider
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        self.configs.onChange = { [weak self] in self?.saveError = nil; self?.updateFooter() }
        buildChrome()
        rebuild(resize: true, animate: false)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        if window?.isVisible != true { reloadFromDisk(); resetDraft() }
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
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelSettings))
        cancel.bezelStyle = .rounded; cancel.setAccessibilityIdentifier("settings.cancel")
        saveButton.target = self; saveButton.action = #selector(saveSettings(_:)); saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"; saveButton.setAccessibilityIdentifier("settings.save")
        saveStatus.font = .systemFont(ofSize: 11); saveStatus.textColor = .secondaryLabelColor
        saveStatus.setAccessibilityIdentifier("settings.status")
        let actions = NSStackView(views: [saveStatus, NSView(), cancel, saveButton]); actions.orientation = .horizontal; actions.spacing = 8
        footer.addSubview(actions); detail.addSubview(footer)
        footer.translatesAutoresizingMaskIntoConstraints = false; actions.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([footer.leadingAnchor.constraint(equalTo: detail.leadingAnchor), footer.trailingAnchor.constraint(equalTo: detail.trailingAnchor), footer.bottomAnchor.constraint(equalTo: detail.bottomAnchor), footer.heightAnchor.constraint(equalToConstant: 64), actions.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 24), actions.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -24), actions.centerYAnchor.constraint(equalTo: footer.centerYAnchor), saveStatus.widthAnchor.constraint(lessThanOrEqualToConstant: 380)])
        window.titlebarSeparatorStyle = .automatic
        window.toolbarStyle = .preference
        let toolbar = NSToolbar(identifier: "yiyi.settings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.selectedItemIdentifier = selectedPane.identifier
        window.toolbar = toolbar
        NotificationCenter.default.addObserver(self, selector: #selector(promptHistoryChanged(_:)), name: .NSUndoManagerDidUndoChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(promptHistoryChanged(_:)), name: .NSUndoManagerDidRedoChange, object: nil)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { SettingsPane.allCases.map(\.identifier) }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = SettingsPane(rawValue: identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = pane.rawValue; item.paletteLabel = pane.rawValue
        item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.rawValue)
        item.target = self; item.action = #selector(selectPane(_:))
        return item
    }
    @objc private func selectPane(_ sender: NSToolbarItem) {
        guard let pane = SettingsPane(rawValue: sender.itemIdentifier.rawValue) else { return }
        window?.makeFirstResponder(nil)
        selectedPane = pane
        window?.toolbar?.selectedItemIdentifier = pane.identifier
        rebuild(animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    private func rebuild(resize: Bool = true, animate: Bool = false) {
        guard !rebuilding else { return }
        rebuilding = true
        defer { rebuilding = false }
        if let editor = window?.contentView?.allSubviews.compactMap({ $0 as? NSTextView }).first(where: { $0.identifier?.rawValue.hasSuffix(".prompt") == true }) {
            if let rawIndex = editor.identifier?.rawValue.split(separator: ".").dropFirst().first, let index = Int(rawIndex) {
                promptSelections[index] = editor.selectedRange()
            }
            // AppKit's window undo manager must not retain edits targeting an editor
            // that belongs to a different command after navigation or removal.
            editor.undoManager?.removeAllActions()
        }
        paneView?.removeFromSuperview()
        let document = paneDocument()
        let documentSize = document.fittingSize
        document.frame = NSRect(origin: .zero, size: documentSize)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        detail.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: detail.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: detail.trailingAnchor), scroll.topAnchor.constraint(equalTo: detail.topAnchor), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor)])
        paneView = scroll
        document.layoutSubtreeIfNeeded()
        let desiredHeight = min(pageHeightLimit, max(360, min(620, documentSize.height + 64)))
        window?.title = "\(selectedPane.rawValue)"
        window?.minSize = NSSize(width: contentWidth, height: min(desiredHeight, 400))
        if resize { resizeWindow(to: desiredHeight, animate: animate) }
        configureKeyLoop(in: document)
        updateFooter()
    }

    /// One page: show all of it whenever the display allows, and only then scroll.
    private var pageHeightLimit: CGFloat {
        let screen = window?.screen ?? NSScreen.main
        return max(360, (screen?.visibleFrame.height ?? 900) - 140)
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
        let content: NSView
        switch selectedPane {
        case .translation: content = servicePane()
        case .commands: content = shortcutsPane()
        case .general: content = systemPane()
        }
        let document = SettingsDocumentView()
        document.setAccessibilityIdentifier("settings.page")
        document.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 56),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -56),
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -28),
            document.widthAnchor.constraint(equalToConstant: contentWidth)
        ])
        return document
    }

    private func servicePane() -> NSView {
        if configs.config.providers[selectedProvider] == nil { selectedProvider = configs.config.defaultProvider }
        guard let provider = configs.config.providers[selectedProvider] else {
            return label("The saved connection is missing. Reload your configuration in General → Advanced.", secondary: true)
        }
        // What you see is what is saved: the field shows the inline key from the config file, masked
        // by default with a reveal toggle. Keys that come from the environment or key files are not
        // shown here because they are not ours to edit; the status line says where they came from.
        let savedKey = fieldDrafts["provider.api-key"] ?? provider.apiKey ?? ""
        let key: NSTextField = keyRevealed ? NSTextField(string: savedKey) : NSSecureTextField(string: savedKey)
        style(key); key.placeholderString = "Paste your API key"
        key.identifier = NSUserInterfaceItemIdentifier("provider.api-key"); key.setAccessibilityIdentifier("provider.api-key"); key.target = self; key.action = #selector(commitField(_:))
        let reveal = NSButton(image: NSImage(systemSymbolName: keyRevealed ? "eye.slash" : "eye", accessibilityDescription: keyRevealed ? "Hide key" : "Show key")!, target: self, action: #selector(toggleKeyReveal))
        reveal.bezelStyle = .rounded; reveal.isBordered = false; reveal.toolTip = keyRevealed ? "Hide key" : "Show key"; reveal.setAccessibilityIdentifier("provider.api-key-reveal")
        reveal.widthAnchor.constraint(equalToConstant: 28).isActive = true
        let keyRow = NSStackView(views: [key, reveal]); keyRow.orientation = .horizontal; keyRow.spacing = 4
        key.setContentHuggingPriority(.defaultLow, for: .horizontal); stretch(keyRow)
        let ready = configs.providerAvailability(selectedProvider).usable
        let status = label(keySourceDescription(), secondary: true)
        status.maximumNumberOfLines = 0; status.usesSingleLineMode = false; status.lineBreakMode = .byWordWrapping
        status.preferredMaxLayoutWidth = controlWidth
        if !ready { status.textColor = Theme.attention }
        status.setAccessibilityIdentifier("provider.key-status")
        status.setAccessibilityValue(ready ? "ready" : "missing")
        stretch(status); status.heightAnchor.constraint(greaterThanOrEqualToConstant: 18).isActive = true
        let model = field(provider.model, id: "provider.model")
        let baseURL = field(provider.baseURL, id: "provider.base-url", mono: true)
        prosePlaceholder(provider.apiStyle.defaultBaseURL, in: baseURL)
        prosePlaceholder(provider.apiStyle == .anthropic ? "claude-sonnet-4-5" : "Model name from your server", in: model)
        let style = popup(APIStyle.allCases.map(\.displayName), selected: provider.apiStyle.displayName, id: "provider.api-style", action: #selector(providerStyle(_:)))
        style.identifier = NSUserInterfaceItemIdentifier(selectedProvider)
        var rows = [row("API", style), row("Base URL", baseURL), row("API key", keyRow), row("", status), row("Model", model)]
        rows.append(advancedToggle("provider"))
        if expandedAdvanced.contains("provider") {
            let env = field(provider.apiKeyEnv, id: "provider.api-key-env", mono: true)
            let temperature = field(provider.temperature.map { String($0) } ?? "", id: "provider.temperature", mono: true); prosePlaceholder("Empty to omit", in: temperature)
            let effort = popup(ReasoningEffort.allCases.map(\.rawValue), selected: provider.reasoningEffort.rawValue, id: "provider.reasoning-effort", action: #selector(providerEffort(_:))); effort.identifier = NSUserInterfaceItemIdentifier(selectedProvider)
            rows += [row("Key environment", env), row("Temperature", temperature), row("Reasoning", effort)]
        }
        appendError(for: "provider", to: &rows)
        return section("Connection", rows: rows)
    }

    private func shortcutsPane() -> NSView {
        let chooser = NSPopUpButton()
        chooser.addItems(withTitles: configs.config.commands.enumerated().map { $0.element.name.isEmpty ? "Command \($0.offset + 1)" : $0.element.name })
        selectedCommand = min(selectedCommand, max(0, configs.config.commands.count - 1))
        chooser.selectItem(at: selectedCommand)
        chooser.target = self; chooser.action = #selector(chooseCommand(_:)); chooser.setAccessibilityIdentifier("commands.selector")
        let add = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Command")!, target: self, action: #selector(addCommand))
        add.bezelStyle = .rounded; add.toolTip = "Add Command"; add.setAccessibilityIdentifier("commands.add")
        let remove = NSButton(title: "Delete…", target: self, action: #selector(removeCommand(_:)))
        remove.bezelStyle = .rounded; remove.tag = selectedCommand; remove.isEnabled = !configs.config.commands.isEmpty
        remove.setAccessibilityIdentifier("commands.delete")
        chooser.widthAnchor.constraint(equalToConstant: 228).isActive = true
        chooser.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let selection = NSStackView(views: [chooser, add, remove]); selection.orientation = .horizontal; selection.spacing = 8
        var sectionsList: [NSView] = [row("Command", selection)]
        for (index, command) in configs.config.commands.enumerated() where index == selectedCommand {
            let name = field(command.name, id: "command.\(index).name")
            // One recorder for both kinds: a modifier chord records a regular shortcut; a bare key
            // records "Hyper Key + key" when a Hyper Key is set up in General.
            let superKey = configs.config.superKey
            let hotkey = HotkeyRecorder(value: command.hotkey, allowsSuperKey: superKey != .none && superKey != .externalHyper); hotkey.onCommit = { [weak self] value in self?.commitHotkey(value, index: index) }; hotkey.setAccessibilityIdentifier("command.\(index).hotkey")
            let hint = label(shortcutHint(for: command.hotkey, superKey: superKey), secondary: true); hint.font = .systemFont(ofSize: 11)
            hint.maximumNumberOfLines = 0; hint.usesSingleLineMode = false; hint.lineBreakMode = .byWordWrapping; hint.preferredMaxLayoutWidth = controlWidth - 160
            hint.setAccessibilityIdentifier("command.\(index).hotkey-hint")
            let shortcut = NSStackView(views: [hotkey, hint]); shortcut.orientation = .horizontal; shortcut.spacing = 12; shortcut.alignment = .centerY
            let prompt = NSTextView(frame: NSRect(x: 0, y: 0, width: formWidth - 2, height: 188))
            prompt.string = promptDrafts[index] ?? command.prompt
            if let range = promptSelections[index], NSMaxRange(range) <= (prompt.string as NSString).length { prompt.setSelectedRange(range) }
            prompt.isRichText = false; prompt.allowsUndo = true; prompt.isAutomaticQuoteSubstitutionEnabled = false
            prompt.isHorizontallyResizable = false; prompt.isVerticallyResizable = true
            prompt.autoresizingMask = [.width]; prompt.textContainer?.widthTracksTextView = true
            prompt.font = .systemFont(ofSize: 13); prompt.textColor = .textColor; prompt.backgroundColor = .textBackgroundColor
            prompt.textContainerInset = NSSize(width: 12, height: 12)
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 3
            prompt.defaultParagraphStyle = paragraph
            prompt.delegate = self; prompt.identifier = NSUserInterfaceItemIdentifier("command.\(index).prompt"); prompt.setAccessibilityIdentifier("command.\(index).prompt")
            highlightPrompt(prompt)
            let promptScroll = SettingsEditorScrollView(); promptScroll.documentView = prompt; promptScroll.hasVerticalScroller = true; promptScroll.autohidesScrollers = true
            promptScroll.borderType = .noBorder
            promptScroll.heightAnchor.constraint(equalToConstant: 188).isActive = true
            promptScroll.widthAnchor.constraint(equalToConstant: formWidth).isActive = true
            promptScroll.wantsLayer = true; promptScroll.layer?.cornerRadius = 8; promptScroll.layer?.masksToBounds = true
            let promptStatus = label(fieldErrors["command.\(index).prompt"] ?? "", secondary: true)
            promptStatus.identifier = NSUserInterfaceItemIdentifier("command.\(index).prompt.status")
            promptStatus.setAccessibilityIdentifier(fieldErrors["command.\(index).prompt"] == nil ? "command.\(index).prompt.status" : "command.\(index).prompt.error")
            promptStatus.textColor = fieldErrors["command.\(index).prompt"] == nil ? Theme.muted : .systemRed
            promptStatus.font = .systemFont(ofSize: 11)
            promptStatus.widthAnchor.constraint(equalToConstant: formWidth).isActive = true
            let insert = NSButton(title: "Selected Text", target: self, action: #selector(insertSelection))
            insert.bezelStyle = .rounded; insert.controlSize = .small; insert.font = .systemFont(ofSize: 11)
            insert.toolTip = "Insert {selection} at the cursor. yiyi replaces it with the text you select."
            insert.setAccessibilityIdentifier("command.\(index).insert-selection")
            let promptHeading = label("Prompt"); promptHeading.font = .systemFont(ofSize: 13, weight: .semibold)
            let clipboard = NSButton(title: "Clipboard Text", target: self, action: #selector(insertClipboard))
            clipboard.bezelStyle = .rounded; clipboard.controlSize = .small; clipboard.font = .systemFont(ofSize: 11)
            clipboard.toolTip = "Insert {clipboard}. Uses clipboard text from before the command runs."
            clipboard.setAccessibilityIdentifier("command.\(index).insert-clipboard")
            let spacer = NSView()
            let promptHeader = NSStackView(views: [promptHeading, spacer, insert, clipboard]); promptHeader.orientation = .horizontal; promptHeader.alignment = .centerY
            promptHeader.widthAnchor.constraint(equalToConstant: formWidth).isActive = true
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let promptGroup = column([promptHeader, promptScroll, promptStatus], spacing: 8)
            // Advanced lives inside the command card, like the connection card, so the disclosure
            // never floats alone between sections.
            var rows = [row("Name", name), row("Shortcut", shortcut), advancedToggle("command.\(index)")]
            if expandedAdvanced.contains("command.\(index)") {
                if let override = command.provider, let connection = configs.config.providers[override] {
                    let reset = NSButton(title: "Use main connection", target: self, action: #selector(clearCommandConnection(_:))); reset.tag = index
                    reset.setAccessibilityIdentifier("command.\(index).use-default-connection")
                    rows += [row("Connection override", label(connection.baseURL, secondary: true)), row("", reset)]
                }
                let model = field(command.model ?? "", id: "command.\(index).model", mono: true); prosePlaceholder("Inherit", in: model)
                let effort = popup(["inherit"] + ReasoningEffort.allCases.map(\.rawValue), selected: command.reasoningEffort?.rawValue ?? "inherit", id: "command.\(index).reasoning-effort", action: #selector(commandEffort(_:))); effort.tag = index
                rows += [row("Model override", model), row("Reasoning", effort)]
            }
            appendError(for: "command.\(index)", to: &rows)
            sectionsList.append(section("", rows: rows))
            sectionsList.append(promptGroup)
        }
        if configs.config.commands.isEmpty {
            let empty = label("Add a command to choose a shortcut and write its prompt.", secondary: true)
            empty.widthAnchor.constraint(equalToConstant: formWidth).isActive = true
            empty.setAccessibilityIdentifier("commands.empty")
            sectionsList.append(empty)
        }
        appendError(for: "commands", to: &sectionsList)
        return column(sectionsList, spacing: 20)
    }

    private func systemPane() -> NSView {
        let copy = NSButton(checkboxWithTitle: "Copy translations to the clipboard", target: self, action: #selector(changeAutoCopy(_:))); copy.state = configs.config.autoCopy ? .on : .off; copy.setAccessibilityIdentifier("provider.auto-copy")
        let status = accessibilityStatus()
        let trusted = label(status.trusted ? "Accessibility trusted" : "Accessibility not granted", secondary: status.trusted); trusted.setAccessibilityIdentifier("permission.trusted"); trusted.setAccessibilityValue(status.trusted ? "yes" : "no")
        var rows = [row("Clipboard", copy)]
        if let launchAtLogin {
            let login = NSButton(checkboxWithTitle: "Open yiyi at login", target: self, action: #selector(changeLaunchAtLogin(_:)))
            login.state = launchAtLogin.get() ? .on : .off
            login.setAccessibilityIdentifier("system.launch-at-login")
            rows.append(row("Startup", login))
        }
        rows.append(row("Accessibility", trusted))
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
        appendError(for: "general", to: &rows)
        return column([triggersSection(), section("General", rows: rows)], spacing: 24)
    }
    /// The two ways to start a command without a plain keyboard shortcut. Both are global, so they live here rather than per command.
    /// The two ways to start a command: from the keyboard or from the pointer. Each card opens with a
    /// small picture of the gesture, the same illustration the website uses, so the setting is
    /// recognisable before reading a word.
    private func triggersSection() -> NSView {
        let superKey = configs.config.superKey
        let hyper = popup(SuperKey.allCases.map(\.displayName), selected: superKey.displayName, id: "superkey.popup", action: #selector(changeSuperKey(_:)))
        hyper.toolTip = "Use a right-side modifier for yiyi, or choose External Hyper for an existing ⌃⌥⇧⌘ remap."
        let keyboardBlurb = superKey == .none
            ? "Each command has its own shortcut, set under Commands. Add a Hyper Key to trigger commands with one right-side modifier plus a letter."
            : "Each command has its own shortcut, set under Commands. Hold \(superKey.displayName) and tap a command's key."
        let keyboardRows = [triggerIntro(image: inputDeckImage(pressedKeys: ["⌘", "⇧", "T"], fingerOnTrackpad: false, size: NSSize(width: 168, height: 95)), text: keyboardBlurb), row("Hyper Key", hyper)]
        let keyboard = section("Keyboard", rows: keyboardRows)

        let pointer = NSButton(checkboxWithTitle: "Press and hold to translate (experimental)", target: self, action: #selector(changePointer(_:)))
        pointer.state = configs.config.pointerTrigger.enabled ? .on : .off
        pointer.isEnabled = !configs.config.commands.isEmpty
        pointer.setAccessibilityIdentifier("pointer.enabled")
        var pointerRows = [triggerIntro(image: inputDeckImage(pressedKeys: [], fingerOnTrackpad: true, size: NSSize(width: 168, height: 95)), text: "Select text, then press the trackpad or mouse button and hold still for half a second. The command starts while you hold. Clicks and drags are unchanged."), row("Gesture", pointer)]
        if configs.config.pointerTrigger.enabled {
            let command = popup(configs.config.commands.map(\.name), selected: "", id: "pointer.command", action: #selector(changePointerCommand(_:)))
            command.selectItem(at: configs.config.pointerTrigger.commandIndex)
            pointerRows += [row("Run command", command), row("Status", label(configs.config.pointerTrigger == baseline.pointerTrigger ? pointerStatus() : "Applies after Save", secondary: true))]
            let permission = NSButton(title: "Input Monitoring Settings…", target: self, action: #selector(openInputMonitoring))
            pointerRows.append(row("", permission))
        }
        let mouse = section("Mouse / trackpad", rows: pointerRows)
        return column([keyboard, mouse], spacing: 24)
    }
    private func triggerIntro(image: NSImage, text: String) -> NSView {
        let picture = NSImageView(image: image); picture.imageScaling = .scaleProportionallyDown
        picture.widthAnchor.constraint(equalToConstant: image.size.width).isActive = true
        picture.heightAnchor.constraint(equalToConstant: image.size.height).isActive = true
        let blurb = label(text, secondary: true); blurb.font = .systemFont(ofSize: 12)
        blurb.maximumNumberOfLines = 0; blurb.usesSingleLineMode = false; blurb.lineBreakMode = .byWordWrapping
        let width = labelWidth + 16 + controlWidth
        blurb.preferredMaxLayoutWidth = width - image.size.width - 20
        let intro = NSStackView(views: [picture, blurb]); intro.orientation = .horizontal; intro.spacing = 20; intro.alignment = .centerY
        intro.widthAnchor.constraint(equalToConstant: width).isActive = true
        return intro
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
        heading.attributedStringValue = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor])
        let slug = title.lowercased().replacingOccurrences(of: " ", with: "-")
        heading.setAccessibilityIdentifier("section.\(slug)"); heading.widthAnchor.constraint(equalToConstant: formWidth).isActive = true; heading.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let rowStack = column(rows, spacing: 12)
        let panel = SettingsGroupView(); panel.addSubview(rowStack); rowStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([rowStack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12), rowStack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12), rowStack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16), rowStack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -16), panel.widthAnchor.constraint(equalToConstant: formWidth)])
        return title.isEmpty ? panel : column([heading, panel], spacing: 8)
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
    private func label(_ text: String, mono: Bool = false, secondary: Bool = false) -> NSTextField { let value = NSTextField(wrappingLabelWithString: text); value.font = mono ? .monospacedSystemFont(ofSize: 11, weight: .regular) : .systemFont(ofSize: 13); value.textColor = secondary ? .secondaryLabelColor : .labelColor; return value }
    private func stretch(_ view: NSView) { view.widthAnchor.constraint(equalToConstant: controlWidth).isActive = true }
    private func field(_ value: String, id: String, mono: Bool = false) -> NSTextField { let field = NSTextField(string: fieldDrafts[id] ?? value); style(field); if mono { field.font = .monospacedSystemFont(ofSize: 12, weight: .regular) }; field.identifier = NSUserInterfaceItemIdentifier(id); field.setAccessibilityIdentifier(id); field.target = self; field.action = #selector(commitField(_:)); stretch(field); return field }
    private func style(_ field: NSTextField) { field.font = .systemFont(ofSize: 13); field.isBezeled = true; field.bezelStyle = .roundedBezel; field.delegate = self }
    private func popup(_ values: [String], selected: String, id: String, action: Selector) -> NSPopUpButton { let popup = NSPopUpButton(); popup.addItems(withTitles: values); popup.selectItem(withTitle: selected); popup.target = self; popup.action = action; popup.setAccessibilityIdentifier(id); return popup }

    private func prosePlaceholder(_ value: String, in field: NSTextField) {
        field.placeholderAttributedString = NSAttributedString(string: value, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.placeholderTextColor
        ])
    }

    private func appendError(for prefix: String, to rows: inout [NSView]) {
        for match in fieldErrors.filter({ ($0.key == prefix || $0.key.hasPrefix(prefix + ".")) && !$0.key.hasSuffix(".prompt") }).sorted(by: { $0.key < $1.key }) {
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
        let controls = (root.allSubviews + footer.allSubviews).filter { ($0 as? NSControl)?.isEnabled == true || $0 is NSTextView }
        for (current, next) in zip(controls, controls.dropFirst() + controls.prefix(1)) { current.nextKeyView = next }
        window?.initialFirstResponder = controls.first
    }

    @objc private func toggleKeyReveal() {
        if let field = control(accessibilityID: "provider.api-key") as? NSTextField,
           field.stringValue != (configs.config.providers[selectedProvider]?.apiKey ?? "") { fieldDrafts["provider.api-key"] = field.stringValue }
        keyRevealed.toggle(); rebuild()
    }
    /// Plain-language origin of the key that will actually be sent.
    private func keySourceDescription() -> String {
        guard let provider = configs.config.providers[selectedProvider] else { return "" }
        if let key = provider.apiKey, !key.isEmpty { return "Saved in yiyi's config file." }
        let raw = liveConfigs.apiKeyStatus(for: selectedProvider)
        if raw.contains("environment") { return "Using $\(provider.apiKeyEnv) from your environment." }
        if raw.contains(".env") { return "Using \(provider.apiKeyEnv) from ~/.config/yiyi/.env." }
        if raw.contains("apikey") { return "Using the key in ~/.config/yiyi/apikey." }
        return "No API key yet. Paste the key supplied by your server."
    }
    @objc private func providerStyle(_ sender: NSPopUpButton) {
        guard let name = sender.identifier?.rawValue, let title = sender.titleOfSelectedItem,
              let value = APIStyle.allCases.first(where: { $0.displayName == title }),
              let provider = configs.config.providers[name], provider.apiStyle != value else { return }
        do {
            // Swap in the matching public endpoint when the URL is still the other protocol's default.
            let swapURL = provider.baseURL.isEmpty || provider.baseURL == provider.apiStyle.defaultBaseURL
            try configs.setProvider(name, baseURL: swapURL ? value.defaultBaseURL : nil, apiStyle: value)
        } catch { reject(error, at: "provider.api-style"); return }
        rebuild()
    }
    @objc private func providerEffort(_ sender: NSPopUpButton) { guard let name = sender.identifier?.rawValue, let value = sender.titleOfSelectedItem.flatMap(ReasoningEffort.init(rawValue:)) else { return }; do { try configs.setProvider(name, reasoningEffort: value) } catch { reject(error, at: "provider.reasoning-effort"); return }; rebuild() }
    @objc private func clearCommandConnection(_ sender: NSButton) {
        do { try configs.setCommand(sender.tag, provider: .some(nil)) }
        catch { reject(error, at: "command.\(sender.tag).provider"); return }
        rebuild()
    }
    private func shortcutHint(for hotkey: String, superKey: SuperKey) -> String {
        let isHyper = hotkey.hasPrefix("super+") || hotkey.hasPrefix("hyper+")
        switch superKey {
        case .none: return isHyper ? "Needs a Hyper Key. Choose one in General → Keyboard." : "Press a key combination."
        case .externalHyper: return isHyper ? "Fires with your external ⌃⌥⇧⌘ Hyper Key." : "Press a key combination."
        default: return isHyper ? "Hold \(superKey.displayName), tap the key." : "Press a key combination, or a single key to pair with \(superKey.displayName)."
        }
    }
    @objc private func commandEffort(_ sender: NSPopUpButton) { let raw = sender.titleOfSelectedItem; do { try configs.setCommand(sender.tag, reasoningEffort: raw == "inherit" ? .some(nil) : .some(raw.flatMap(ReasoningEffort.init(rawValue:)))) } catch { reject(error, at: "command.\(sender.tag).reasoning-effort"); return }; rebuild() }
    @objc private func changeSuperKey(_ sender: NSPopUpButton) {
        guard let selected = sender.titleOfSelectedItem, let value = SuperKey.allCases.first(where: { $0.displayName == selected }) else { return }
        do { try configs.setSuperKey(value); fieldErrors.removeValue(forKey: "general.leader") }
        catch { reject(error, at: "general.leader"); return }
        rebuild()
    }
    @objc private func changePointer(_ sender: NSButton) {
        var value = configs.config.pointerTrigger; value.enabled = sender.state == .on
        if !configs.config.commands.indices.contains(value.commandIndex) { value.commandIndex = 0 }
        do { try configs.setPointerTrigger(value) } catch { reject(error, at: "general.pointer"); return }
        rebuild()
    }
    @objc private func changePointerCommand(_ sender: NSPopUpButton) {
        var value = configs.config.pointerTrigger; value.commandIndex = sender.indexOfSelectedItem
        do { try configs.setPointerTrigger(value) } catch { reject(error, at: "general.pointer") }
    }
    @objc private func openInputMonitoring() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") { NSWorkspace.shared.open(url) }
    }
    /// Applies immediately: this is a system registration, not part of the saved draft.
    @objc private func changeLaunchAtLogin(_ sender: NSButton) {
        launchAtLogin?.set(sender.state == .on)
        sender.state = launchAtLogin?.get() == true ? .on : .off
    }
    @objc private func changeAutoCopy(_ sender: NSButton) {
        do { try configs.setAutoCopy(sender.state == .on); fieldErrors.removeValue(forKey: "general.clipboard") }
        catch { reject(error, at: "general.clipboard"); return }
    }
    @objc private func toggleAdvanced(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        window?.makeFirstResponder(nil)
        if expandedAdvanced.contains(id) { expandedAdvanced.remove(id) } else { expandedAdvanced.insert(id) }
        rebuild()
    }
    @objc private func enableAccessibility() { requestAccessibility(); rebuild() }
    @objc private func editConfigFile() { NSWorkspace.shared.open(configs.fileURL) }
    @objc private func reloadFromFile() {
        window?.makeFirstResponder(nil)
        let reload = { [weak self] in guard let self else { return }; self.reloadFromDisk(); self.resetDraft(); self.rebuild() }
        if hasUnsavedChanges { confirmAction("Discard unsaved changes?", detail: "Reloading replaces your edits with the saved settings.", button: "Discard", completion: reload) }
        else { reload() }
    }
    @objc private func repairAccessibilityPermission() { repairAccessibility(); rebuild() }
    @objc private func chooseCommand(_ sender: NSPopUpButton) {
        if let editor = control(accessibilityID: "command.\(selectedCommand).prompt") as? NSTextView { promptSelections[selectedCommand] = editor.selectedRange() }
        window?.makeFirstResponder(nil)
        selectedCommand = sender.indexOfSelectedItem
        rebuild()
    }
    @objc private func insertSelection() { insertPromptToken("{selection}") }
    @objc private func insertClipboard() { insertPromptToken("{clipboard}") }
    private func insertPromptToken(_ token: String) {
        guard let editor = control(accessibilityID: "command.\(selectedCommand).prompt") as? NSTextView else { return }
        window?.makeFirstResponder(editor)
        let text = editor.string as NSString
        let range = editor.selectedRange()
        if range.length == token.utf16.count, text.substring(with: range) == token { return }
        // Repeated clicks should select the placeholder, not duplicate the input.
        if range.length == 0, range.location >= token.utf16.count {
            let preceding = NSRange(location: range.location - token.utf16.count, length: token.utf16.count)
            if text.substring(with: preceding) == token {
                editor.setSelectedRange(preceding); editor.scrollRangeToVisible(preceding); return
            }
        }
        editor.insertText(token, replacementRange: range)
    }
    @objc private func addCommand() {
        window?.makeFirstResponder(nil)
        do { try configs.addCommand(); selectedCommand = configs.config.commands.count - 1 }
        catch { reject(error, at: "commands.add"); return }
        rebuild()
    }
    @objc private func removeCommand(_ sender: NSButton) {
        window?.makeFirstResponder(nil)
        let index = sender.tag
        guard configs.config.commands.indices.contains(index) else { return }
        confirmAction("Delete “\(configs.config.commands[index].name)”?", detail: "Its prompt and shortcut will be removed when you save.", button: "Delete") { [weak self] in
            guard let self else { return }
            do {
                try self.configs.deleteCommand(at: index)
                self.promptDrafts = Dictionary(uniqueKeysWithValues: self.promptDrafts.filter { $0.key != index }.map { ($0.key > index ? $0.key - 1 : $0.key, $0.value) })
                self.fieldErrors = self.fieldErrors.filter { !$0.key.hasPrefix("command.") }
                self.fieldDrafts = self.fieldDrafts.filter { !$0.key.hasPrefix("command.") }
                self.promptSelections.removeAll()
                self.selectedCommand = min(index, max(0, self.configs.config.commands.count - 1))
            } catch { self.reject(error, at: "commands.remove"); return }
            self.rebuild()
        }
    }
    @objc private func commitField(_ sender: NSTextField) {
        let id = sender.identifier?.rawValue ?? ""
        let hadError = fieldErrors[id] != nil
        editedFields.remove(ObjectIdentifier(sender))
        do {
            switch id {
            case "provider.base-url": try configs.setProvider(selectedProvider, baseURL: sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
            case "provider.api-key-env": try configs.setProvider(selectedProvider, apiKeyEnv: sender.stringValue)
            case "provider.model": try configs.setProvider(selectedProvider, model: sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
            case "provider.api-key":
                let entered = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let previous = configs.config.providers[selectedProvider]?.apiKey ?? ""
                if entered != previous {
                    // Clearing the field removes the inline key; other key sources still apply.
                    try configs.setProvider(selectedProvider, apiKey: .some(entered.isEmpty ? nil : entered))
                    keyWasEntered = !entered.isEmpty
                }
            case "provider.temperature": try configs.setProvider(selectedProvider, temperature: .some(try validateTemperature(sender.stringValue)))
            default:
                let parts = id.split(separator: ".").map(String.init)
                if parts.count == 3, parts[0] == "command", let index = Int(parts[1]) {
                    if parts[2] == "name" { try configs.setCommand(index, name: sender.stringValue) }
                    else if parts[2] == "model" { try configs.setCommand(index, model: .some(sender.stringValue.isEmpty ? nil : sender.stringValue)) }
                }
            }
            fieldErrors.removeValue(forKey: id)
            fieldDrafts.removeValue(forKey: id)
        } catch {
            if id != "provider.api-key" { fieldDrafts[id] = sender.stringValue }
            reject(error, at: id); return
        }
        if let chooser = control(accessibilityID: "commands.selector") as? NSPopUpButton, configs.config.commands.indices.contains(selectedCommand) {
            chooser.item(at: selectedCommand)?.title = configs.config.commands[selectedCommand].name
        }
        if id == "provider.api-key" {
            let ready = configs.providerAvailability(selectedProvider).usable
            let status = control(accessibilityID: "provider.key-status") as? NSTextField
            status?.stringValue = keySourceDescription()
            status?.textColor = ready ? .secondaryLabelColor : Theme.attention
            status?.setAccessibilityValue(ready ? "ready" : "missing")
        }
        saveError = nil
        updateFooter()
        if hadError { rebuild() }
    }
    func controlTextDidChange(_ notification: Notification) {
        if let field = notification.object as? NSTextField { editedFields.insert(ObjectIdentifier(field)); saveError = nil; updateFooter() }
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, editedFields.contains(ObjectIdentifier(field)) else { return }
        commitField(field)
    }

    func prepareOffscreen(appearance: NSAppearance) {
        window?.appearance = appearance
        window?.contentView?.appearance = appearance
        rebuild(resize: true, animate: false)
        window?.contentView?.layoutSubtreeIfNeeded()
    }
    /// The staged, unsaved configuration. Journeys use it to tell staging apart from persistence.
    var draftConfig: YiyiConfig { configs.config }
    func control(accessibilityID: String) -> NSView? { window?.contentView.flatMap { root in ([root] + root.allSubviews).first { $0.accessibilityIdentifier() == accessibilityID } } }
    func renderPNG(to url: URL, bottom: Bool = false) throws {
        guard let content = window?.contentView?.superview else { return }
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
    @objc private func promptHistoryChanged(_ notification: Notification) {
        guard let editor = control(accessibilityID: "command.\(selectedCommand).prompt") as? NSTextView,
              let history = notification.object as? UndoManager, editor.undoManager === history else { return }
        // Undo changes text storage without sending the normal typing notification.
        persistPrompt(Notification(name: NSText.didChangeNotification, object: editor))
    }
    func textDidChange(_ notification: Notification) { persistPrompt(notification) }
    func textDidEndEditing(_ notification: Notification) { persistPrompt(notification) }

    private func persistPrompt(_ notification: Notification) {
        guard let text = notification.object as? NSTextView, let id = text.identifier?.rawValue else { return }
        let parts = id.split(separator: ".")
        guard parts.count == 3, parts[0] == "command", parts[2] == "prompt", let index = Int(parts[1]), configs.config.commands.indices.contains(index) else { return }
        promptDrafts[index] = text.string
        // Leave IME composition and its marked attributes alone until text is committed.
        guard !text.hasMarkedText() else { updateFooter(); return }
        do {
            if configs.config.commands[index].prompt != text.string { try configs.setCommand(index, prompt: text.string) }
            promptDrafts.removeValue(forKey: index)
            fieldErrors.removeValue(forKey: id)
        } catch { fieldErrors[id] = "Not saved: \(error.localizedDescription)" }
        // Keep the editor and selection alive; rebuilding here can discard a draft
        // and swallow the click that ended editing.
        let status = window?.contentView?.allSubviews.first { $0.identifier?.rawValue == "\(id).status" } as? NSTextField
        status?.stringValue = fieldErrors[id] ?? ""
        status?.textColor = fieldErrors[id] == nil ? Theme.muted : .systemRed
        status?.setAccessibilityIdentifier(fieldErrors[id] == nil ? "\(id).status" : "\(id).error")
        highlightPrompt(text)
        saveError = nil
        updateFooter()
    }

    private var hasUnsavedChanges: Bool { configs.config != baseline || !promptDrafts.isEmpty || !fieldDrafts.isEmpty || !editedFields.isEmpty }
    private func updateFooter() {
        saveButton.isEnabled = hasUnsavedChanges && fieldErrors.isEmpty
        saveStatus.stringValue = saveError ?? (fieldErrors.isEmpty ? (hasUnsavedChanges ? "Unsaved changes" : "No changes") : "Review the highlighted fields.")
        saveStatus.textColor = saveError == nil ? .secondaryLabelColor : .systemRed
        window?.isDocumentEdited = hasUnsavedChanges
    }
    private func resetDraft() {
        baseline = liveConfigs.config
        promptDrafts.removeAll(); fieldDrafts.removeAll(); fieldErrors.removeAll(); editedFields.removeAll()
        promptSelections.removeAll(); saveError = nil
        selectedProvider = baseline.defaultProvider
        keyWasEntered = false; approvedKeyDestination = nil
        configs.resetDraft(to: baseline)
    }
    @objc func saveSettings(_ sender: Any?) {
        window?.makeFirstResponder(nil)
        guard fieldErrors.isEmpty else { updateFooter(); return }
        do {
            if let provider = configs.config.providers[selectedProvider] { try validateConnection(provider) }
            for (index, command) in configs.config.commands.enumerated() {
                try validateCommand(name: command.name, hotkey: command.hotkey, prompt: command.prompt, commands: configs.config.commands, excluding: index)
                if configs.config.superKey == .none, command.hotkey.hasPrefix("super+") || command.hotkey.hasPrefix("hyper+") { throw SettingsSaveError.hyperKeyDisabled }
            }
            if let previous = baseline.providers[selectedProvider], let candidate = configs.config.providers[selectedProvider],
               requiresKeyDestinationConfirmation(from: previous.baseURL, to: candidate.baseURL),
               !keyWasEntered, approvedKeyDestination != candidate.baseURL, configs.providerAvailability(selectedProvider).usable {
                confirmAction("Use the existing API key with this server?", detail: "The connection address changed. Only continue if you trust the new server with your existing key.", button: "Use Key and Save") { [weak self] in
                    self?.approvedKeyDestination = candidate.baseURL; self?.saveSettings(nil)
                }
                return
            }
            try liveConfigs.apply(configs.config, replacing: baseline)
            baseline = configs.config
            keyWasEntered = false; approvedKeyDestination = nil
            saveError = nil
            updateFooter()
            saveStatus.stringValue = "Saved"
        } catch { saveError = error.localizedDescription; updateFooter() }
    }
    @objc private func cancelSettings() { window?.performClose(nil) }
    private func confirmAction(_ title: String, detail: String, button: String, completion: @escaping () -> Void) {
        if let confirmation { if confirmation(title) { completion() }; return }
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: "Keep Editing"); alert.addButton(withTitle: button)
        alert.beginSheetModal(for: window) { response in if response == .alertSecondButtonReturn { completion() } }
    }
    func confirmDiscardForTermination(_ completion: @escaping (Bool) -> Void) {
        window?.makeFirstResponder(nil)
        guard hasUnsavedChanges else { completion(true); return }
        if let confirmation { completion(confirmation("Quit without saving?")); return }
        guard let window, window.attachedSheet == nil else { completion(false); return }
        let alert = NSAlert(); alert.messageText = "Quit without saving?"
        alert.informativeText = "Your unsaved settings will be discarded."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Quit Without Saving")
        alert.beginSheetModal(for: window) { completion($0 == .alertSecondButtonReturn) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.makeFirstResponder(nil)
        if closingAfterDiscard { closingAfterDiscard = false; return true }
        guard hasUnsavedChanges else { return true }
        confirmAction("Discard unsaved changes?", detail: "Your saved commands and connection will not change.", button: "Discard") { [weak self] in
            guard let self else { return }; self.resetDraft(); self.closingAfterDiscard = true; self.window?.performClose(nil)
        }
        return false
    }
}
private final class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        Theme.settingsBackground.setFill()
        dirtyRect.fill()
    }
}

private final class SettingsBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.settingsBackground.setFill()
        dirtyRect.fill()
    }
}

private final class SettingsGroupView: NSView {
    override var intrinsicContentSize: NSSize {
        guard let content = subviews.first else { return .zero }
        let size = content.fittingSize
        return NSSize(width: size.width + 24, height: size.height + 32)
    }
    override func draw(_ dirtyRect: NSRect) {
        Theme.settingsSurface.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        Theme.settingsBorder.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        border.lineWidth = 1
        border.stroke()
    }
}

@MainActor private final class SettingsEditorScrollView: NSScrollView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = Theme.settingsBorder.cgColor
        }
        layer?.borderWidth = 1
        layer?.cornerRadius = 8
    }
}

@MainActor private final class HotkeyRecorder: NSButton {
    var onCommit: ((String) -> Void)?
    private var recording = false
    private let allowsSuperKey: Bool
    private let originalValue: String
    init(value: String, allowsSuperKey: Bool = false) { self.allowsSuperKey = allowsSuperKey; originalValue = value; super.init(frame: .zero); title = value.isEmpty ? "Record Shortcut" : value; font = .monospacedSystemFont(ofSize: 11, weight: .regular); bezelStyle = .rounded; target = self; action = #selector(beginRecording) }
    override var intrinsicContentSize: NSSize {
        if recording || title == "Record Shortcut" { return NSSize(width: 146, height: 26) }
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
        if event.keyCode == 53 { recording = false; title = originalValue.isEmpty ? "Record Shortcut" : originalValue; return }
        if event.keyCode == 51 || event.keyCode == 117 { recording = false; title = "Record Shortcut"; onCommit?(""); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }; if flags.contains(.option) { modifiers |= UInt32(optionKey) }; if flags.contains(.control) { modifiers |= UInt32(controlKey) }; if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if modifiers == 0 {
            // A bare key only means something together with a Hyper Key.
            guard allowsSuperKey, let value = formatSuperKeyBinding(keyCode: UInt32(event.keyCode)) else { NSSound.beep(); return }
            recording = false; title = value; onCommit?(value)
            return
        }
        let value = formatHotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers); recording = false; title = value; onCommit?(value)
    }
    func commitForJourney(_ value: String) { onCommit?(value) }
}

private extension NSView {
    var allSubviews: [NSView] { subviews + subviews.flatMap(\.allSubviews) }
}
