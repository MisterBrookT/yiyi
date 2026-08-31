import Foundation

public struct ParsedHotkey: Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    public init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
}

public enum SuperKey: String, Codable, Sendable, CaseIterable {
    case none, rightCommand, rightOption, rightControl

    public var displayName: String {
        switch self {
        case .none: "off"
        case .rightCommand: "right ⌘"
        case .rightOption: "right ⌥"
        case .rightControl: "right ⌃"
        }
    }

    public var keyCode: UInt16? {
        switch self {
        case .none: nil
        case .rightCommand: 54
        case .rightOption: 61
        case .rightControl: 62
        }
    }

    public var deviceFlag: UInt64 {
        switch self {
        case .none: 0
        case .rightCommand: 0x000010
        case .rightOption: 0x000040
        case .rightControl: 0x002000
        }
    }
}

public enum HotkeyBinding: Equatable, Sendable {
    case carbon(ParsedHotkey)
    case superKey(keyCode: UInt32)
}

public enum SuperKeyEventType: Sendable {
    case flagsChanged
    case keyDown
}

public struct SuperKeyEvent: Sendable {
    public let type: SuperKeyEventType
    public let keyCode: UInt32
    public let deviceFlags: UInt64

    public init(type: SuperKeyEventType, keyCode: UInt32, deviceFlags: UInt64) {
        self.type = type
        self.keyCode = keyCode
        self.deviceFlags = deviceFlags
    }
}

public struct SuperKeyMatcher: Sendable {
    private let leaderFlag: UInt64
    private let bindings: [UInt32: Int]
    private var leaderHeld = false

    public init(superKey: SuperKey, bindings: [UInt32: Int]) {
        leaderFlag = superKey.deviceFlag
        self.bindings = bindings
    }

    public mutating func consume(_ event: SuperKeyEvent) -> Int? {
        switch event.type {
        case .flagsChanged:
            leaderHeld = leaderFlag != 0 && event.deviceFlags & leaderFlag != 0
            return nil
        case .keyDown:
            guard leaderHeld else { return nil }
            return bindings[event.keyCode]
        }
    }
}

public func matchedSuperKeyCommands(
    superKey: SuperKey,
    bindings: [UInt32: Int],
    events: [SuperKeyEvent]
) -> [Int] {
    var matcher = SuperKeyMatcher(superKey: superKey, bindings: bindings)
    return events.compactMap { matcher.consume($0) }
}

public enum HotkeyParseError: Error, Equatable { case empty, unknownModifier(String), unknownKey(String), missingKey, multipleKeys }

public enum HotkeyModifier {
    public static let cmd: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12
}

public func parseHotkey(_ value: String) throws -> ParsedHotkey {
    let parts = value.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
    guard !value.isEmpty else { throw HotkeyParseError.empty }
    var modifiers: UInt32 = 0
    var key: UInt32?
    for part in parts {
        switch part {
        case "cmd", "command": modifiers |= HotkeyModifier.cmd
        case "shift": modifiers |= HotkeyModifier.shift
        case "opt", "option", "alt": modifiers |= HotkeyModifier.option
        case "ctrl", "control": modifiers |= HotkeyModifier.control
        case "":
            // A trailing empty component denotes the '+' key.
            if part == parts.last, parts.count > 1 { if key != nil { throw HotkeyParseError.multipleKeys }; key = 24 }
            else { throw HotkeyParseError.unknownKey(part) }
        default:
            guard key == nil else { throw HotkeyParseError.multipleKeys }
            guard let code = keyCodes[part] else {
                if part.count > 1 { throw HotkeyParseError.unknownModifier(part) }
                throw HotkeyParseError.unknownKey(part)
            }
            key = code
        }
    }
    guard let key else { throw HotkeyParseError.missingKey }
    return ParsedHotkey(keyCode: key, modifiers: modifiers)
}

public func parseBinding(_ value: String) throws -> HotkeyBinding {
    let parts = value.lowercased().split(separator: "+", omittingEmptySubsequences: false)
    if parts.count == 2, parts[0] == "super" || parts[0] == "hyper" {
        let parsed = try parseHotkey(String(parts[1]))
        return .superKey(keyCode: parsed.keyCode)
    }
    return .carbon(try parseHotkey(value))
}

public func effectiveBinding(_ value: String, superKey: SuperKey) throws -> HotkeyBinding {
    let binding = try parseBinding(value)
    guard superKey != .none,
          case let .carbon(parsed) = binding,
          parsed.modifiers == (HotkeyModifier.cmd | HotkeyModifier.shift | HotkeyModifier.option | HotkeyModifier.control)
    else { return binding }
    return .superKey(keyCode: parsed.keyCode)
}

public func formatSuperKeyBinding(keyCode: UInt32) -> String? {
    canonicalKeyNames[keyCode].map { "super+\($0)" }
}

@discardableResult
public func migrateLegacySuperKeyBindings(in config: inout YiyiConfig) -> Bool {
    guard config.superKey != .none else { return false }
    let legacyModifiers = HotkeyModifier.cmd | HotkeyModifier.shift | HotkeyModifier.option | HotkeyModifier.control
    var changed = false
    for index in config.commands.indices {
        guard case let .carbon(parsed) = try? parseBinding(config.commands[index].hotkey),
              parsed.modifiers == legacyModifiers,
              let canonical = formatSuperKeyBinding(keyCode: parsed.keyCode)
        else { continue }
        config.commands[index].hotkey = canonical
        changed = true
    }
    return changed
}

/// Formats modifiers in the canonical order: command, shift, option, control.
public func formatHotkey(keyCode: UInt32, modifiers: UInt32) -> String {
    var parts: [String] = []
    if modifiers & HotkeyModifier.cmd != 0 { parts.append("cmd") }
    if modifiers & HotkeyModifier.shift != 0 { parts.append("shift") }
    if modifiers & HotkeyModifier.option != 0 { parts.append("opt") }
    if modifiers & HotkeyModifier.control != 0 { parts.append("ctrl") }
    guard let key = canonicalKeyNames[keyCode] else { return parts.joined(separator: "+") }
    parts.append(key)
    return parts.joined(separator: "+")
}

private let keyCodes: [String: UInt32] = [
    "a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,
    "1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"=":24,"9":25,"7":26,"-":27,"8":28,"0":29,"]":30,"o":31,"u":32,"[":33,"i":34,"p":35,"l":37,"j":38,"'":39,"k":40,";":41,"\\":42,",":43,"/":44,"n":45,"m":46,".":47,"`":50,
    "space":49,"return":36,"enter":36,"tab":48,"escape":53,"esc":53
]

private let canonicalKeyNames: [UInt32: String] = {
    var names: [UInt32: String] = [:]
    for (name, code) in keyCodes {
        if names[code] == nil { names[code] = name }
    }
    names[24] = "="
    names[36] = "return"
    names[49] = "space"
    names[53] = "escape"
    return names
}()
