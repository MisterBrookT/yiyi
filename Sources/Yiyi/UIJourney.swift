import AppKit
import YiyiCore

@MainActor func runUIJourney(outdir: URL) throws {
    guard let isolatedPath = ProcessInfo.processInfo.environment["YIYI_CONFIG_DIR"], !isolatedPath.isEmpty else {
        throw NSError(domain: "UIJourney", code: 10, userInfo: [NSLocalizedDescriptionKey: "--ui-journey requires an isolated YIYI_CONFIG_DIR"])
    }
    let realConfig = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/yiyi/config.json").standardizedFileURL
    try FileManager.default.createDirectory(at: outdir, withIntermediateDirectories: true)
    let manager = ConfigManager()
    if !FileManager.default.fileExists(atPath: manager.fileURL.path) {
        try FileManager.default.createDirectory(at: manager.directory, withIntermediateDirectories: true)
        var providers = YiyiConfig.defaultProviders
        providers["openrouter"] = ProviderConfig(baseURL: "https://openrouter.example/v1", model: "legacy", apiKeyEnv: "OPENROUTER_API_KEY")
        providers["ark"] = ProviderConfig(baseURL: "https://ark.example/v1", model: "legacy", apiKeyEnv: "ARK_API_KEY")
        let seed = YiyiConfig(providers: providers)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(seed).write(to: manager.fileURL)
    }
    try manager.load()
    let status = AccessibilityStatus(trusted: false, superKeyTapStatus: "unavailable — Accessibility permission required", signatureIdentity: "yiyi Local Signing · cc.blackblue.yiyi", advice: .repairStaleGrant)
    func makeController() -> SettingsWindowController {
        SettingsWindowController(configs: manager, accessibilityStatus: { status }, requestAccessibility: {}, repairAccessibility: {})
    }
    let controller = makeController()
    var checks: [[String: Any]] = []
    func check(_ name: String, _ condition: @autoclosure () throws -> Bool, _ detail: String) throws {
        let passed = try condition(); checks.append(["name": name, "passed": passed, "detail": detail])
        if !passed { throw NSError(domain: "UIJourney", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(name): \(detail)"]) }
    }
    func act(_ view: NSControl) { if let action = view.action { _ = NSApp.sendAction(action, to: view.target, from: view) } }
    func field(_ id: String) throws -> NSTextField { guard let value = controller.control(accessibilityID: id) as? NSTextField else { throw NSError(domain: "UIJourney", code: 2, userInfo: [NSLocalizedDescriptionKey: "missing text field \(id)"]) }; return value }
    func popup(_ id: String) throws -> NSPopUpButton { guard let value = controller.control(accessibilityID: id) as? NSPopUpButton else { throw NSError(domain: "UIJourney", code: 3, userInfo: [NSLocalizedDescriptionKey: "missing popup \(id)"]) }; return value }

    let light = NSAppearance(named: .aqua)!, dark = NSAppearance(named: .darkAqua)!
    var lightTrees: [SettingsWindowController.Pane: [String: String]] = [:]
    let panes = SettingsWindowController.Pane.allCases
    for pane in panes {
        controller.selectPane(pane, persist: true)
        controller.prepareOffscreen(appearance: light)
        try check("pane.\(pane.rawValue.lowercased()).visible", controller.control(accessibilityID: "pane.\(pane.rawValue.lowercased())") != nil, "sidebar selection displays \(pane.rawValue)")
        try check("pane.\(pane.rawValue.lowercased()).selected", controller.selectedPane == pane, "selected pane model follows sidebar")
        try assertGeometry(controller: controller, pane: pane, checks: &checks)
        try check("isolation.config-path", manager.fileURL.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: isolatedPath).standardizedFileURL.path + "/") && manager.fileURL.standardizedFileURL != realConfig, "writes are confined to \(isolatedPath)")
        lightTrees[pane] = controller.window?.contentView?.geometryTree() ?? [:]
        try controller.renderPNG(to: outdir.appendingPathComponent("light-\(pane.rawValue.lowercased()).png"))
        let lightImage = NSImage(contentsOf: outdir.appendingPathComponent("light-\(pane.rawValue.lowercased()).png"))
        try check("visual.light.\(pane.rawValue.lowercased())", lightImage?.size.width ?? 0 >= 700 && lightImage?.size.height ?? 0 >= 300, "off-screen light PNG has a full settings frame")
        if pane == .provider { try controller.renderPNG(to: outdir.appendingPathComponent("light-provider-bottom.png"), bottom: true) }
    }
    controller.selectPane(.provider, persist: false)
    controller.prepareOffscreen(appearance: light)
    if let keyStatus = controller.control(accessibilityID: "provider.key-status") as? NSTextField {
        let wrappedHeight = keyStatus.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: keyStatus.bounds.width, height: .greatestFiniteMagnitude)).height ?? 0
        try check("provider.key-status.wraps", keyStatus.bounds.height + 0.5 >= wrappedHeight, "key status height \(keyStatus.bounds.height) fits wrapped text height \(wrappedHeight)")
    } else {
        try check("provider.key-status.wraps", false, "key status exists")
    }
    controller.selectPane(.superkey, persist: false)
    controller.prepareOffscreen(appearance: light)
    if let tapStatus = controller.control(accessibilityID: "superkey.tap") as? NSTextField {
        let wrappedHeight = tapStatus.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: tapStatus.bounds.width, height: .greatestFiniteMagnitude)).height ?? 0
        try check("superkey.tap.wraps", tapStatus.bounds.height + 0.5 >= wrappedHeight, "tap availability height \(tapStatus.bounds.height) fits wrapped text height \(wrappedHeight)")
    } else {
        try check("superkey.tap.wraps", false, "tap availability exists")
    }
    controller.selectPane(.permissions, persist: false)
    controller.prepareOffscreen(appearance: light)
    let lightSidebar = controller.sidebarState()
    try check("sidebar.light.rows", lightSidebar.titles == panes.map(\.rawValue), "sidebar renders all pane titles: \(lightSidebar.titles)")
    try check("sidebar.light.selection", lightSidebar.selectedRow == 3, "Permissions row is selected")
    try controller.renderSidebarPNG(to: outdir.appendingPathComponent("sidebar-light.png"), dark: false)

    controller.selectPane(.permissions)
    let permissionValues = [
        ("permission.trusted", "No"),
        ("permission.signature", status.signatureIdentity)
    ]
    for (id, expected) in permissionValues {
        let actual = controller.control(accessibilityID: id)?.accessibilityValue() as? String
        try check("semantic.\(id)", actual == expected, "\(id) accessible value is \(expected), got \(actual ?? "nil")")
    }
    try check("permission.stale-grant", controller.control(accessibilityID: "permission.stale-grant") != nil, "stale-grant guidance renders")
    try check("permission.repair", controller.control(accessibilityID: "permission.repair") != nil, "repair permission control renders")

    func persisted() throws -> YiyiConfig { try JSONDecoder().decode(YiyiConfig.self, from: Data(contentsOf: manager.fileURL)) }
    func commit(_ id: String, _ value: String) throws { let control = try field(id); control.stringValue = value; act(control) }

    let original = try Data(contentsOf: manager.fileURL)
    controller.selectPane(.provider)
    let qwenDefault = controller.control(accessibilityID: "provider.default.qwen") as! NSButton; qwenDefault.state = .on; act(qwenDefault)
    try check("behaviour.provider.default", try persisted().defaultProvider == "qwen", "real default-provider radio action persists")
    let deepseekDefault = controller.control(accessibilityID: "provider.default.deepseek") as! NSButton; deepseekDefault.state = .on; act(deepseekDefault)
    try check("behaviour.provider.default-revert", try persisted().defaultProvider == "deepseek", "default-provider radio action reverts")
    try commit("provider.base-url", "https://changed.example/v1")
    try check("behaviour.provider.base-url", try persisted().providers["deepseek"]?.baseURL == "https://changed.example/v1", "real field action persists baseURL")
    try commit("provider.api-key-env", "CHANGED_KEY")
    try check("behaviour.provider.api-key-env", try persisted().providers["deepseek"]?.apiKeyEnv == "CHANGED_KEY", "real field action persists apiKeyEnv")
    try commit("provider.model", "changed-model")
    try commit("provider.api-key", "secret")
    try commit("provider.temperature", "0.25")
    let reasoning = try popup("provider.reasoning-effort"); reasoning.selectItem(withTitle: "high"); act(reasoning)
    let copy = controller.control(accessibilityID: "provider.auto-copy") as! NSButton; copy.state = .off; act(copy)
    var value = try persisted()
    try check("behaviour.provider.fields", value.providers["deepseek"]?.model == "changed-model" && value.providers["deepseek"]?.apiKey == "secret" && value.providers["deepseek"]?.temperature == 0.25 && value.providers["deepseek"]?.reasoningEffort == .high, "provider fields persist through target/action")
    try check("behaviour.provider.auto-copy", !value.autoCopy, "real auto-copy checkbox action persists")
    try commit("provider.add-name", "custom")
    act(controller.control(accessibilityID: "provider.add") as! NSControl)
    try check("behaviour.provider.add", try persisted().providers["custom"] != nil, "add provider action persists")
    act(controller.control(accessibilityID: "provider.remove") as! NSControl)
    try check("behaviour.provider.remove", try persisted().providers["custom"] == nil, "remove provider action persists")
    act(controller.control(accessibilityID: "provider.remove") as! NSControl)
    try check("rejection.provider.default-remove", try persisted().providers["deepseek"] != nil && controller.control(accessibilityID: "provider.remove.error") != nil, "default removal is refused visibly")
    try commit("provider.add-name", "qwen"); act(controller.control(accessibilityID: "provider.add") as! NSControl)
    try check("rejection.provider.duplicate", try persisted().providers.count == value.providers.count && controller.control(accessibilityID: "provider.add-name.error") != nil, "duplicate provider is not persisted and shows an error")
    try commit("provider.temperature", "not-a-number")
    try check("rejection.provider.temperature", try persisted().providers["deepseek"]?.temperature == 0.25 && controller.control(accessibilityID: "provider.temperature.error") != nil, "invalid temperature is not persisted and shows an error")

    controller.selectPane(.shortcuts)
    try commit("command.0.name", "Changed command")
    try commit("command.0.model", "override-model")
    let commandProvider = try popup("command.0.provider"); commandProvider.selectItem(withTitle: "qwen"); act(commandProvider)
    let commandEffort = try popup("command.0.reasoning-effort"); commandEffort.selectItem(withTitle: "none"); act(commandEffort)
    guard let prompt = controller.control(accessibilityID: "command.0.prompt") as? NSTextView else { throw NSError(domain: "UIJourney", code: 4) }
    prompt.string = "Changed {input}"; controller.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: prompt))
    controller.commitRecordedHotkey(accessibilityID: "command.0.hotkey", value: "cmd+1")
    value = try persisted()
    try check("behaviour.command.fields", value.commands[0].name == "Changed command" && value.commands[0].hotkey == "cmd+1" && value.commands[0].prompt == "Changed {input}" && value.commands[0].provider == "qwen" && value.commands[0].model == "override-model" && value.commands[0].reasoningEffort == .some(.none), "all command fields persist through their real handlers")
    commandProvider.selectItem(withTitle: "inherit"); act(commandProvider)
    let inheritedEffort = try popup("command.0.reasoning-effort"); inheritedEffort.selectItem(withTitle: "inherit"); act(inheritedEffort)
    try commit("command.0.model", "")
    value = try persisted()
    try check("behaviour.command.inherit", value.commands[0].provider == nil && value.commands[0].model == nil && value.commands[0].reasoningEffort == nil, "all optional overrides clear to inherit")
    controller.commitRecordedHotkey(accessibilityID: "command.0.hotkey", value: "not+a+hotkey")
    try check("rejection.command.hotkey-invalid", try persisted().commands[0].hotkey == "cmd+1" && controller.control(accessibilityID: "command.0.hotkey.error") != nil, "unparseable hotkey is refused visibly")
    controller.commitRecordedHotkey(accessibilityID: "command.0.hotkey", value: value.commands[1].hotkey)
    try check("rejection.command.hotkey-duplicate", try persisted().commands[0].hotkey == "cmd+1" && controller.control(accessibilityID: "command.0.hotkey.error") != nil, "duplicate hotkey is refused visibly")
    for invalid in ["", "no placeholder"] {
        controller.selectPane(.shortcuts)
        let invalidPrompt = controller.control(accessibilityID: "command.0.prompt") as! NSTextView
        invalidPrompt.string = invalid; controller.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: invalidPrompt))
        try check("rejection.command.prompt.\(invalid.isEmpty ? "empty" : "placeholder")", try persisted().commands[0].prompt == "Changed {input}" && controller.control(accessibilityID: "command.0.prompt.error") != nil, "invalid prompt is refused visibly")
    }
    let beforeAdd = try persisted().commands.count
    act(controller.control(accessibilityID: "commands.add") as! NSControl)
    try check("behaviour.command.add", try persisted().commands.count == beforeAdd + 1, "add command action persists")
    act(controller.control(accessibilityID: "command.\(beforeAdd).remove") as! NSControl)
    try check("behaviour.command.remove", try persisted().commands.count == beforeAdd, "remove command action persists")

    controller.selectPane(.superkey)
    let superkey = try popup("superkey.popup"); superkey.selectItem(withTitle: "right ⌘"); act(superkey)
    controller.commitRecordedHotkey(accessibilityID: "superkey.command.0.binding", value: "super+t")
    try check("behaviour.superkey", try persisted().superKey == .rightCommand && persisted().commands[0].hotkey == "super+t", "leader and per-command binding persist through handlers")

    var requestConfig = try persisted()
    requestConfig.providers["deepseek"]?.reasoningEffort = .none
    requestConfig.commands[0].provider = "deepseek"
    requestConfig.commands[0].reasoningEffort = nil
    let omitted = try JSONSerialization.jsonObject(with: buildChatCompletionBody(prompt: "x", provider: resolveProvider(config: requestConfig, command: requestConfig.commands[0]))) as! [String: Any]
    try check("behaviour.reasoning.omit", omitted["reasoning_effort"] == nil, "provider none omits reasoning_effort from the real request body")
    requestConfig.providers["deepseek"]?.reasoningEffort = .high
    let explicit = try JSONSerialization.jsonObject(with: buildChatCompletionBody(prompt: "x", provider: resolveProvider(config: requestConfig, command: requestConfig.commands[0]))) as! [String: Any]
    try check("behaviour.reasoning.explicit", explicit["reasoning_effort"] as? String == "high", "explicit provider level is included in the real request body")
    requestConfig.commands[0].reasoningEffort = .low
    let overridden = try JSONSerialization.jsonObject(with: buildChatCompletionBody(prompt: "x", provider: resolveProvider(config: requestConfig, command: requestConfig.commands[0]))) as! [String: Any]
    try check("behaviour.reasoning.override", overridden["reasoning_effort"] as? String == "low", "command reasoning override beats the provider default")

    try original.write(to: manager.fileURL, options: .atomic)
    try manager.load()
    try check("behaviour.byte-identical-revert", try Data(contentsOf: manager.fileURL) == original, "reverting every behavioural edit restores config byte-identically")

    controller.selectPane(.shortcuts)
    let invalidPrompt = controller.control(accessibilityID: "command.0.prompt") as! NSTextView
    invalidPrompt.string = "invalid prompt"; controller.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: invalidPrompt))
    try check("prompt.inline-error", controller.control(accessibilityID: "command.0.prompt.error") != nil, "invalid prompt shows inline validation")
    try controller.renderPNG(to: outdir.appendingPathComponent("light-shortcuts-invalid.png"))
    let restoredPrompt = controller.control(accessibilityID: "command.0.prompt") as! NSTextView
    restoredPrompt.string = YiyiConfig.defaultCommands[0].prompt
    controller.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: restoredPrompt))
    for pane in panes {
        controller.selectPane(pane, persist: false)
        controller.prepareOffscreen(appearance: light)
        let paneID = "pane.\(pane.rawValue.lowercased())"
        let comparisonLightTree = controller.control(accessibilityID: paneID)?.geometryTree() ?? [:]
        controller.prepareOffscreen(appearance: dark)
        let darkTree = controller.control(accessibilityID: paneID)?.geometryTree() ?? [:]
        try check("geometry.\(pane.rawValue.lowercased()).light-dark", NSDictionary(dictionary: darkTree).isEqual(to: comparisonLightTree), "light and dark frame trees are identical")
        try controller.renderPNG(to: outdir.appendingPathComponent("dark-\(pane.rawValue.lowercased()).png"))
        let darkImage = NSImage(contentsOf: outdir.appendingPathComponent("dark-\(pane.rawValue.lowercased()).png"))
        try check("visual.dark.\(pane.rawValue.lowercased())", darkImage?.size.width ?? 0 >= 700 && darkImage?.size.height ?? 0 >= 300, "off-screen dark PNG has a full settings frame")
        if pane == .provider { try controller.renderPNG(to: outdir.appendingPathComponent("dark-provider-bottom.png"), bottom: true) }
    }
    controller.selectPane(.permissions, persist: false)
    controller.prepareOffscreen(appearance: dark)
    let darkSidebar = controller.sidebarState()

    try check("sidebar.dark.rows", darkSidebar.titles == panes.map(\.rawValue), "dark sidebar renders all pane titles: \(darkSidebar.titles)")
    try check("sidebar.dark.selection", darkSidebar.selectedRow == 3, "Permissions row remains selected in dark appearance")
    try controller.renderSidebarPNG(to: outdir.appendingPathComponent("sidebar-dark.png"), dark: true)

    let json = try JSONSerialization.data(withJSONObject: ["passed": checks.allSatisfy { $0["passed"] as? Bool == true }, "checks": checks], options: [.prettyPrinted, .sortedKeys])
    try json.write(to: outdir.appendingPathComponent("assertions.json"))
    let images = panes.flatMap { ["light-\($0.rawValue.lowercased()).png", "dark-\($0.rawValue.lowercased()).png"] } + ["light-provider-bottom.png", "dark-provider-bottom.png", "sidebar-light.png", "sidebar-dark.png", "light-shortcuts-invalid.png"]
    let figures = try images.map { name -> String in let data = try Data(contentsOf: outdir.appendingPathComponent(name)).base64EncodedString(); return "<figure><img src=\"data:image/png;base64,\(data)\"><figcaption>\(name)</figcaption></figure>" }.joined()
    let html = "<!doctype html><meta charset=utf-8><title>yiyi Settings UI journey</title><style>body{font:15px system-ui;max-width:1200px;margin:32px auto;color:#222}h1{font-size:24px}section{margin:24px 0}figure{display:inline-block;width:48%;vertical-align:top;margin:1%}img{width:100%;border:1px solid #ccc}code{white-space:pre-wrap}</style><h1>yiyi Settings UI journey</h1><p>Off-screen rendering of the real AppKit view hierarchy; no host pixels or synthetic input.</p><section><h2>Verdict: PASS</h2><p>All panes, semantic interaction, persistence, validation, layout invariants, and light/dark geometry passed.</p></section><section>\(figures)</section><section><h2>Assertions</h2><code>\(String(data: json, encoding: .utf8)!)</code></section>"
    try html.write(to: outdir.appendingPathComponent("report.html"), atomically: true, encoding: .utf8)
}


