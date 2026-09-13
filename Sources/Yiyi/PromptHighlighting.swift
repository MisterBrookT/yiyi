import AppKit
import YiyiCore

/// Only attributes change: the saved prompt and undoable text remain plain text.
@MainActor func highlightPrompt(_ editor: NSTextView) {
    guard !editor.hasMarkedText(), let storage = editor.textStorage else { return }
    let fullRange = NSRange(location: 0, length: storage.length)
    storage.beginEditing()
    storage.removeAttribute(.backgroundColor, range: fullRange)
    storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)
    for token in promptPlaceholders(in: editor.string) {
        let color: NSColor = token.isSupported ? .controlAccentColor : .systemRed
        storage.addAttributes([
            .foregroundColor: color,
            .backgroundColor: color.withAlphaComponent(0.10)
        ], range: token.range)
    }
    storage.endEditing()
    editor.typingAttributes = [.font: editor.font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.textColor]
}
