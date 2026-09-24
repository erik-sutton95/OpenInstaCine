import XCTest

@testable import OpenInstaCine

@MainActor
final class MonitorMediaReviewTests: XCTestCase {
    func testOrdinaryCacheRemainsInCameraApplicationSupportDirectory() throws {
        #if DEBUG && targetEnvironment(simulator)
            guard !MonitorMediaReview.isActive else {
                throw XCTSkip("This assertion requires an ordinary app test process")
            }
        #endif
        let root = CameraMedia().cacheRoot(cameraID: "cache-isolation-test")
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        XCTAssertEqual(
            root,
            applicationSupport.appendingPathComponent(
                "OpenInstaCine/media/cache-isolation-test", isDirectory: true))
        XCTAssertFalse(root.path.contains("OpenInstaCine-UI-Review"))
    }
}
