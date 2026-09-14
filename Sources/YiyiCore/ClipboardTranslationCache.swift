import Foundation

/// One in-memory result; clipboard counters distinguish our automatic copy
/// from a new user copy, even when the strings happen to be identical.
public struct ClipboardTranslationCache {
    public struct Value: Equatable {
        public let text: String
    }
    private var source: String?
    private var commandIndex: Int?
    private var config: YiyiConfig?
    private var value: Value?
    private var writtenText: String?
    private var writtenCount: Int?
    public init() {}

    public func ownsClipboard(_ text: String, changeCount: Int) -> Bool {
        writtenCount == changeCount && writtenText == text
    }
    public func input(for clipboard: String, changeCount: Int) -> String {
        if writtenCount == changeCount, writtenText == clipboard, let source { return source }
        return clipboard
    }
    public func lookup(input: String, commandIndex: Int, config: YiyiConfig) -> Value? {
        guard source == input, self.commandIndex == commandIndex, self.config == config else { return nil }
        return value
    }
    public mutating func begin(input: String, commandIndex: Int, config: YiyiConfig) {
        source = input; self.commandIndex = commandIndex; self.config = config
        value = nil; writtenCount = nil; writtenText = nil
    }
    public mutating func store(text: String) {
        value = Value(text: text)
    }
    public mutating func markClipboardWrite(text: String, changeCount: Int) {
        writtenText = text; writtenCount = changeCount
    }
}
