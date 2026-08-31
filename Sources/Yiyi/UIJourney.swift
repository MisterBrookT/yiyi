import AppKit
import YiyiCore

@MainActor func runUIJourney(outdir: URL) throws {
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
    func check(_ name: String, _ condition: @autoclosure () -> Bool, _ detail: String) throws {
        let passed = condition(); checks.append(["name": name, "passed": passed, "detail": detail])
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
        try assertInteractivity(controller: controller, pane: pane, checks: &checks)
        lightTrees[pane] = controller.window?.contentView?.geometryTree() ?? [:]
        try controller.renderPNG(to: outdir.appendingPathComponent("light-\(pane.rawValue.lowercased()).png"))
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

    controller.selectPane(.provider)
    let model = try field("provider.model"); model.stringValue = "deepseek-v4-flash-test"; act(model)
    let reasoning = try popup("provider.reasoning"); reasoning.selectItem(withTitle: "high"); act(reasoning)
    controller.selectPane(.superkey)
    let superkey = try popup("superkey.popup"); superkey.selectItem(withTitle: "right ⌘"); act(superkey)
    try controller.setRecordedHotkey("super+t", index: 0)
    let persisted = try JSONDecoder().decode(YiyiConfig.self, from: Data(contentsOf: manager.fileURL))
    try check("persistence.model", persisted.providers["deepseek"]?.model == "deepseek-v4-flash-test", "model round-trips through config.json")
    try check("persistence.reasoning", persisted.providers["deepseek"]?.reasoningEffort == .high, "reasoning persists")
    try check("persistence.superkey", persisted.superKey == .rightCommand, "superkey persists")
    try check("persistence.hotkey", persisted.commands.first?.hotkey == "super+t", "super hotkey persists")
    try check("legacy.providers", persisted.providers["openrouter"] != nil && persisted.providers["ark"] != nil, "unknown and legacy providers survive a UI edit")

    controller.selectPane(.shortcuts)
    guard let prompt = controller.control(accessibilityID: "command.0.prompt") as? NSTextView else { throw NSError(domain: "UIJourney", code: 4) }
    prompt.string = "invalid prompt"; controller.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: prompt))
    try check("prompt.inline-error", controller.control(accessibilityID: "command.0.prompt-error") != nil, "invalid prompt shows inline validation")
    try controller.renderPNG(to: outdir.appendingPathComponent("light-shortcuts-invalid.png"))

    controller.selectPane(.permissions, persist: true)
    let restored = makeController()
    try check("pane.persistence-roundtrip", restored.selectedPane == .permissions, "last selected pane restores in a new window controller")
    restored.selectPane(.provider, persist: true)

    try manager.setProvider("deepseek", model: "deepseek-v4-flash", reasoningEffort: ReasoningEffort.none)
    try manager.setSuperKey(.none); try manager.setCommand(0, prompt: YiyiConfig.defaultCommands[0].prompt, hotkey: "cmd+-")
    for pane in panes {
        controller.selectPane(pane, persist: false)
        controller.prepareOffscreen(appearance: light)
        let paneID = "pane.\(pane.rawValue.lowercased())"
        let comparisonLightTree = controller.control(accessibilityID: paneID)?.geometryTree() ?? [:]
        controller.prepareOffscreen(appearance: dark)
        let darkTree = controller.control(accessibilityID: paneID)?.geometryTree() ?? [:]
        try check("geometry.\(pane.rawValue.lowercased()).light-dark", NSDictionary(dictionary: darkTree).isEqual(to: comparisonLightTree), "light and dark frame trees are identical")
        try controller.renderPNG(to: outdir.appendingPathComponent("dark-\(pane.rawValue.lowercased()).png"))
    }
    controller.selectPane(.permissions, persist: false)
    controller.prepareOffscreen(appearance: dark)
    let darkSidebar = controller.sidebarState()
    try check("sidebar.dark.rows", darkSidebar.titles == panes.map(\.rawValue), "dark sidebar renders all pane titles: \(darkSidebar.titles)")
    try check("sidebar.dark.selection", darkSidebar.selectedRow == 3, "Permissions row remains selected in dark appearance")
    try controller.renderSidebarPNG(to: outdir.appendingPathComponent("sidebar-dark.png"), dark: true)

    let json = try JSONSerialization.data(withJSONObject: ["passed": checks.allSatisfy { $0["passed"] as? Bool == true }, "checks": checks], options: [.prettyPrinted, .sortedKeys])
    try json.write(to: outdir.appendingPathComponent("assertions.json"))
    let images = panes.flatMap { ["light-\($0.rawValue.lowercased()).png", "dark-\($0.rawValue.lowercased()).png"] } + ["sidebar-light.png", "sidebar-dark.png", "light-shortcuts-invalid.png"]
    let figures = try images.map { name -> String in let data = try Data(contentsOf: outdir.appendingPathComponent(name)).base64EncodedString(); return "<figure><img src=\"data:image/png;base64,\(data)\"><figcaption>\(name)</figcaption></figure>" }.joined()
    let html = "<!doctype html><meta charset=utf-8><title>yiyi Settings UI journey</title><style>body{font:15px system-ui;max-width:1200px;margin:32px auto;color:#222}h1{font-size:24px}section{margin:24px 0}figure{display:inline-block;width:48%;vertical-align:top;margin:1%}img{width:100%;border:1px solid #ccc}code{white-space:pre-wrap}</style><h1>yiyi Settings UI journey</h1><p>Off-screen rendering of the real AppKit view hierarchy; no host pixels or synthetic input.</p><section><h2>Verdict: PASS</h2><p>All panes, semantic interaction, persistence, validation, layout invariants, and light/dark geometry passed.</p></section><section>\(figures)</section><section><h2>Assertions</h2><code>\(String(data: json, encoding: .utf8)!)</code></section>"
    try html.write(to: outdir.appendingPathComponent("report.html"), atomically: true, encoding: .utf8)
}

