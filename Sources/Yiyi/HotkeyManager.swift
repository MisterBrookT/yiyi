import Foundation
import Carbon
import YiyiCore

extension Notification.Name { static let yiyiHotkey = Notification.Name("cc.blackblue.yiyi.hotkey") }

@MainActor final class HotkeyManager {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private let superKeyMonitor = SuperKeyMonitor()
    var superKeyStatus: String { superKeyMonitor.status }
    var superKeyTapCreated: Bool { superKeyMonitor.isCreated }
    var superKeyTapEnabled: Bool { superKeyMonitor.isEnabled }

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async { NotificationCenter.default.post(name: .yiyiHotkey, object: Int(id.id)) }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    func register(_ commands: [CommandConfig], superKey: SuperKey) -> [String] {
        unregisterAll()
        superKeyMonitor.configure(superKey: superKey, commands: commands, trusted: AXIsProcessTrusted())
        var errors: [String] = []
        for (index, command) in commands.enumerated() where !command.hotkey.isEmpty {
            do {
                switch try effectiveBinding(command.hotkey, superKey: superKey) {
                case let .carbon(parsed):
                    var ref: EventHotKeyRef?
                    let status = RegisterEventHotKey(parsed.keyCode, parsed.modifiers, EventHotKeyID(signature: fourCC("YIYI"), id: UInt32(index)), GetApplicationEventTarget(), 0, &ref)
                    if status == noErr, let ref { refs.append(ref); NSLog("yiyi: registered %@ (%@), OSStatus=%d", command.name, command.hotkey, status) }
                    else { errors.append("\(command.name): RegisterEventHotKey OSStatus \(status)") }
                case .superKey:
                    break
                }
            } catch { errors.append("\(command.name): invalid hotkey '\(command.hotkey)' (\(error))") }
        }
        return errors
    }

    private func unregisterAll() { refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll() }
}

private func fourCC(_ value: String) -> OSType { value.utf8.reduce(0) { ($0 << 8) + OSType($1) } }
