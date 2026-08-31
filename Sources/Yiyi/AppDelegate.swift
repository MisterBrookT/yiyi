import AppKit
import ServiceManagement
import YiyiCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configs = ConfigManager(), hotkeys = HotkeyManager(), panel = ResultPanelController()
    private lazy var settings = SettingsWindowController(configs: configs) { [weak self] in self?.hotkeys.superKeyStatus ?? "off" }
    private var statusItem: NSStatusItem!
    private var lastResult: String?
    private var didRequestAccessibility = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength); statusItem.button?.title = "译"
        NotificationCenter.default.addObserver(forName: .yiyiHotkey, object: nil, queue: .main) { [weak self] note in
            let index = note.object as? Int ?? 0
            Task { @MainActor in self?.runCommand(index: index) }
        }
        configs.onChange = { [weak self] in self?.configDidChange() }
        reloadConfig(showErrors: true)
        if !SelectionCapture.isTrusted(prompt: false), !UserDefaults.standard.bool(forKey: "yiyi.onboarded") {
            UserDefaults.standard.set(true, forKey: "yiyi.onboarded")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.showOnboarding() }
        }
    }

    private func showOnboarding() {
        panel.showNotice(command: "yiyi",
                         message: "⌘- translates the selected text, ⌘⇧- translates it into English.\n\nTo read the selection in other apps, yiyi needs Accessibility access. Without it, it translates whatever is on the clipboard.",
                         hints: "⏎ enable accessibility   esc later") { [weak self] in self?.openAccessibilitySettings() }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        add("Translate now", action: #selector(translateNow), to: menu)
        if configs.config.commands.count > 1 {
            let submenu = NSMenu()
            for (index, command) in configs.config.commands.enumerated() { let item = add(command.name, action: #selector(runMenuCommand(_:)), to: submenu); item.tag = index }
            let parent = NSMenuItem(title: "Commands", action: nil, keyEquivalent: ""); parent.submenu = submenu; menu.addItem(parent)
        }
        let providers = NSMenu()
        for name in configs.config.providers.keys.sorted() {
            let availability = configs.providerAvailability(name)
            let item = add(name, action: #selector(selectProvider(_:)), to: providers); item.representedObject = name
            item.state = name == configs.config.defaultProvider ? .on : .off; item.isEnabled = availability.usable; item.toolTip = availability.reason
        }
        let providerParent = NSMenuItem(title: "Provider", action: nil, keyEquivalent: ""); providerParent.submenu = providers; menu.addItem(providerParent)
        menu.addItem(.separator())
        add("Settings…", action: #selector(openSettings), key: ",", to: menu)
        add("Edit config…", action: #selector(editConfig), to: menu)
        add("Reload config", action: #selector(reload), to: menu)
        let copy = add("Copy last result", action: #selector(copyLast), to: menu); copy.isEnabled = lastResult != nil
        let login = add("Launch at login", action: #selector(toggleLogin(_:)), to: menu); login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if !SelectionCapture.isTrusted(prompt: false) {
            let item = add("Enable Accessibility…", action: #selector(openAccessibilitySettings), to: menu)
            item.toolTip = accessibilityHint
        }
        menu.addItem(.separator()); add("Quit", action: #selector(NSApplication.terminate(_:)), key: "q", to: menu)
        statusItem.menu = menu
    }

    @discardableResult private func add(_ title: String, action: Selector, key: String = "", to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item); return item
    }
    @objc private func translateNow() { runCommand(index: 0) }
    @objc private func runMenuCommand(_ sender: NSMenuItem) { runCommand(index: sender.tag) }
    @objc private func reload() { reloadConfig(showErrors: true) }
    @objc private func editConfig() { NSWorkspace.shared.open(configs.fileURL) }
    @objc private func openSettings() { settings.show() }
    @objc private func copyLast() { if let lastResult { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(lastResult, forType: .string) } }
    @objc private func selectProvider(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        do { try configs.setDefaultProvider(name); rebuildMenu() } catch { panel.showError(message: "Could not save provider", detail: error.localizedDescription) }
    }
    @objc private func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
            sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } catch { panel.showError(message: "Could not change launch at login", detail: error.localizedDescription) }
    }

    private func reloadConfig(showErrors: Bool) {
        do {
            try configs.load(); let errors = hotkeys.register(configs.config.commands, superKey: configs.config.superKey); rebuildMenu()
            if showErrors, !errors.isEmpty { panel.showError(message: "Some hotkeys could not be registered", detail: errors.joined(separator: "\n")) }
        } catch { panel.showError(message: "Config could not be loaded", detail: error.localizedDescription) }
    }

    private func configDidChange() {
        let errors = hotkeys.register(configs.config.commands, superKey: configs.config.superKey)
        rebuildMenu()
        if !errors.isEmpty { panel.showError(message: "Some hotkeys could not be registered", detail: errors.joined(separator: "\n")) }
    }

    private func runCommand(index: Int) {
        guard configs.config.commands.indices.contains(index) else { return }
        let command = configs.config.commands[index]
        let trusted = SelectionCapture.isTrusted(prompt: false)
        if !trusted { requestAccessibilityOnce() }
        Task {
            guard let input = await SelectionCapture.capture(synthesize: trusted), !input.isEmpty else {
                panel.showError(command: command.name,
                                message: trusted ? "No selected or clipboard text found"
                                                 : "Nothing on the clipboard — copy the text first, or enable Accessibility",
                                detail: trusted ? nil : accessibilityHint)
                return
            }
            do {
                let provider = try resolveProvider(config: configs.config, command: command)
                let key = try configs.apiKey(for: provider.name)
                panel.showLoading(command: command.name, source: input, provider: provider.name, model: provider.model)
                let prompt = try renderPrompt(command.prompt, input: input)
                let result = try await OpenAIClient().complete(prompt: prompt, provider: provider, apiKey: key)
                lastResult = result
                if configs.config.autoCopy { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result, forType: .string) }
                panel.showResult(result); rebuildMenu()
            } catch let error as OpenAIError {
                showProviderError(error, command: command)
            } catch {
                let provider = (try? resolveProvider(config: configs.config, command: command))
                panel.showError(command: command.name, provider: provider?.name ?? "", model: provider?.model ?? "", message: error.localizedDescription)
            }
        }
    }

    private func showProviderError(_ error: OpenAIError, command: CommandConfig) {
        let provider = try? resolveProvider(config: configs.config, command: command)
        let name = provider?.name ?? configs.config.defaultProvider
        if case let .http(status, body) = error {
            let reason = status == 401 ? "unauthorized — check \(provider?.apiKeyEnv ?? "API key")" : "request failed (HTTP \(status))"
            panel.showError(command: command.name, provider: name, model: provider?.model ?? "", message: "\(name): \(status) \(reason)", detail: body)
        } else { panel.showError(command: command.name, provider: name, model: provider?.model ?? "", message: "\(name): \(error.localizedDescription)") }
    }

    /// LSUIElement apps must never run a modal alert here: an unseen `runModal()` blocks the
    /// main run loop and silently kills every later hotkey. Ask tccd once per launch instead
    /// and keep working in clipboard-only mode.
    private var accessibilityHint: String {
        "Enable yiyi in System Settings → Privacy & Security → Accessibility to translate the current selection. Until then yiyi translates the clipboard."
    }

    private func requestAccessibilityOnce() {
        guard !didRequestAccessibility else { return }
        didRequestAccessibility = true
        _ = SelectionCapture.isTrusted(prompt: true)
    }

    @objc private func openAccessibilitySettings() {
        _ = SelectionCapture.isTrusted(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
}
