import XCTest

@testable import OpenInstaCine

/// The debug stress seam records a phase token and does not pick a camera.
/// Luna is never a Pocket 4 Pro, so `live` and `none` are the only stored values.
final class FeedStressReconnectTests: XCTestCase {
    func testReconnectRecordStaysLiveOrNone() {
        XCTAssertEqual(FeedStressAutomation.reconnectRecord(phaseIsLive: true), "live")
        XCTAssertEqual(FeedStressAutomation.reconnectRecord(phaseIsLive: false), "none")
    }
}