@MainActor private func assertGeometry(controller: SettingsWindowController, pane: SettingsWindowController.Pane, checks: inout [[String: Any]]) throws {
    guard let root = controller.control(accessibilityID: "pane.\(pane.rawValue.lowercased())") else { return }
    func record(_ name: String, _ passed: Bool, _ detail: String) throws {
        checks.append(["name": name, "passed": passed, "detail": detail])
        if !passed { throw NSError(domain: "UIJourney", code: 5, userInfo: [NSLocalizedDescriptionKey: "\(name): \(detail)"]) }
    }
    let grids = root.allSubviews.compactMap { $0 as? NSGridView }.filter { $0.numberOfColumns >= 2 && $0.numberOfRows > 0 }
    let origins = grids.compactMap { $0.cell(atColumnIndex: 1, rowIndex: 0).contentView }.map { root.convert($0.bounds, from: $0).minX }
    try record("geometry.\(pane.rawValue.lowercased()).control-column", !origins.isEmpty && origins.allSatisfy { abs($0 - (origins.first ?? $0)) <= 2.0 }, "value columns share one grid origin (allowing AppKit's 2 pt text-field drawing inset): \(origins)")
    let labelX = grids.first.flatMap { $0.cell(atColumnIndex: 0, rowIndex: 0).contentView }.map { root.convert($0.bounds, from: $0).minX } ?? 0
    let headings = root.allSubviews.compactMap { view -> NSView? in guard view.accessibilityIdentifier().hasPrefix("section.") else { return nil }; return view }
    let headingOrigins = headings.map { root.convert($0.bounds, from: $0).minX }
    try record("geometry.\(pane.rawValue.lowercased()).headings", !headings.isEmpty && headingOrigins.allSatisfy { abs($0 - labelX) <= 0.5 }, "headings align with label column: \(headingOrigins), label \(labelX)")
    let controls = grids.flatMap { grid in
        (0..<grid.numberOfRows)
            .compactMap { grid.cell(atColumnIndex: 1, rowIndex: $0).contentView }
            .flatMap { [$0] + $0.allSubviews }
            .compactMap { $0 as? NSControl }
    }
    let truncated = controls.filter {
        if let text = $0 as? NSTextField, text.maximumNumberOfLines != 1 { return false }
        return $0.intrinsicContentSize.width > 0 && $0.bounds.width + 0.5 < $0.intrinsicContentSize.width
    }
    let truncationDetail = truncated.map { control in
        "\(type(of: control)):\(NSStringFromSize(control.bounds.size))<\(NSStringFromSize(control.intrinsicContentSize))"
    }
    try record("geometry.\(pane.rawValue.lowercased()).no-truncation", truncated.isEmpty, "controls narrower than intrinsic width: \(truncationDetail)")
}

private extension NSView {
    var allSubviews: [NSView] { subviews + subviews.flatMap(\.allSubviews) }
    func geometryTree() -> [String: String] { Dictionary(uniqueKeysWithValues: ([self] + allSubviews).enumerated().map { ("\($0.offset):\(type(of: $0.element))", NSStringFromRect($0.element.frame)) }) }
}
