public enum AccessibilityAdvice: Equatable, Sendable {
    case ok
    case promptOnce
    case repairStaleGrant
    case awaitGrant
}

public func accessibilityAdvice(
    trusted: Bool,
    hasPrompted: Bool,
    repairAttempted: Bool,
    grantedSignature: String?,
    currentSignature: String
) -> AccessibilityAdvice {
    if trusted { return .ok }
    if repairAttempted { return .awaitGrant }
    if hasPrompted || grantedSignature != nil { return .repairStaleGrant }
    return .promptOnce
}
