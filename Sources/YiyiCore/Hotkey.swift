import Foundation

public struct ParsedHotkey: Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    public init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
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

private let keyCodes: [String: UInt32] = [
    "a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,
    "1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"=":24,"9":25,"7":26,"-":27,"8":28,"0":29,"]":30,"o":31,"u":32,"[":33,"i":34,"p":35,"l":37,"j":38,"'":39,"k":40,";":41,"\\":42,",":43,"/":44,"n":45,"m":46,".":47,"`":50,
    "space":49,"return":36,"enter":36,"tab":48,"escape":53,"esc":53
]
