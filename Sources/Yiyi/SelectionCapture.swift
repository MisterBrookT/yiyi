import AppKit
import ApplicationServices
import OSLog
import YiyiCore

private let captureLogger = Logger(subsystem: "cc.blackblue.yiyi", category: "capture")

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
                sentinelText: nil,
                snapshotText: fallback,
                observedText: nil,
                accessibilitySelectedText: nil,
                clipboardText: fallback
            )
        }

        let saved = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { values, type in
                values[type] = item.data(forType: type)
            }
        } ?? []
        let oldCount = pasteboard.changeCount
        let focused = focusedSelection()
        let axSelection = focused.text
        let sentinel = "__yiyi_capture_\(UUID().uuidString)__"
        let started = ContinuousClock.now
        captureLogger.notice("capture begin oldCount=\(oldCount) hasClipboard=\(fallback != nil) hasAXSelection=\(axSelection != nil)")

        pasteboard.clearContents()
        pasteboard.setString(sentinel, forType: .string)
        var lastCount = pasteboard.changeCount
        captureLogger.notice("changeCount \(oldCount)->\(lastCount) elapsedMs=\(milliseconds(since: started)) entity=sentinel")

        // The physical super-key may still be held. Explicit flags on both events produce a
        // balanced Command-C chord independent of the HID modifier state.
        let modifierDeadline = ContinuousClock.now + .milliseconds(300)
        let triggerModifiers: NSEvent.ModifierFlags = [.command, .shift, .control, .option]
        while !NSEvent.modifierFlags.intersection(triggerModifiers).isEmpty,
              ContinuousClock.now < modifierDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        let eventSource = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 8, keyDown: true)
        let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 8, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        if let targetPID = focused.pid {
            down?.postToPid(targetPID)
            up?.postToPid(targetPID)
        } else {
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
        captureLogger.notice("synthetic command-c posted elapsedMs=\(milliseconds(since: started)) physicalModifiers=\(NSEvent.modifierFlags.rawValue)")

        var observed: String?
        let captureDeadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < captureDeadline {
            let count = pasteboard.changeCount
            if count != lastCount {
                let value = pasteboard.string(forType: .string)
                captureLogger.notice("changeCount \(lastCount)->\(count) elapsedMs=\(milliseconds(since: started)) entity=external")
                lastCount = count
                if value != sentinel {
                    observed = value
                    if axSelection == nil || value == axSelection { break }
                }
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let decision = chooseCaptureInput(
            trusted: true,
            sentinelText: sentinel,
            snapshotText: fallback,
            observedText: observed,
            accessibilitySelectedText: axSelection,
            clipboardText: fallback
        )
        captureLogger.notice("capture decision source=\(decision.source.rawValue, privacy: .public) elapsedMs=\(milliseconds(since: started))")

        let beforeRestore = pasteboard.changeCount
        pasteboard.clearContents()
        for values in saved {
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            pasteboard.writeObjects([item])
        }
        captureLogger.notice("changeCount \(beforeRestore)->\(pasteboard.changeCount) elapsedMs=\(milliseconds(since: started)) entity=restore")
        return decision
    }

    private static func focusedSelection() -> (text: String?, pid: pid_t?) {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused as! AXUIElement? else { return (nil, nil) }
        var pid: pid_t = 0
        let pidResult = AXUIElementGetPid(element, &pid)
        var selected: CFTypeRef?
        let text = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success
            ? selected as? String
            : nil
        return (text, pidResult == .success ? pid : nil)
    }

    private static func milliseconds(since instant: ContinuousClock.Instant) -> Int64 {
        let duration = instant.duration(to: .now)
        return duration.components.seconds * 1_000 + Int64(duration.components.attoseconds / 1_000_000_000_000_000)
    }
}
