import Foundation

/// Jittered exponential backoff for reconnect retries. OpenZCine `ReconnectBackoff`.
public struct ReconnectBackoff: Sendable, Equatable {
    public var baseSeconds: Double
    public var maxSeconds: Double
    public var multiplier: Double
    public var jitterFraction: Double

    public init(
        baseSeconds: Double = 0.5,
        maxSeconds: Double = 30,
        multiplier: Double = 2,
        jitterFraction: Double = 0.3
    ) {
        self.baseSeconds = baseSeconds
        self.maxSeconds = maxSeconds
        self.multiplier = multiplier
        self.jitterFraction = jitterFraction
    }

    public func delaySeconds(forAttempt attempt: Int, jitter: Double) -> Double {
        let exponent = Double(max(0, attempt))
        let capped = min(maxSeconds, baseSeconds * pow(multiplier, exponent))
        let clampedJitter = min(1, max(0, jitter))
        let signedSpread = (clampedJitter * 2 - 1) * jitterFraction
        let jittered = capped * (1 + signedSpread)
        return min(maxSeconds, max(0, jittered))
    }
}
