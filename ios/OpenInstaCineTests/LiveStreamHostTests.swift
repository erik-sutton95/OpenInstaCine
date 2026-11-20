import OpenCineCore
import OpenCineStreaming
import XCTest

@testable import OpenInstaCine

/// Live streaming's host values: no route without this phone's own live picture, the preview
/// feed's shape, and only the app's root model streams. SIMULATED session (no camera).
@MainActor
final class LiveStreamHostTests: XCTestCase {
    func testNoLivePictureMeansNoRouteAndNoSource() {
        let session = CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder())
        let model = AppModel(session: session)
        XCTAssertNil(model.liveStreamRoute, "Go live says to connect a camera")
        XCTAssertNil(model.liveStreamSource)
        session.phase = .live
        XCTAssertEqual(model.liveStreamSource, StreamSourceFormat(width: 1280, height: 720, frameRate: Rational(25, 1)))
        XCTAssertNil(model.liveStreamRoute, "A live phase without a connected camera has no route")
    }

    func testATilesBorrowedModelNeverStreams() {
        let session = CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder())
        XCTAssertNil(AppModel(session: session).liveStream)
    }
}
