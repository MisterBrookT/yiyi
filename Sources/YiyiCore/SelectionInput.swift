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
    sentinelText: String?,
    snapshotText: String?,
    observedText: String?,
    accessibilitySelectedText: String?,
    clipboardText: String?
) -> CaptureDecision {
    let observed = observedText.flatMap(nonEmpty)
    let axSelection = accessibilitySelectedText.flatMap(nonEmpty)
    let contradicted = axSelection != nil && observed != axSelection
    let isConfirmedSelection = trusted
        && observed != nil
        && observed != sentinelText
        && observed != snapshotText
        && !contradicted

    if isConfirmedSelection, let observed {
        return CaptureDecision(text: observed, source: .selection)
    }

    let clipboard = clipboardText.flatMap(nonEmpty)
    let hint = trusted ? nil : accessibilityClipboardHint
    guard let clipboard else { return CaptureDecision(text: nil, source: .empty, hint: hint) }
    return CaptureDecision(text: clipboard, source: .clipboard, hint: hint)
}

private func nonEmpty(_ text: String) -> String? {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
}
