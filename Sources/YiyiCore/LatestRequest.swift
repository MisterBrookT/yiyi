import Foundation

/// A slow earlier request must never replace a newer result or clipboard value.
public struct LatestRequest: Sendable {
    private var current: UUID?
    public init() {}
    public mutating func begin() -> UUID {
        let token = UUID(); current = token; return token
    }
    public func isCurrent(_ token: UUID) -> Bool { current == token }
}
