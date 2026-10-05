import Testing

@testable import OpenPocketViewCore

@Suite struct ExposureMeterReadingTests {

    @Test func cameraMeterUsesTheExistingHudCadence() {
        let previous = CameraStatus()
        var next = previous
        next.meteredEv = EvComp(thirds: 2)
        #expect(!LiveChromeThrottle.shouldNotify(previous: previous, next: next, elapsed: 0.19))
        #expect(LiveChromeThrottle.shouldNotify(previous: previous, next: next, elapsed: 0.2))
    }
}
