import AppKit
import YiyiCore

/// Real AppKit controls and persistence, always against disposable configuration.
@MainActor func runUIJourney(outdir: URL) throws {
    guard let path = ProcessInfo.processInfo.environment["YIYI_CONFIG_DIR"], !path.isEmpty else { throw failure("An isolated YIYI_CONFIG_DIR is required") }
    let manager = ConfigManager()
    let real = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/yiyi").resolvingSymlinksInPath()
    guard manager.directory.resolvingSymlinksInPath() != real else { throw failure("Never test against live configuration") }
    try FileManager.default.createDirectory(at: outdir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: manager.directory, withIntermediateDirectories: true)
    let seed = YiyiConfig(defaultProvider: "connection", providers: [
        "connection": ProviderConfig(baseURL: "https://api.example.com/v1", model: "your-model", apiKeyEnv: "EXAMPLE_API_KEY", apiKey: "test-only-not-a-real-key"),
        "legacy": ProviderConfig(baseURL: "https://legacy.example/v1", model: "legacy-model", apiKeyEnv: "LEGACY_KEY")
    ], commands: [
        CommandConfig(name: "Translate to Chinese", hotkey: "cmd+1", prompt: "Translate into Chinese.\nAdd IPA and Chinese meanings\nfor difficult words.\n\n{selection}"),
        CommandConfig(name: "Translate to English", hotkey: "cmd+2", provider: "legacy", prompt: "Translate into English: {selection}")
    ])
    try JSONEncoder().encode(seed).write(to: manager.fileURL)
    try manager.load()
    let original = try Data(contentsOf: manager.fileURL)
    var allowConfirmation = true
    var confirmations = 0
    var notifications = 0
    manager.onChange = { notifications += 1 }
    let status = AccessibilityStatus(trusted: true, superKeyTapStatus: "Ready", signatureIdentity: "Local build", advice: .ok)
    let controller = SettingsWindowController(configs: manager, accessibilityStatus: { status }, requestAccessibility: {}, repairAccessibility: {}, reloadFromDisk: { try? manager.load() }, confirmation: { _ in confirmations += 1; return allowConfirmation })
    let light = NSAppearance(named: .aqua)!, dark = NSAppearance(named: .darkAqua)!
    var checks: [[String: Any]] = []
    func check(_ name: String, _ passed: @autoclosure () throws -> Bool) throws {
        let result = try passed(); checks.append(["name": name, "passed": result])
        try JSONSerialization.data(withJSONObject: ["passed": result, "checks": checks], options: [.prettyPrinted, .sortedKeys]).write(to: outdir.appendingPathComponent("assertions.json"))
        guard result else { throw failure(name) }
    }
    func view<T: NSView>(_ id: String, as type: T.Type = T.self) throws -> T {
        guard let value = controller.control(accessibilityID: id) as? T else { throw failure("Missing control: \(id)") }; return value
    }
    func act(_ control: NSControl) { if let action = control.action { _ = NSApp.sendAction(action, to: control.target, from: control) } }
    func press(_ id: String) throws { act(try view(id, as: NSControl.self)) }
    func page(_ name: String) throws {
        guard let item = controller.window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == name }), let action = item.action else { throw failure("Missing page: \(name)") }
        _ = NSApp.sendAction(action, to: item.target, from: item)
    }
    func choose(_ id: String, _ title: String) throws { let popup = try view(id, as: NSPopUpButton.self); popup.selectItem(withTitle: title); act(popup) }
    func commit(_ id: String, _ text: String) throws { let field = try view(id, as: NSTextField.self); field.stringValue = text; act(field) }
    func persisted() throws -> YiyiConfig { try JSONDecoder().decode(YiyiConfig.self, from: Data(contentsOf: manager.fileURL)) }
    func prompt(_ text: String, index: Int = 0) throws {
        let editor = try view("command.\(index).prompt", as: NSTextView.self)
        controller.window?.makeFirstResponder(editor)
        editor.insertText(text, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
    }
    func reload() throws {
        try page("General")
        if (controller.control(accessibilityID: "system.advanced") as? NSButton)?.state != .on { try press("system.advanced") }
        try press("system.reload-config")
    }
    func snapshot(_ name: String) throws {
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let root = try view("settings.page", as: NSView.self)
        let overflow = ([root] + root.descendants).contains { child in
            guard child is NSControl, !(child is NSTextView), child.bounds.width > 0 else { return false }
            let rect = root.convert(child.bounds, from: child)
            return rect.minX < -1 || rect.maxX > root.bounds.maxX + 1
        }
        try check("geometry.\(name)", !overflow)
        try controller.renderPNG(to: outdir.appendingPathComponent(name + ".png"))
    }
    controller.prepareOffscreen(appearance: light)
    try check("native.toolbar", controller.window?.toolbar?.items.map(\.label) == ["Commands", "Connection", "General"])
    try check("opens-on-commands", controller.control(accessibilityID: "commands.selector") != nil)
    try page("Connection")
    try check("connection.generic", controller.control(accessibilityID: "provider.base-url") != nil && controller.control(accessibilityID: "provider.selector") == nil)
    try check("connection.key-masked-and-shown", try view("provider.api-key", as: NSSecureTextField.self).stringValue == seed.providers["connection"]?.apiKey)
    try press("provider.api-key-reveal")
    try check("connection.key-revealed", { let f = try view("provider.api-key", as: NSTextField.self); return !(f is NSSecureTextField) && f.stringValue == seed.providers["connection"]?.apiKey }())
    try press("provider.api-key-reveal")
    try check("connection.key-rehidden", controller.control(accessibilityID: "provider.api-key") is NSSecureTextField)
    try check("connection.style-default", try view("provider.api-style", as: NSPopUpButton.self).titleOfSelectedItem == "OpenAI-compatible")
    try choose("provider.api-style", "Anthropic")
    try check("connection.style-staged", controller.draftConfig.providers[controller.draftConfig.defaultProvider]?.apiStyle == .anthropic)
    try check("connection.style-not-persisted", try persisted().providers[controller.draftConfig.defaultProvider]?.apiStyle == .openAI)
    try choose("provider.api-style", "OpenAI-compatible")
    try check("connection.style-reverted", try !view("settings.save", as: NSButton.self).isEnabled)
    try check("save.initially-disabled", try !view("settings.save", as: NSButton.self).isEnabled)
    try snapshot("light-connection")
    let frozenRequestConfig = manager.makeDraft()
    try commit("provider.model", "changed-model")
    try commit("provider.api-key", "replacement-test-key")
    try check("draft.no-disk-write", try Data(contentsOf: manager.fileURL) == original)
    try check("draft.no-runtime-change", manager.config == seed && notifications == 0)
    try check("draft.save-enabled", try view("settings.save", as: NSButton.self).isEnabled)
    try press("settings.save")
    try check("save.atomic-commit", try persisted().providers["connection"]?.model == "changed-model" && notifications == 1)
    try check("config.owner-only", try FileManager.default.attributesOfItem(atPath: manager.fileURL.path)[.posixPermissions] as? Int == 0o600)
    try check("save.preserves-legacy", manager.config.providers["legacy"] == seed.providers["legacy"] && manager.config.commands[1] == seed.commands[1])
    try check("request.snapshot-is-immutable", frozenRequestConfig.config == seed)
    try commit("provider.base-url", "https://new.example/v1")
    allowConfirmation = false; let previousConfirmations = confirmations; try press("settings.save")
    try check("key.origin-change-requires-consent", confirmations == previousConfirmations + 1 && manager.config.providers["connection"]?.baseURL == seed.providers["connection"]?.baseURL)
    allowConfirmation = true
    try commit("provider.base-url", "https://api.example.com/v1")
    try commit("provider.api-key", "")
    try check("key.blank-stages-removal", controller.draftConfig.providers["connection"]?.apiKey == nil && manager.config.providers["connection"]?.apiKey == "replacement-test-key")
    try commit("provider.api-key", "replacement-test-key")
    try commit("provider.base-url", "not a URL"); try press("settings.save")
    try check("connection.invalid-not-saved", try persisted().providers["connection"]?.baseURL == seed.providers["connection"]?.baseURL)
    try check("connection.error-visible", try view("settings.status", as: NSTextField.self).stringValue.contains("URL"))
    try commit("provider.base-url", "https://api.example.com/v1")
    try commit("provider.model", ""); try press("settings.save")
    try check("connection.model-required", try view("settings.status", as: NSTextField.self).stringValue.contains("model"))
    try commit("provider.model", "changed-model")
    try page("Commands")
    try check("delete.visible", controller.control(accessibilityID: "commands.delete") != nil)
    try check("triggers.in-commands", controller.control(accessibilityID: "command.0.hotkey") != nil && controller.control(accessibilityID: "command.0.pointer") != nil && controller.control(accessibilityID: "superkey.popup") == nil)
    let editor = try view("command.0.prompt", as: NSTextView.self)
    try prompt("Selected {selection}; copied {copy}")
    try check("prompt.stable-editor", controller.control(accessibilityID: "command.0.prompt") === editor)
    editor.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
    controller.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
    try check("prompt.ime-composition-not-reformatted", editor.hasMarkedText() && controller.control(accessibilityID: "command.0.prompt.error") == nil)
    editor.unmarkText()
    controller.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
    try check("prompt.ime-validates-after-commit", controller.control(accessibilityID: "command.0.prompt.error") != nil)
    try prompt("Selected {selection}; copied {copy}")
    let token = promptPlaceholders(in: editor.string)[0]
    try check("prompt.highlighted", editor.textStorage?.attribute(.backgroundColor, at: token.range.location, effectiveRange: nil) != nil)
    try check("prompt.staged", manager.config.commands[0].prompt == seed.commands[0].prompt)
    editor.undoManager?.removeAllActions(); editor.breakUndoCoalescing(); editor.undoManager?.beginUndoGrouping()
    try prompt("Undo {input}"); editor.undoManager?.endUndoGrouping(); editor.undoManager?.undo()
    try check("prompt.undo", editor.string == "Selected {selection}; copied {copy}")
    editor.undoManager?.redo(); try check("prompt.redo", editor.string == "Undo {input}")
    try prompt("Typo {selecton}")
    try check("prompt.typo-feedback", try view("command.0.prompt.error", as: NSTextField.self).stringValue.contains("{selecton}"))
    try check("prompt.invalid-blocks-save", try !view("settings.save", as: NSButton.self).isEnabled)
    try page("Connection"); try page("Commands")
    try check("prompt.invalid-survives-navigation", try view("command.0.prompt", as: NSTextView.self).string == "Typo {selecton}")
    try prompt("Translate: ")
    let insertion = try view("command.0.prompt", as: NSTextView.self); insertion.setSelectedRange(NSRange(location: 11, length: 0))
    try press("command.0.insert-selection"); try press("command.0.insert-selection")
    try check("prompt.insert-selection-idempotent", insertion.string == "Translate: {selection}")
    insertion.setSelectedRange(NSRange(location: (insertion.string as NSString).length, length: 0)); try press("command.0.insert-clipboard")
    try check("prompt.insert-clipboard", insertion.string.hasSuffix("{clipboard}"))
    try press("settings.save")
    try check("prompt.saved-exactly", try persisted().commands[0].prompt == insertion.string)
    controller.commitRecordedHotkey(accessibilityID: "command.0.hotkey", value: "super+-")
    try check("hyper.note-when-off", try view("command.0.hotkey-note", as: NSTextField.self).stringValue.contains("off"))
    try press("settings.save")
    try check("hyper.off-blocks-save", try view("settings.status", as: NSTextField.self).stringValue.contains("Hyper"))
    try page("General"); try choose("superkey.popup", "External Hyper (⌃⌥⇧⌘)"); try press("settings.save"); try page("Commands")
    try check("hyper.recorded-inline", try view("command.0.hotkey", as: NSButton.self).title == "super+-")
    // A real key press with the Hyper Key held: Right Command carries the device-specific bit 0x10 alongside ⌘.
    try page("General"); try choose("superkey.popup", "Right Command"); try page("Commands")
    let hyperRecorder = try view("command.0.hotkey", as: NSButton.self); act(hyperRecorder)
    let rightCmdMinus = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(0x100010)), timestamp: 0, windowNumber: controller.window!.windowNumber, context: nil, characters: "-", charactersIgnoringModifiers: "-", isARepeat: false, keyCode: 27)!
    hyperRecorder.keyDown(with: rightCmdMinus)
    try check("hyper.right-command-records-super", controller.draftConfig.commands[0].hotkey == "super+-")
    act(hyperRecorder)
    let leftCmdMinus = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(0x100008)), timestamp: 0, windowNumber: controller.window!.windowNumber, context: nil, characters: "-", charactersIgnoringModifiers: "-", isARepeat: false, keyCode: 27)!
    hyperRecorder.keyDown(with: leftCmdMinus)
    try check("hyper.left-command-records-plain", controller.draftConfig.commands[0].hotkey == "cmd+-")
    try page("General"); try choose("superkey.popup", "External Hyper (⌃⌥⇧⌘)"); try page("Commands")
    controller.commitRecordedHotkey(accessibilityID: "command.0.hotkey", value: "super+-"); try press("settings.save")
    try check("hyper.external-saved", try persisted().superKey == .externalHyper && persisted().commands[0].hotkey == "super+-")
    controller.commitRecordedHotkey(accessibilityID: "command.0.hotkey", value: "cmd+3")
    let recorder = try view("command.0.hotkey", as: NSButton.self); act(recorder)
    let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: controller.window!.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)!
    recorder.keyDown(with: escape)
    try check("shortcut.escape", recorder.title == "cmd+3")
    controller.commitRecordedHotkey(accessibilityID: "command.0.hotkey", value: "cmd+2")
    try check("shortcut.duplicate-rejected", controller.control(accessibilityID: "command.0.hotkey.error") != nil)
    controller.commitRecordedHotkey(accessibilityID: "command.0.hotkey", value: "cmd+3")
    try press("settings.save")
    let savedCount = manager.config.commands.count
    try press("commands.add"); try press("commands.add")
    try check("command.add-staged", manager.config.commands.count == savedCount)
    try check("command.add-unique", try view("commands.selector", as: NSPopUpButton.self).itemTitles.suffix(2) == ["New command", "New command 2"])
    allowConfirmation = false; try press("commands.delete")
    try check("delete.cancel", try view("commands.selector", as: NSPopUpButton.self).numberOfItems == savedCount + 2)
    allowConfirmation = true; try press("commands.delete"); try press("commands.delete")
    try check("delete.confirmed-staged", try view("commands.selector", as: NSPopUpButton.self).numberOfItems == savedCount && manager.config.commands.count == savedCount)
    try choose("commands.selector", "Translate to Chinese"); try prompt("Unsaved {selection}")
    let beforeCancel = manager.config
    allowConfirmation = false
    var quitAllowed = true
    controller.confirmDiscardForTermination { quitAllowed = $0 }
    try check("quit.protects-draft", !quitAllowed)
    _ = controller.windowShouldClose(controller.window!)
    try check("cancel.keep-editing", try view("command.0.prompt", as: NSTextView.self).string == "Unsaved {selection}")
    allowConfirmation = true; _ = controller.windowShouldClose(controller.window!)
    controller.prepareOffscreen(appearance: light)
    try check("cancel.discards", try view("command.0.prompt", as: NSTextView.self).string == beforeCancel.commands[0].prompt && persisted() == beforeCancel)
    try prompt("Retry {selection}")
    let backup = manager.directory.appendingPathComponent("backup.json")
    let blocked = manager.directory.appendingPathComponent("blocked-directory")
    try FileManager.default.moveItem(at: manager.fileURL, to: backup)
    try FileManager.default.createDirectory(at: manager.fileURL, withIntermediateDirectories: false)
    try press("settings.save")
    try check("save.failure-preserves-runtime", manager.config == beforeCancel)
    try check("save.failure-retains-draft", try view("command.0.prompt", as: NSTextView.self).string == "Retry {selection}")
    try FileManager.default.moveItem(at: manager.fileURL, to: blocked); try FileManager.default.moveItem(at: backup, to: manager.fileURL)
    try press("settings.save"); try check("save.retry", try persisted().commands[0].prompt == "Retry {selection}")
    let beforeConflict = try Data(contentsOf: manager.fileURL)
    var external = manager.config; external.autoCopy.toggle()
    try JSONEncoder().encode(external).write(to: manager.fileURL)
    try prompt("Conflict {selection}"); try press("settings.save")
    try check("save.disk-conflict", try persisted() == external && view("settings.status", as: NSTextField.self).stringValue.contains("changed"))
    try beforeConflict.write(to: manager.fileURL); try press("settings.save")
    try choose("commands.selector", "Translate to English")
    let pointer = try view("command.1.pointer", as: NSButton.self); pointer.state = .on; act(pointer)
    try check("pointer.staged", !manager.config.pointerTrigger.enabled && controller.draftConfig.pointerTrigger == PointerTriggerConfig(enabled: true, commandIndex: 1))
    try press("settings.save")
    try check("pointer.persisted", try persisted().pointerTrigger == PointerTriggerConfig(enabled: true, commandIndex: 1))
    try choose("commands.selector", "Translate to Chinese")
    try check("pointer.other-command-shows-owner", try view("command.0.pointer", as: NSButton.self).state == .off)
    try press("commands.delete"); try press("settings.save")
    try check("pointer.target-follows-deletion", manager.config.pointerTrigger.commandIndex == 0 && manager.config.pointerTrigger.enabled)
    try press("commands.delete"); try press("settings.save")
    try check("pointer.target-deletion-disables", manager.config.commands.isEmpty && !manager.config.pointerTrigger.enabled)
    try check("command.empty-state", controller.control(accessibilityID: "command.0.prompt") == nil)
    try original.write(to: manager.fileURL); try reload()
    try check("config.restored", try persisted() == seed)
    for appearance in [light, dark] {
        controller.prepareOffscreen(appearance: appearance)
        for title in ["Commands", "Connection", "General"] {
            try page(title)
            if title == "General", let toggle = controller.control(accessibilityID: "system.advanced") as? NSButton, toggle.state == .on { act(toggle) }
            try snapshot("\(appearance == light ? "light" : "dark")-\(title.lowercased())")
        }
    }
    try check("confirmation.used", confirmations >= 5)
    let reading = ResultPanelController(closesOnResign: false)
    defer { reading.close() }
    let originalText = "Design is intelligence made visible.\nA quiet interface lets content lead."
    reading.showLoading(command: "Translate to Chinese", source: originalText)
    try check("result.loading-no-stale-copy", reading.control("result.copy")?.isHidden == true && reading.textForCopy(useSelection: false).isEmpty)
    let translated = "设计是可视化的智慧。\n\n安静的界面让内容成为主角。"
    reading.showResult(translated)
    try check("result.white-surface", reading.window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
    try check("result.sentence-case-title", (reading.control("result.command") as? NSTextField)?.stringValue == "Translate to Chinese")
    try check("result.compact", reading.window.frame.width == 440 && reading.window.frame.height < 250)
    try check("result.original-collapsed", reading.control("result.original")?.isHidden == true)
    try check("result.real-controls", reading.control("result.close") != nil && reading.control("result.copy")?.isHidden == false)
    try reading.renderPNG(to: outdir.appendingPathComponent("reading-result.png"))
    act(reading.control("result.show-original") as! NSButton)
    let originalEditor = reading.control("result.original") as! NSTextView
    try check("result.original-full-text", !originalEditor.isHidden && originalEditor.string == originalText)
    reading.window.makeFirstResponder(originalEditor); originalEditor.setSelectedRange(NSRange(location: 0, length: 6))
    try check("result.original-selection-copy", reading.textForCopy(useSelection: true) == "Design")
    act(reading.control("result.show-original") as! NSButton)
    reading.showResult("**Important**: keep `literal` text.\n\n你好。")
    let resultEditor = reading.control("result.text") as! NSTextView
    try check("result.inline-markdown", resultEditor.string == "Important: keep literal text.\n\n你好。")
    reading.window.makeFirstResponder(resultEditor); resultEditor.setSelectedRange(NSRange(location: 0, length: 9))
    try check("result.selected-copy", reading.textForCopy(useSelection: true) == "Important")
    try check("result.full-copy-preserves-format", reading.textForCopy(useSelection: false).hasPrefix("**Important**"))
    reading.showResult(String(repeating: "A long translation remains scrollable.\n", count: 120))
    try check("result.long-scrolls", reading.window.frame.height <= 528 && resultEditor.frame.height > 420)
    var confirmed = false
    reading.showNotice(command: "Accessibility", message: "Enable selection capture.", actionTitle: "Continue", confirm: { confirmed = true })
    act(reading.control("result.action") as! NSButton)
    try check("result.notice-action", confirmed && !reading.window.isVisible)
    reading.showError(message: "Could not connect", detail: "Diagnostic information")
    try check("result.error-clears-action", reading.control("result.action")?.isHidden == true && reading.control("result.copy")?.isHidden == true)
    try check("result.error-details-collapsed", reading.control("result.original")?.isHidden == true)
    act(reading.control("result.show-original") as! NSButton)
    try check("result.error-details-available", (reading.control("result.original") as? NSTextView)?.string == "Diagnostic information")
    try reading.renderPNG(to: outdir.appendingPathComponent("reading-error.png"))
    reading.close()
    let otherWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: .titled, backing: .buffered, defer: false)
    let otherCopy = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: otherWindow.windowNumber, context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!
    try check("result.never-steals-settings-copy", reading.handleKey(otherCopy) === otherCopy)
    print("PASS: \(checks.count) AppKit checks")
}

private func failure(_ text: String) -> NSError { NSError(domain: "UIJourney", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
private extension NSView { var descendants: [NSView] { subviews + subviews.flatMap(\.descendants) } }
