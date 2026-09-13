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
    try check("native.toolbar", controller.window?.toolbar?.items.map(\.label) == ["Translation", "Commands", "General"])
    try check("connection.generic", controller.control(accessibilityID: "provider.base-url") != nil && controller.control(accessibilityID: "provider.selector") == nil)
    try check("connection.key-masked", try view("provider.api-key", as: NSSecureTextField.self).stringValue.isEmpty)
    try check("save.initially-disabled", try !view("settings.save", as: NSButton.self).isEnabled)
    try snapshot("light-translation")
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
    try check("key.blank-keeps-existing", manager.config.providers["connection"]?.apiKey == "replacement-test-key")
    try commit("provider.base-url", "not a URL"); try press("settings.save")
    try check("connection.invalid-not-saved", try persisted().providers["connection"]?.baseURL == seed.providers["connection"]?.baseURL)
    try check("connection.error-visible", try view("settings.status", as: NSTextField.self).stringValue.contains("URL"))
    try commit("provider.base-url", "https://api.example.com/v1")
    try commit("provider.model", ""); try press("settings.save")
    try check("connection.model-required", try view("settings.status", as: NSTextField.self).stringValue.contains("model"))
    try commit("provider.model", "changed-model")
    try page("Commands")
    try check("delete.visible", controller.control(accessibilityID: "commands.delete") != nil)
    try check("hyper.with-shortcuts", controller.control(accessibilityID: "superkey.popup") != nil)
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
    try page("Translation"); try page("Commands")
    try check("prompt.invalid-survives-navigation", try view("command.0.prompt", as: NSTextView.self).string == "Typo {selecton}")
    try prompt("Translate: ")
    let insertion = try view("command.0.prompt", as: NSTextView.self); insertion.setSelectedRange(NSRange(location: 11, length: 0))
    try press("command.0.insert-selection"); try press("command.0.insert-selection")
    try check("prompt.insert-selection-idempotent", insertion.string == "Translate: {selection}")
    insertion.setSelectedRange(NSRange(location: (insertion.string as NSString).length, length: 0)); try press("command.0.insert-clipboard")
    try check("prompt.insert-clipboard", insertion.string.hasSuffix("{clipboard}"))
    try press("settings.save")
    try check("prompt.saved-exactly", try persisted().commands[0].prompt == insertion.string)
    try choose("command.0.hotkey-mode", "Hyper Key")
    controller.commitRecordedHotkey(accessibilityID: "command.0.hotkey", value: "super+-")
    try press("settings.save")
    try check("hyper.off-blocks-save", try view("settings.status", as: NSTextField.self).stringValue.contains("Hyper"))
    try choose("superkey.popup", "External Hyper (⌃⌥⇧⌘)"); try press("settings.save")
    try check("hyper.external-saved", try persisted().superKey == .externalHyper && persisted().commands[0].hotkey == "super+-")
    try choose("command.0.hotkey-mode", "Keyboard")
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
    try page("General")
    let pointer = try view("pointer.enabled", as: NSButton.self); pointer.state = .on; act(pointer)
    try choose("pointer.command", "Translate to English")
    try check("pointer.staged", !manager.config.pointerTrigger.enabled)
    try press("settings.save")
    try check("pointer.persisted", try persisted().pointerTrigger == PointerTriggerConfig(enabled: true, commandIndex: 1))
    try page("Commands"); try choose("commands.selector", "Translate to Chinese"); try press("commands.delete"); try press("settings.save")
    try check("pointer.target-follows-deletion", manager.config.pointerTrigger.commandIndex == 0 && manager.config.pointerTrigger.enabled)
    try press("commands.delete"); try press("settings.save")
    try check("pointer.target-deletion-disables", manager.config.commands.isEmpty && !manager.config.pointerTrigger.enabled)
    try check("command.empty-state", controller.control(accessibilityID: "command.0.prompt") == nil)
    try original.write(to: manager.fileURL); try reload()
    try check("config.restored", try persisted() == seed)
    for appearance in [light, dark] {
        controller.prepareOffscreen(appearance: appearance)
        for title in ["Translation", "Commands", "General"] {
            try page(title)
            let id = title == "General" ? "system.advanced" : title == "Translation" ? "provider.advanced" : "command.0.advanced"
            if let toggle = controller.control(accessibilityID: id) as? NSButton, toggle.state == .on { act(toggle) }
            try snapshot("\(appearance == light ? "light" : "dark")-\(title.lowercased())")
        }
    }
    try check("confirmation.used", confirmations >= 5)
    print("PASS: \(checks.count) AppKit checks")
}

private func failure(_ text: String) -> NSError { NSError(domain: "UIJourney", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
private extension NSView { var descendants: [NSView] { subviews + subviews.flatMap(\.descendants) } }
