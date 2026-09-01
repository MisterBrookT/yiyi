import AppKit
import Foundation
import YiyiCore

if CommandLine.arguments.contains("--selftest-superkey") {
    Task { @MainActor in
        do {
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            let manager = ConfigManager()
            try manager.load()
            let monitor = SuperKeyMonitor()
            var dispatched = false
            monitor.onMatch = { index in
                dispatched = true
                print("match command=\(index)")
                print("dispatch command=\(index)")
                print("PASS tap callback -> match -> dispatch")
                fflush(stdout)
                exit(0)
            }
            monitor.configure(superKey: manager.config.superKey, commands: manager.config.commands, trusted: AXIsProcessTrusted())
            print("tap.created=\(monitor.isCreated) tap.enabled=\(monitor.isEnabled)")
            guard monitor.isEnabled else { throw NSError(domain: "yiyi.selftest", code: 1, userInfo: [NSLocalizedDescriptionKey: "event tap is not enabled"]) }
            print("inject flagsChanged keyCode=54 flags=0x100000")
            monitor.consumeForSelfTest(type: .flagsChanged, keyCode: 54, flags: 0x100000)
            monitor.consumeForSelfTest(type: .keyDown, keyCode: 27, flags: 0x100000)
            guard dispatched else {
                fputs("FAIL no matched command was dispatched\n", stderr)
                exit(1)
            }
        } catch {
            fputs("yiyi selftest-superkey: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    RunLoop.main.run()
} else
if CommandLine.arguments.contains("--diagnose") {
    Task { @MainActor in
        do {
            let manager = ConfigManager()
            try manager.load()
            let hotkeys = HotkeyManager()
            let errors = hotkeys.register(manager.config.commands, superKey: manager.config.superKey)
            print("trusted=\(AXIsProcessTrusted())")
            print("tap.created=\(hotkeys.superKeyTapCreated)")
            print("tap.enabled=\(hotkeys.superKeyTapEnabled)")
            print("tap.status=\(hotkeys.superKeyStatus)")
            print("leader=\(manager.config.superKey.rawValue) keyCode=\(manager.config.superKey.keyCode.map(String.init) ?? "none") deviceFlag=0x\(String(manager.config.superKey.deviceFlag, radix: 16))")
            for (index, command) in manager.config.commands.enumerated() {
                let kind: String
                switch try effectiveBinding(command.hotkey, superKey: manager.config.superKey) {
                case let .superKey(keyCode): kind = "superKey keyCode=\(keyCode)"
                case let .carbon(parsed): kind = "carbon keyCode=\(parsed.keyCode) modifiers=0x\(String(parsed.modifiers, radix: 16))"
                }
                print("binding[\(index)]=\(command.name): \(command.hotkey) -> \(kind)")
            }
            if !errors.isEmpty { print("errors=\(errors.joined(separator: "; "))") }
            exit(errors.isEmpty && hotkeys.superKeyTapEnabled ? 0 : 1)
        } catch {
            fputs("yiyi diagnose: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    RunLoop.main.run()
} else
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--translate" {
    let input = CommandLine.arguments.dropFirst(2).joined(separator: " ")
    Task { @MainActor in
        do {
            let manager = ConfigManager(); try manager.load()
            guard let command = manager.config.commands.first else { throw OpenAIError.provider("No command configured") }
            let provider = try resolveProvider(config: manager.config, command: command)
            let key = try manager.apiKey(for: provider.name)
            let prompt = try renderPrompt(command.prompt, input: input)
            print(try await OpenAIClient().complete(prompt: prompt, provider: provider, apiKey: key)); exit(0)
        } catch { fputs("yiyi: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    RunLoop.main.run()
} else if let journeyIndex = CommandLine.arguments.firstIndex(of: "--ui-journey"), CommandLine.arguments.indices.contains(journeyIndex + 1) {
    let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
    do {
        try runUIJourney(outdir: URL(fileURLWithPath: CommandLine.arguments[journeyIndex + 1], isDirectory: true))
        exit(0)
    } catch {
        fputs("yiyi ui journey: \(error.localizedDescription)\n", stderr); exit(1)
    }
} else if CommandLine.arguments.contains("--preview") {
    let app = NSApplication.shared; app.setActivationPolicy(.regular)
    if CommandLine.arguments.contains("dark") { app.appearance = NSAppearance(named: .darkAqua) }
    else if CommandLine.arguments.contains("light") { app.appearance = NSAppearance(named: .aqua) }
    let preview = ResultPanelController(closesOnResign: false)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        if CommandLine.arguments.contains("edge"), let screen = NSScreen.main {
            let point = CGPoint(x: screen.visibleFrame.maxX - 1, y: screen.frame.height - screen.visibleFrame.minY - 1)
            CGWarpMouseCursorPosition(point)
        }
        preview.showLoading(command: "Translate to Chinese", source: "Design is intelligence made visible.", provider: "deepseek", model: "deepseek-v4-flash")
        preview.showResult("设计是可视化的智慧。\n\n安静的界面让内容成为主角。")
    }
    app.run()
} else {
    let app = NSApplication.shared, delegate = AppDelegate()
    app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
}
