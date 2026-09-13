import Foundation

public struct PointerTriggerConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var commandIndex: Int

    public init(enabled: Bool = false, commandIndex: Int = 0) {
        self.enabled = enabled
        self.commandIndex = commandIndex
    }

    private enum CodingKeys: String, CodingKey { case enabled, commandIndex }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        commandIndex = try values.decodeIfPresent(Int.self, forKey: .commandIndex) ?? 0
    }
}

public struct PointerGestureEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case primaryDown, moved, primaryUp, cancel }
    public let kind: Kind
    public let timestamp: TimeInterval
    public let x: Double
    public let y: Double
    public let modifierHeld: Bool

    public init(kind: Kind, timestamp: TimeInterval, x: Double, y: Double, modifierHeld: Bool) {
        self.kind = kind
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.modifierHeld = modifierHeld
    }
}

/// Recognizes one deliberate Option-primary-button hold while leaving event delivery to the caller.
public struct PointerGestureRecognizer: Sendable {
    public static let minimumDuration: TimeInterval = 0.45
    public static let maximumTravel = 8.0

    private var enabled = false
    private var start: PointerGestureEvent?
    private var cancelledUntilRelease = false

    public init(enabled: Bool = false) { self.enabled = enabled }

    public mutating func configure(enabled: Bool) {
        self.enabled = enabled
        start = nil
        cancelledUntilRelease = false
    }

    /// Returns true once, on release, when the complete gesture qualifies.
    public mutating func consume(_ event: PointerGestureEvent) -> Bool {
        guard enabled else { return false }
        switch event.kind {
        case .primaryDown:
            guard !cancelledUntilRelease else { return false }
            guard event.modifierHeld else { cancel(); return false }
            start = event
        case .moved:
            guard let start else { return false }
            guard event.modifierHeld, distance(from: start, to: event) <= Self.maximumTravel else { cancel(); return false }
        case .cancel:
            if start != nil || cancelledUntilRelease { cancel() }
        case .primaryUp:
            defer { start = nil; cancelledUntilRelease = false }
            guard !cancelledUntilRelease, let start, event.modifierHeld,
                  distance(from: start, to: event) <= Self.maximumTravel,
                  event.timestamp - start.timestamp >= Self.minimumDuration else { return false }
            return true
        }
        return false
    }

    private mutating func cancel() {
        start = nil
        cancelledUntilRelease = true
    }

    private func distance(from start: PointerGestureEvent, to end: PointerGestureEvent) -> Double {
        hypot(end.x - start.x, end.y - start.y)
    }
}
