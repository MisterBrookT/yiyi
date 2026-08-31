import AppKit
import ApplicationServices

@MainActor enum SelectionCapture {
    static func isTrusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func capture() async -> String? {
        let pasteboard = NSPasteboard.general
        let fallback = pasteboard.string(forType: .string)
        let saved = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { values, type in values[type] = item.data(forType: type) }
        } ?? []
        let oldCount = pasteboard.changeCount
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        down?.flags = .maskCommand; up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        let deadline = Date().addingTimeInterval(0.4)
        while pasteboard.changeCount == oldCount, Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        let selected = pasteboard.changeCount != oldCount ? pasteboard.string(forType: .string) : nil
        pasteboard.clearContents()
        for values in saved {
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            pasteboard.writeObjects([item])
        }
        return selected?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? selected : fallback
    }
}
