import AppKit
import YiyiCore
import OSLog

private let superKeyLogger = Logger(subsystem: "cc.blackblue.yiyi", category: "superkey")

final class SuperKeyMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var matcher = SuperKeyMatcher(superKey: .none, bindings: [:])
    private var superKey: SuperKey = .none
    private var bindings: [UInt32: Int] = [:]
    private var creationFailure: String?
    var onMatch: ((Int) -> Void)?
    private(set) var status = "off"
    var isCreated: Bool { tap != nil }
    var isEnabled: Bool { tap.map(CGEvent.tapIsEnabled(tap:)) ?? false }

    func configure(superKey: SuperKey, commands: [CommandConfig], trusted: Bool) {
        stop()
        self.superKey = superKey
        for (index, command) in commands.enumerated() {
            if let binding = try? effectiveBinding(command.hotkey, superKey: superKey), case let .superKey(keyCode) = binding { bindings[keyCode] = index }
        }
        matcher = SuperKeyMatcher(superKey: superKey, bindings: bindings)
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
            creationFailure = trusted ? "tap creation failed" : "Accessibility missing"
            status = creationFailure!
            superKeyLogger.error("yiyi: superkey tap creation failed trusted=\(trusted)")
            return
        }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        status = CGEvent.tapIsEnabled(tap: tap) ? "tap active" : "tap created but disabled"
        superKeyLogger.notice("yiyi: superkey tap created enabled=\(self.isEnabled) bindings=\(self.bindings.count) leader=\(self.superKey.rawValue, privacy: .public)")
    }

    func consumeForSelfTest(type: CGEventType, keyCode: CGKeyCode, flags: UInt64) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: type != .keyUp) else { return }
        event.type = type
        event.flags = CGEventFlags(rawValue: flags)
        _ = handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                status = CGEvent.tapIsEnabled(tap: tap) ? "tap active" : "tap created but disabled"
                superKeyLogger.error("yiyi: superkey tap recovered reason=\(String(describing: type)) enabled=\(self.isEnabled)")
            }
            return Unmanaged.passUnretained(event)
        }
        let eventType: SuperKeyEventType
        switch type {
        case .flagsChanged: eventType = .flagsChanged
        case .keyDown: eventType = .keyDown
        default: return Unmanaged.passUnretained(event)
        }
        if keyCode == superKey.keyCode.map(UInt32.init) || bindings[keyCode] != nil {
            superKeyLogger.notice("tap callback type=\(type.rawValue) keyCode=\(keyCode) flags=0x\(String(event.flags.rawValue, radix: 16), privacy: .public) enabled=\(self.isEnabled)")
        }
        let description = SuperKeyEvent(
            type: eventType,
            keyCode: keyCode,
            deviceFlags: event.flags.rawValue
        )
        guard let index = matcher.consume(description) else {
            return Unmanaged.passUnretained(event)
        }
        superKeyLogger.notice("matcher matched command=\(index) keyCode=\(description.keyCode)")
        onMatch?(index)
        superKeyLogger.notice("notification posting command=\(index)")
        NotificationCenter.default.post(name: .yiyiHotkey, object: index)
        return nil
    }

    private func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        source = nil; tap = nil; matcher = SuperKeyMatcher(superKey: .none, bindings: [:]); bindings.removeAll(); creationFailure = nil; status = "off"
    }

    deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }
}
