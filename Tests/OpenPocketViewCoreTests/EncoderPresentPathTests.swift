import Testing

@testable import OpenPocketViewCore

// Parameter-set policy is tested in OpenCineCore (OpenCineMediaTests). These cover the DJI
// live-view enable and its watchdog coupling.
@Suite struct EncoderPresentPathTests {

    /// OpenCineMedia keeps the freeze threshold as its own constant; it must stay the watchdog stall.
    @Test func freezeThresholdMatchesWatchdogStall() {
        #expect(FeedPresentPolicy.freezeThreshold == FeedWatchdog.stallThreshold)
    }
}
