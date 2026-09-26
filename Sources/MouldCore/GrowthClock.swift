import Foundation

/// Accumulates "time spent at the screen". It only runs while the user is actually there,
/// can be sped up for demos, and never jumps forward by huge amounts (e.g. after sleep).
public struct GrowthClock: Sendable, Equatable {
    public private(set) var elapsed: TimeInterval = 0
    public var speed: Double
    /// Beyond this much input inactivity the user is considered away and growth pauses.
    public var idleThreshold: TimeInterval
    /// Largest real-time step accepted at once; protects against wall-clock jumps.
    public var maxStep: TimeInterval

    public init(speed: Double = 1, idleThreshold: TimeInterval = 5 * 60, maxStep: TimeInterval = 5) {
        self.speed = speed
        self.idleThreshold = idleThreshold
        self.maxStep = maxStep
    }

    public mutating func advance(by dt: TimeInterval, idleFor idle: TimeInterval) {
        guard dt > 0, idle < idleThreshold else { return }
        elapsed += min(dt, maxStep) * speed
    }

    public mutating func reset() {
        elapsed = 0
    }

    public func progress(duration: TimeInterval) -> Double {
        min(1, max(0, elapsed / duration))
    }
}

/// The "wipe it off" animation that runs when the user hits the hotkey.
public struct WipeAnimation: Sendable, Equatable {
    public let duration: TimeInterval
    public private(set) var elapsed: TimeInterval = 0

    public init(duration: TimeInterval = 1.6) {
        self.duration = duration
    }

    public mutating func advance(by dt: TimeInterval) {
        elapsed = min(duration, elapsed + max(0, dt))
    }

    public var isFinished: Bool { elapsed >= duration }

    /// Eased 0...1 position of the wipe front.
    public var progress: Double {
        let t = min(1, elapsed / duration)
        return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }
}

extension GrowthClock {
    /// Jump straight to a moment (used by `--minutes` for demos).
    public mutating func jump(to seconds: TimeInterval) {
        elapsed = max(0, seconds)
    }
}

/// How often to redraw. Growth at real speed is ~0.2 pt/s, so a frame every two seconds moves
/// edges by well under a pixel and keeps the GPU (and battery) out of it. Wipes get the full frame rate.
public enum RedrawPolicy {
    public static let wipeInterval: TimeInterval = 1.0 / 60
    public static let slowest: TimeInterval = 2
    public static let fastest: TimeInterval = 1.0 / 30

    public static func interval(speed: Double, wiping: Bool) -> TimeInterval {
        if wiping { return wipeInterval }
        return min(slowest, max(fastest, slowest / max(speed, 0.001)))
    }
}
