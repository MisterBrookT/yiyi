import AppKit
import ServiceManagement
import YiyiCore
import OSLog

private let appLogger = Logger(subsystem: "cc.blackblue.yiyi", category: "dispatch")

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configs = ConfigManager(), hotkeys = HotkeyManager(), panel = ResultPanelController()
    private let pointer = PointerGestureMonitor()
    private lazy var settings = SettingsWindowController(
        configs: configs,
        accessibilityStatus: { [weak self] in self?.accessibilityStatus() ?? AccessibilityStatus(trusted: false, superKeyTapStatus: "unknown", signatureIdentity: "unavailable", advice: .awaitGrant) },
        requestAccessibility: { [weak self] in self?.openAccessibilitySettings() },
        repairAccessibility: { [weak self] in self?.repairAccessibilityPermission() },
        reloadFromDisk: { [weak self] in self?.reloadConfig(showErrors: true) },
        pointerStatus: { [weak self] in self?.pointer.status ?? "Off" },
        launchAtLogin: (
            get: { SMAppService.mainApp.status == .enabled },
            set: { [weak self] enabled in self?.setLaunchAtLogin(enabled) }
        )
    )
    private var statusItem: NSStatusItem!
    private var requests = LatestRequest()
    private var clipboardCache = ClipboardTranslationCache()
    private var isCapturing = false
    private var accessibilityPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditingMenu(settingsTarget: self)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let font = NSFont(name: "PingFangSC-Semibold", size: 15) ?? .systemFont(ofSize: 15, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let glyph = "译" as NSString
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let bounds = glyph.size(withAttributes: attributes)
            glyph.draw(
                at: NSPoint(x: (18 - bounds.width) / 2, y: (18 - bounds.height) / 2),
                withAttributes: attributes
            )
            return true
        }
        image.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.title = ""
        statusItem.button?.setAccessibilityLabel("yiyi")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        NotificationCenter.default.addObserver(forName: .yiyiHotkey, object: nil, queue: .main) { [weak self] note in
            let index = note.object as? Int ?? 0
            appLogger.notice("notification received command=\(index)")
            Task { @MainActor in self?.runCommand(index: index) }
        }
        configs.onChange = { [weak self] in self?.configDidChange() }
        pointer.onTrigger = { [weak self] index, selection in
            let clipboard = NSPasteboard.general.string(forType: .string)
            let capture = CaptureDecision(text: selection ?? clipboard, source: selection == nil ? .clipboard : .selection)
            self?.runCommand(index: index, presetCapture: capture)
        }
        reloadConfig(showErrors: true)
        let initialAccessibility = AccessibilityState.observe()
        handleAccessibilityAdvice(initialAccessibility.advice)
        startAccessibilityPollingIfNeeded(trusted: initialAccessibility.trusted)
        if CommandLine.arguments.contains("--settings") { settings.show() }
    }


    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard settings.window?.isVisible == true else { return .terminateNow }
        settings.confirmDiscardForTermination { allowed in
            DispatchQueue.main.async { sender.reply(toApplicationShouldTerminate: allowed) }
        }
        return .terminateLater
    }

    /// The menu-bar icon is a single door: click opens Settings. Right-click (or Control-click)
    /// offers Quit so the app remains easy to leave. Everything else lives in Settings.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let secondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        guard secondary else { openSettings(); return }
        let menu = NSMenu()
        add("Settings…", action: #selector(openSettings), key: ",", to: menu)
        menu.addItem(.separator())
        // Quit must target NSApp: this delegate does not respond to terminate: and AppKit
        // disables any item whose target cannot perform its action.
        add("Quit yiyi", action: #selector(NSApplication.terminate(_:)), key: "q", to: menu).target = NSApp
        statusItem.menu = menu
        sender.performClick(nil)
        statusItem.menu = nil
    }

    @discardableResult private func add(_ title: String, action: Selector, key: String = "", to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item); return item
    }
    @objc func openSettings() { settings.show() }
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { panel.showError(message: "Could not change launch at login", detail: error.localizedDescription) }
    }

    private func reloadConfig(showErrors: Bool) {
        do {
            try configs.load(); let errors = hotkeys.register(configs.config.commands, superKey: configs.config.superKey)
            pointer.configure(config: configs.config.pointerTrigger, commandCount: configs.config.commands.count)
            if showErrors, !errors.isEmpty { panel.showError(message: "Some hotkeys could not be registered", detail: errors.joined(separator: "\n")) }
        } catch { panel.showError(message: "Config could not be loaded", detail: error.localizedDescription) }
    }

    private func configDidChange() {
        pointer.configure(config: configs.config.pointerTrigger, commandCount: configs.config.commands.count)
        let errors = hotkeys.register(configs.config.commands, superKey: configs.config.superKey)
        if !errors.isEmpty { panel.showError(message: "Some hotkeys could not be registered", detail: errors.joined(separator: "\n")) }
    }

    private func runCommand(index: Int, presetCapture: CaptureDecision? = nil) {
        appLogger.notice("runCommand entered command=\(index)")
        guard !isCapturing, configs.config.commands.indices.contains(index) else { return }
        let command = configs.config.commands[index]
        let frozen = configs.makeDraft()
        let resolution = Result { let provider = try resolveProvider(config: frozen.config, command: command); return (provider, try frozen.apiKey(for: provider.name)) }
        let autoCopy = frozen.config.autoCopy
        let requestID = requests.begin()
        isCapturing = true
        // AX trust can change after launch. This observation deliberately happens for every
        // invocation; no launch-time value is used to decide whether synthetic copy is allowed.
        let accessibility = AccessibilityState.observe()
        startAccessibilityPollingIfNeeded(trusted: accessibility.trusted)
        let clipboardCount = NSPasteboard.general.changeCount
        let clipboard = NSPasteboard.general.string(forType: .string).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        Task {
            let capture: CaptureDecision
            if !promptNeedsSelection(command.prompt) { capture = CaptureDecision(text: clipboard, source: clipboard == nil ? .empty : .clipboard) }
            else if let presetCapture { capture = presetCapture }
            else { capture = await SelectionCapture.capture(trusted: accessibility.trusted) }
            isCapturing = false
            guard requests.isCurrent(requestID) else { return }
            appLogger.notice("capture completed source=\(capture.source.rawValue, privacy: .public) hasText=\(capture.text != nil)")
            guard let capturedInput = capture.text else {
                if accessibility.trusted {
                    panel.showError(command: command.name, message: "No selected or clipboard text found")
                } else {
                    panel.showNotice(
                        command: command.name,
                        message: "Nothing on the clipboard. Accessibility is not active in this yiyi process.",
                        actionTitle: "Relaunch"
                    ) { [weak self] in self?.relaunch() }
                }
                return
            }
            // Selection requests continue to use their actual selection. Cache only
            // clipboard captures, including explicitly clipboard-only prompts.
            let usesClipboard = capture.source == .clipboard
            let input = usesClipboard
                ? clipboardCache.input(for: capturedInput, changeCount: clipboardCount)
                : capturedInput
            let promptClipboard = usesClipboard ? input : clipboard
            let displayCapture = CaptureDecision(text: input, source: capture.source, hint: capture.hint)
            if usesClipboard, let cached = clipboardCache.lookup(input: input, commandIndex: index, config: frozen.config) {
                panel.showLoading(command: command.name, capture: displayCapture)
                panel.showResult(cached.text)
                if autoCopy {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cached.text, forType: .string)
                    clipboardCache.markClipboardWrite(text: cached.text, changeCount: NSPasteboard.general.changeCount)
                }
                return
            }
            do {
                let (provider, key) = try resolution.get()
                panel.showLoading(
                    command: command.name,
                    capture: displayCapture,
                    relaunch: accessibility.trusted ? nil : { [weak self] in self?.relaunch() }
                )
                let prompt = try renderPrompt(command.prompt, input: input, clipboard: promptClipboard)
                let result = try await OpenAIClient().complete(prompt: prompt, provider: provider, apiKey: key)
                guard requests.isCurrent(requestID) else { return }
                appLogger.notice("provider completed characters=\(result.count)")
                if usesClipboard {
                    clipboardCache.begin(input: input, commandIndex: index, config: frozen.config)
                    clipboardCache.store(text: result)
                }
                if autoCopy {
                    let before = NSPasteboard.general.changeCount
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                    if usesClipboard { clipboardCache.markClipboardWrite(text: result, changeCount: NSPasteboard.general.changeCount) }
                    appLogger.notice("changeCount \(before)->\(NSPasteboard.general.changeCount) entity=autoCopy")
                }
                panel.showResult(result)
            } catch let error as OpenAIError {
                guard requests.isCurrent(requestID) else { return }
                showProviderError(error, command: command, provider: try? resolution.get().0)
            } catch {
                guard requests.isCurrent(requestID) else { return }
                let provider = try? resolution.get().0
                panel.showError(command: command.name, provider: provider?.name ?? "", model: provider?.model ?? "", message: error.localizedDescription)
            }
        }
    }

    private func showProviderError(_ error: OpenAIError, command: CommandConfig, provider: ResolvedProvider?) {
        let name = provider?.name ?? "Connection"
        if case let .http(status, body) = error {
            let reason = status == 401 ? "unauthorized — check \(provider?.apiKeyEnv ?? "API key")" : "request failed (HTTP \(status))"
            panel.showError(command: command.name, provider: name, model: provider?.model ?? "", message: "\(name): \(status) \(reason)", detail: body)
        } else { panel.showError(command: command.name, provider: name, model: provider?.model ?? "", message: "\(name): \(error.localizedDescription)") }
    }

    private var accessibilityHint: String {
        "Enable yiyi in System Settings → Privacy & Security → Accessibility to translate the current selection. Until then yiyi translates the clipboard."
    }

    private var staleGrantMessage: String {
        "The existing Accessibility grant belongs to an older yiyi build. Repair it to reset only yiyi's entry and request permission again."
    }

    private func accessibilityStatus() -> AccessibilityStatus {
        let state = AccessibilityState.observe()
        return AccessibilityStatus(
            trusted: state.trusted,
            superKeyTapStatus: hotkeys.superKeyStatus,
            signatureIdentity: AccessibilityState.shortSignature(state.signature),
            advice: state.advice
        )
    }

    private func handleAccessibilityAdvice(_ advice: AccessibilityAdvice) {
        switch advice {
        case .promptOnce:
            AccessibilityState.requestSystemPrompt()
        case .repairStaleGrant:
            showStaleGrantNotice()
        case .ok, .awaitGrant:
            break
        }
    }

    private func showStaleGrantNotice() {
        panel.showNotice(command: "Accessibility",
                         message: staleGrantMessage,
                         actionTitle: "Repair Permission") { [weak self] in self?.repairAccessibilityPermission() }
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityState.requestSystemPrompt()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }

    @objc private func repairAccessibilityPermission() {
        AccessibilityState.resetAccessibility { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                UserDefaults.standard.set(true, forKey: AccessibilityState.hasPromptedKey)
                UserDefaults.standard.set(true, forKey: AccessibilityState.repairAttemptedKey)
                UserDefaults.standard.removeObject(forKey: AccessibilityState.grantedSignatureKey)
                AccessibilityState.requestSystemPrompt()
                startAccessibilityPollingIfNeeded(trusted: false)
            case let .failure(error):
                panel.showError(message: "Could not repair Accessibility permission", detail: error.localizedDescription)
            }
        }
    }

    private func startAccessibilityPollingIfNeeded(trusted: Bool) {
        if trusted {
            accessibilityPollTimer?.invalidate()
            accessibilityPollTimer = nil
            return
        }
        guard accessibilityPollTimer == nil else { return }
        accessibilityPollTimer = Timer.scheduledTimer(
            timeInterval: 2,
            target: self,
            selector: #selector(pollAccessibility),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func pollAccessibility() {
        let state = AccessibilityState.observe()
        guard state.trusted else { return }
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
        let errors = hotkeys.register(configs.config.commands, superKey: configs.config.superKey)
        NSLog("yiyi: Accessibility became trusted; hotkeys re-registered tap=%@", hotkeys.superKeyStatus)
        if !errors.isEmpty {
            panel.showError(message: "Some hotkeys could not be registered", detail: errors.joined(separator: "\n"))
        }
    }

    @objc private func relaunch() {
        let applicationURL = URL(fileURLWithPath: "/Applications/yiyi.app", isDirectory: true)
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            guard error == nil else {
                Task { @MainActor in
                    self.panel.showError(message: "Could not relaunch yiyi", detail: error?.localizedDescription)
                }
                return
            }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
