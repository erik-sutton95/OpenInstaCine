import OpenCineCore
import OpenInstaViewCore
import XCTest

@testable import OpenInstaCine

#if targetEnvironment(simulator)
/// SIMULATED review reports exercise the production common battery decoder.
@MainActor final class MonitorReviewBatteryTests: XCTestCase {
    func testReviewPreservesKnownZeroAndAbsentBattery() {
        for percent in [68, 0, -1] {
            var status = CameraStatus()
            status.iso = 400
            status.shutterDenom = 50
            status.whiteBalanceKelvin = 5600
            status.batteryPercent = percent
            status.charging = true
            let session = MonitorUIReview.simulatedSession(status: status)
            defer { session.close(.requested) }
            if percent >= 0 {
                XCTAssertEqual(session.current.power.batteryReading, .fraction(Double(percent) / 100))
                XCTAssertEqual(session.current.power.externalPower.value, true)
            } else {
                XCTAssertNil(session.current.power.batteryReading)
                XCTAssertNil(session.current.power.externalPower.value)
            }
            XCTAssertNil(session.current.power.charging.value)
            XCTAssertNil(session.current.power.exhausted.value)
        }
    }
}
#endif
