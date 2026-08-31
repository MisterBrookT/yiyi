import AppKit
import Foundation
import YiyiCore

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
