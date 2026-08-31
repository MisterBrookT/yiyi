import Foundation

public enum CaptureSource: String, Equatable, Sendable {
    case selection
    case clipboard
    case empty
}

public struct CaptureDecision: Equatable, Sendable {
    public let text: String?
    public let source: CaptureSource
    public let hint: String?

    public init(text: String?, source: CaptureSource, hint: String? = nil) {
        self.text = text
        self.source = source
        self.hint = hint
    }
}

public let accessibilityClipboardHint = "grant Accessibility or relaunch to read selection"

public func shouldSynthesizeSelection(trusted: Bool) -> Bool {
    trusted
}

public func chooseCaptureInput(
    trusted: Bool,
    changeCountAdvanced: Bool,
    capturedText: String?,
    clipboardText: String?
) -> CaptureDecision {
    if trusted, changeCountAdvanced, let capturedText, !capturedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return CaptureDecision(text: capturedText, source: .selection)
    }

    let clipboard = clipboardText.flatMap {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
    }
    let hint = trusted ? nil : accessibilityClipboardHint
    guard let clipboard else { return CaptureDecision(text: nil, source: .empty, hint: hint) }
    return CaptureDecision(text: clipboard, source: .clipboard, hint: hint)
}
