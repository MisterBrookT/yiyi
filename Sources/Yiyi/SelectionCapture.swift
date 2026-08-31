import AppKit
import ApplicationServices
import YiyiCore

@MainActor enum SelectionCapture {
    static func isTrusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func capture(trusted: Bool) async -> CaptureDecision {
        let pasteboard = NSPasteboard.general
        let fallback = pasteboard.string(forType: .string)
        guard shouldSynthesizeSelection(trusted: trusted) else {
            return chooseCaptureInput(
                trusted: false,
                changeCountAdvanced: false,
                capturedText: nil,
                clipboardText: fallback
            )
        }

        let saved = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { values, type in
                values[type] = item.data(forType: type)
            }
        } ?? []
        let oldCount = pasteboard.changeCount

        // The global hotkey fires while its physical chord may still be down. Posting another
        // command chord during that overlap is unreliable in some target applications.
        let modifierDeadline = Date().addingTimeInterval(0.3)
        let triggerModifiers: NSEvent.ModifierFlags = [.command, .shift, .control, .option]
        while !NSEvent.modifierFlags.intersection(triggerModifiers).isEmpty, Date() < modifierDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        let eventSource = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 8, keyDown: true)
        let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 8, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        let captureDeadline = Date().addingTimeInterval(1.0)
        while pasteboard.changeCount == oldCount, Date() < captureDeadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let advanced = pasteboard.changeCount != oldCount
        let captured = advanced ? pasteboard.string(forType: .string) : nil

        pasteboard.clearContents()
        for values in saved {
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            pasteboard.writeObjects([item])
        }

        return chooseCaptureInput(
            trusted: true,
            changeCountAdvanced: advanced,
            capturedText: captured,
            clipboardText: fallback
        )
    }
}
