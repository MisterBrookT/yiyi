import AppKit
import ApplicationServices
import YiyiCore

/// Passive Option-click hold listener. It never consumes or mutates pointer events.
@MainActor final class PointerGestureMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var recognizer = PointerGestureRecognizer()
    private var config = PointerTriggerConfig()
    private var selectionSnapshot: String?
    private var holdGeneration = 0
    private var holdPending = false
    private var lastLocation = CGPoint.zero
    private var lastOptionHeld = false

    var onTrigger: ((Int, String?) -> Void)?
    private(set) var status = "Off"
    var isEnabled: Bool { tap.map(CGEvent.tapIsEnabled(tap:)) ?? false }

    func configure(config: PointerTriggerConfig, commandCount: Int) {
        stop()
        self.config = config
        recognizer.configure(enabled: config.enabled)
        guard config.enabled else { status = "Off"; return }
        guard commandCount > 0, (0..<commandCount).contains(config.commandIndex) else {
            status = "Unavailable — choose an existing command"
            return
        }

        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .otherMouseDown, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<PointerGestureMonitor>.fromOpaque(context).takeUnretainedValue()
            let timestamp = event.timestamp
            let location = event.location
            let optionHeld = event.flags.contains(.maskAlternate)
            let snapshot = type == .leftMouseDown && optionHeld ? PointerGestureMonitor.selectedTextSnapshot() : nil
            DispatchQueue.main.async { [weak monitor] in
                monitor?.consume(type: type, timestamp: timestamp, location: location, optionHeld: optionHeld, snapshot: snapshot)
            }
            return Unmanaged.passUnretained(event)
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                eventsOfInterest: mask, callback: callback,
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { status = "Unavailable — Input Monitoring permission may be required"; return }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        status = isEnabled ? "Ready — hold Option and primary click" : "Unavailable — event listener disabled"
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        holdGeneration += 1; holdPending = false
        selectionSnapshot = nil
        recognizer.configure(enabled: false)
        status = "Off"
    }

    func consumeForTesting(_ event: PointerGestureEvent, snapshot: String? = nil) {
        if event.kind == .primaryDown { selectionSnapshot = snapshot }
        lastLocation = CGPoint(x: event.x, y: event.y); lastOptionHeld = event.modifierHeld
        if recognizer.consume(event) {
            let selected = selectionSnapshot
            selectionSnapshot = nil
            onTrigger?(config.commandIndex, selected)
        } else if event.kind == .primaryUp || event.kind == .cancel {
            selectionSnapshot = nil
        }
        guard recognizer.isTracking else { holdGeneration += 1; holdPending = false; return }
        guard !holdPending, event.kind == .primaryDown else { return }
        // Fire while the button is still down: the user sees the command start, then lets go.
        holdGeneration += 1; holdPending = true
        let generation = holdGeneration
        let tick = event.timestamp + PointerGestureRecognizer.minimumDuration + 0.001
        DispatchQueue.main.asyncAfter(deadline: .now() + PointerGestureRecognizer.minimumDuration + 0.02) { [weak self] in
            guard let self, self.holdGeneration == generation else { return }
            self.holdPending = false
            self.consumeForTesting(PointerGestureEvent(kind: .held, timestamp: tick, x: self.lastLocation.x, y: self.lastLocation.y, modifierHeld: self.lastOptionHeld))
        }
    }

    private func consume(type: CGEventType, timestamp: CGEventTimestamp, location: CGPoint, optionHeld: Bool, snapshot: String?) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            recognizer.configure(enabled: false)
            selectionSnapshot = nil
            status = "Interrupted — reopen Settings to retry"
            return
        }
        if type == .flagsChanged {
            lastOptionHeld = optionHeld
            if optionHeld { return }
        }
        let kind: PointerGestureEvent.Kind
        switch type {
        case .leftMouseDown: kind = .primaryDown
        case .leftMouseDragged: kind = .moved
        case .leftMouseUp: kind = .primaryUp
        default: kind = .cancel
        }
        let event = PointerGestureEvent(kind: kind, timestamp: TimeInterval(timestamp) / 1_000_000_000,
                                        x: location.x, y: location.y, modifierHeld: optionHeld)
        consumeForTesting(event, snapshot: snapshot)
    }

    nonisolated private static func selectedTextSnapshot() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        // Two bounded reads, at most ~40 ms; slow AX clients fall back to clipboard.
        AXUIElementSetMessagingTimeout(system, 0.02)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused as! AXUIElement? else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.02)
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

}
