import OpenInstaViewCore
import XCTest

@testable import OpenInstaCine

#if targetEnvironment(simulator)
/// SIMULATED review reports use the same common storage producer as the live surface.
@MainActor final class MonitorReviewStorageTests: XCTestCase {
    func testReviewPublishesExactBytesAndKnownZeroWithoutInventingUnknown() {
        for free in [102_400, 0, -1] {
            var status = CameraStatus()
            status.iso = 400
            status.shutterDenom = 50
            status.whiteBalanceKelvin = 5600
            status.storageFreeMb = free
            status.storageTotalMb = free >= 0 ? 131_072 : -1
            let session = MonitorUIReview.simulatedSession(status: status)
            defer { session.close(.requested) }
            if free >= 0 {
                XCTAssertEqual(session.current.storage.value?.first?.freeBytes.value,
                    UInt64(free) * 1_048_576)
                XCTAssertEqual(session.current.storage.value?.first?.totalBytes.value,
                    137_438_953_472)
            } else {
                XCTAssertNil(session.current.storage.value)
            }
        }
    }
}
#endif
