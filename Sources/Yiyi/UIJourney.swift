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
    let controller = SettingsWindowController(configs: manager) { "unavailable: Accessibility not granted" }
    var checks: [[String: Any]] = []
    func check(_ name: String, _ condition: @autoclosure () -> Bool, _ detail: String) throws {
        let passed = condition(); checks.append(["name": name, "passed": passed, "detail": detail]); if !passed { throw NSError(domain: "UIJourney", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(name): \(detail)"]) }
    }
    func act(_ view: NSControl) { if let action = view.action { _ = NSApp.sendAction(action, to: view.target, from: view) } }
    func field(_ id: String) throws -> NSTextField { guard let value = controller.control(accessibilityID: id) as? NSTextField else { throw NSError(domain: "UIJourney", code: 2, userInfo: [NSLocalizedDescriptionKey: "missing text field \(id)"]) }; return value }
    func popup(_ id: String) throws -> NSPopUpButton { guard let value = controller.control(accessibilityID: id) as? NSPopUpButton else { throw NSError(domain: "UIJourney", code: 3, userInfo: [NSLocalizedDescriptionKey: "missing popup \(id)"]) }; return value }

    let light = NSAppearance(named: .aqua)!, dark = NSAppearance(named: .darkAqua)!
    controller.prepareOffscreen(appearance: light)
    for section in ["provider", "shortcuts", "superkey"] { try check("section.\(section)", controller.control(accessibilityID: "section.\(section)") != nil, "section must exist in scroll content") }
    try controller.renderPNG(to: outdir.appendingPathComponent("light-top.png"))
    try controller.renderPNG(to: outdir.appendingPathComponent("light-bottom.png"), bottom: true)

    let model = try field("provider.model"); model.stringValue = "deepseek-v4-flash-test"; act(model)
    let reasoning = try popup("provider.reasoning"); reasoning.selectItem(withTitle: "high"); act(reasoning)
    let superkey = try popup("superkey.popup"); superkey.selectItem(withTitle: "right ⌘"); act(superkey)
    try controller.setRecordedHotkey("super+t", index: 0)
    let persisted = try JSONDecoder().decode(YiyiConfig.self, from: Data(contentsOf: manager.fileURL))
    try check("persistence.model", persisted.providers["deepseek"]?.model == "deepseek-v4-flash-test", "model persists")
    try check("persistence.reasoning", persisted.providers["deepseek"]?.reasoningEffort == .high, "reasoning persists")
    try check("persistence.superkey", persisted.superKey == .rightCommand, "superkey persists")
    try check("persistence.hotkey", persisted.commands.first?.hotkey == "super+t", "super hotkey persists")
    try check("legacy.providers", persisted.providers["openrouter"] != nil && persisted.providers["ark"] != nil, "unknown loaded providers survive")

    guard let prompt = controller.control(accessibilityID: "command.0.prompt") as? NSTextView else { throw NSError(domain: "UIJourney", code: 4) }
    prompt.string = "invalid prompt"; controller.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: prompt))
    try check("prompt.inline-error", controller.control(accessibilityID: "command.0.prompt-error") != nil, "invalid prompt shows inline danger text")
    try controller.renderPNG(to: outdir.appendingPathComponent("light-invalid-prompt.png"))

    try manager.setProvider("deepseek", model: "deepseek-v4-flash", reasoningEffort: ReasoningEffort.none)
    try manager.setSuperKey(.none); try manager.setCommand(0, prompt: YiyiConfig.defaultCommands[0].prompt, hotkey: "cmd+-")
    controller.prepareOffscreen(appearance: dark)
    try controller.renderPNG(to: outdir.appendingPathComponent("dark-top.png"))
    try controller.renderPNG(to: outdir.appendingPathComponent("dark-bottom.png"), bottom: true)

    let geometry = controller.window?.contentView?.geometryTree() ?? [:]
    controller.prepareOffscreen(appearance: light)
    let lightGeometry = controller.window?.contentView?.geometryTree() ?? [:]
    try check("geometry.light-dark", NSDictionary(dictionary: geometry).isEqual(to: lightGeometry), "frame trees are identical")
    if let root = controller.window?.contentView {
        let grids = root.allSubviews.compactMap { $0 as? NSGridView }
        let origins = grids.compactMap { grid -> CGFloat? in guard grid.numberOfRows > 0 else { return nil }; return grid.cell(atColumnIndex: 1, rowIndex: 0).contentView.map { root.convert($0.bounds, from: $0).minX } }
        try check("geometry.control-column", origins.allSatisfy { abs($0 - (origins.first ?? $0)) <= 0.5 }, "all value columns share one x origin: \(origins)")
        let headingX = ["provider", "shortcuts", "superkey"].compactMap { controller.control(accessibilityID: "section.\($0)").map { root.convert($0.bounds, from: $0).minX } }
        let labelX = grids.first.flatMap { $0.cell(atColumnIndex: 0, rowIndex: 0).contentView }.map { root.convert($0.bounds, from: $0).minX } ?? 0
        try check("geometry.headings", headingX.allSatisfy { abs($0 - labelX) <= 0.5 }, "section headings align with label column")
        let controls = grids.compactMap { $0.cell(atColumnIndex: 1, rowIndex: 0).contentView?.allSubviews.compactMap { $0 as? NSControl }.first }
        try check("geometry.no-truncation", controls.allSatisfy { $0.bounds.width + 0.5 >= min(260, max(0, $0.intrinsicContentSize.width)) }, "controls fit intrinsic content")
    }

    let json = try JSONSerialization.data(withJSONObject: ["passed": checks.allSatisfy { $0["passed"] as? Bool == true }, "checks": checks], options: [.prettyPrinted, .sortedKeys]); try json.write(to: outdir.appendingPathComponent("assertions.json"))
    let images = ["light-top.png", "light-bottom.png", "light-invalid-prompt.png", "dark-top.png", "dark-bottom.png"]
    let figures = try images.map { name -> String in let data = try Data(contentsOf: outdir.appendingPathComponent(name)).base64EncodedString(); return "<figure><img src=\"data:image/png;base64,\(data)\"><figcaption>\(name)</figcaption></figure>" }.joined()
    let html = "<!doctype html><meta charset=utf-8><title>yiyi Settings UI journey</title><style>body{font:15px system-ui;max-width:1200px;margin:32px auto;color:#222}h1{font-size:24px}section{margin:24px 0}figure{display:inline-block;width:48%;vertical-align:top;margin:1%}img{width:100%;border:1px solid #ccc}code{white-space:pre-wrap}</style><h1>yiyi Settings UI journey</h1><p>Off-screen rendering of the real AppKit view hierarchy; no host pixels or synthetic input.</p><section><h2>Verdict: PASS</h2><p>Semantic interaction, persistence, prompt validation, layout invariants, and light/dark geometry passed.</p></section><section>\(figures)</section><section><h2>Assertions</h2><code>\(String(data: json, encoding: .utf8)!)</code></section><p>Not covered: host-level ⌘- and super+t; use a disposable VM or brook's manual press.</p>"
    try html.write(to: outdir.appendingPathComponent("report.html"), atomically: true, encoding: .utf8)
}

private extension NSView {
    var allSubviews: [NSView] { subviews + subviews.flatMap(\.allSubviews) }
    func findText(_ needle: String) -> Bool { (self as? NSTextField)?.stringValue.contains(needle) == true || subviews.contains { $0.findText(needle) } }
    func geometryTree() -> [String: String] { Dictionary(uniqueKeysWithValues: allSubviews.enumerated().map { ("\($0.offset):\(type(of: $0.element))", NSStringFromRect($0.element.frame)) }) }
}
