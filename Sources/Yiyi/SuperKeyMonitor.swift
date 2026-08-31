import AppKit
import YiyiCore

final class SuperKeyMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var held = false
    private var superKey: SuperKey = .none
    private var bindings: [UInt32: Int] = [:]
    private(set) var status = "off"

    func configure(superKey: SuperKey, commands: [CommandConfig]) {
        stop()
        self.superKey = superKey
        for (index, command) in commands.enumerated() {
            if let binding = try? parseBinding(command.hotkey), case let .superKey(keyCode) = binding { bindings[keyCode] = index }
        }
        guard superKey != .none else { status = "off"; return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<SuperKeyMonitor>.fromOpaque(context).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(mask), callback: callback,
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            status = "unavailable: enable yiyi in System Settings → Privacy & Security → Accessibility"
            return
        }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        status = "active"
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .flagsChanged {
            held = (event.flags.rawValue & superKey.deviceFlag) != 0
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown, held else { return Unmanaged.passUnretained(event) }
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        guard let index = bindings[keyCode] else { return Unmanaged.passUnretained(event) }
        NotificationCenter.default.post(name: .yiyiHotkey, object: index)
        return nil
    }

    private func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        source = nil; tap = nil; held = false; bindings.removeAll(); status = "off"
    }

    deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }
}
