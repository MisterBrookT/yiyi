public enum AccessibilityAdvice: Equatable, Sendable {
    case ok
    case promptOnce
    case staleGrant
    case awaitGrant
}

public func accessibilityAdvice(
    trusted: Bool,
    hasPrompted: Bool,
    grantedSignature: String?,
    currentSignature: String
) -> AccessibilityAdvice {
    if trusted { return .ok }
    if let grantedSignature, grantedSignature != currentSignature { return .staleGrant }
    if !hasPrompted { return .promptOnce }
    return .awaitGrant
}
