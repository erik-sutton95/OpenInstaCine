import Testing

@testable import OpenPocketViewCore

@Suite("ReconnectBackoff")
struct ReconnectBackoffTests {
    @Test func firstAttemptUsesBaseDelay() {
        let backoff = ReconnectBackoff(
            baseSeconds: 0.5, maxSeconds: 30, multiplier: 2, jitterFraction: 0.3)
        #expect(backoff.delaySeconds(forAttempt: 0, jitter: 0.5) == 0.5)
    }

    @Test func growsExponentially() {
        let backoff = ReconnectBackoff(
            baseSeconds: 0.5, maxSeconds: 30, multiplier: 2, jitterFraction: 0.3)
        #expect(backoff.delaySeconds(forAttempt: 1, jitter: 0.5) == 1.0)
        #expect(backoff.delaySeconds(forAttempt: 2, jitter: 0.5) == 2.0)
        #expect(backoff.delaySeconds(forAttempt: 3, jitter: 0.5) == 4.0)
    }

    @Test func clampsToMaximum() {
        let backoff = ReconnectBackoff(
            baseSeconds: 0.5, maxSeconds: 30, multiplier: 2, jitterFraction: 0.3)
        #expect(backoff.delaySeconds(forAttempt: 20, jitter: 0.5) == 30)
    }

    @Test func jitterSpreadsBelowAndAbove() {
        let backoff = ReconnectBackoff(
            baseSeconds: 0.5, maxSeconds: 30, multiplier: 2, jitterFraction: 0.3)
        #expect(abs(backoff.delaySeconds(forAttempt: 3, jitter: 0) - 2.8) < 1e-9)
        #expect(abs(backoff.delaySeconds(forAttempt: 3, jitter: 1) - 5.2) < 1e-9)
    }

    @Test func jitterNeverExceedsMaximum() {
        let backoff = ReconnectBackoff(
            baseSeconds: 0.5, maxSeconds: 30, multiplier: 2, jitterFraction: 0.3)
        #expect(backoff.delaySeconds(forAttempt: 20, jitter: 1) == 30)
    }

    @Test func negativeAttemptTreatedAsFirst() {
        let backoff = ReconnectBackoff(
            baseSeconds: 0.5, maxSeconds: 30, multiplier: 2, jitterFraction: 0.3)
        #expect(backoff.delaySeconds(forAttempt: -3, jitter: 0.5) == 0.5)
    }

    @Test func jitterSampleIsClampedToUnitRange() {
        let backoff = ReconnectBackoff(
            baseSeconds: 1, maxSeconds: 30, multiplier: 2, jitterFraction: 0.5)
        #expect(
            backoff.delaySeconds(forAttempt: 0, jitter: -1)
                == backoff.delaySeconds(forAttempt: 0, jitter: 0))
        #expect(
            backoff.delaySeconds(forAttempt: 0, jitter: 2)
                == backoff.delaySeconds(forAttempt: 0, jitter: 1))
    }
}