@MainActor private func assertInteractivity(controller: SettingsWindowController, pane: SettingsWindowController.Pane, checks: inout [[String: Any]]) throws {
    func record(_ name: String, _ passed: Bool, _ detail: String) throws {
        checks.append(["name": name, "passed": passed, "detail": detail])
        if !passed { throw NSError(domain: "UIJourney", code: 6, userInfo: [NSLocalizedDescriptionKey: "\(name): \(detail)"]) }
    }
    guard let window = controller.window,
          let windowRoot = window.contentView,
          let paneRoot = controller.control(accessibilityID: "pane.\(pane.rawValue.lowercased())") else { return }
    try record("interaction.window.can-become-key", window.canBecomeKey, "settings window accepts key status")
    try record("interaction.\(pane.rawValue.lowercased()).single-content", controller.installedPaneCount == 1, "detail contains exactly one pane view")
    let controls = paneRoot.allSubviews.filter { view in
        guard !view.isHidden else { return false }
        if let text = view as? NSTextField { return text.isEditable }
        if let text = view as? NSTextView { return text.isEditable }
        return view is NSButton || view is NSPopUpButton
    }
    for control in controls {
        let frame = windowRoot.convert(control.bounds, from: control)
        let centre = NSPoint(x: frame.midX, y: frame.midY)
        guard windowRoot.bounds.contains(centre), frame.width > 0, frame.height > 0 else { continue }
        let hit = windowRoot.hitTest(centre)
        let hitBelongsToControl = hit.map { candidate in
            candidate === control || candidate.isDescendant(of: control) || control.isDescendant(of: candidate)
        } ?? false
        let wired: Bool
        if let text = control as? NSTextField {
            wired = text.isEditable || (text.target != nil && text.action != nil) || !text.isEnabled
        } else if let text = control as? NSTextView {
            wired = text.isEditable
        } else if let value = control as? NSControl {
            wired = value.target != nil && value.action != nil
        } else {
            wired = false
        }
        let id = control.accessibilityIdentifier().isEmpty ? String(describing: type(of: control)) : control.accessibilityIdentifier()
        try record("interaction.\(pane.rawValue.lowercased()).\(id).hit-test", hitBelongsToControl, "\(id) is hit-testable at its centre")
        try record("interaction.\(pane.rawValue.lowercased()).\(id).wired", wired, "\(id) is editable or has target/action")
    }
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
