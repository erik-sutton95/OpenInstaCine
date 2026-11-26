import Insta360Protocol
import MonitorPresentation
import OpenInstaViewCore
import XCTest

@testable import OpenInstaCine

/// The zoom a connected Luna body offers (Kotlin `LunaBodyZoomTest`): a Luna Pro has no 3x
/// telephoto, so it gets no 3x chip, no tele mark and no TELE caption, and stops at 4x; the Luna
/// Ultra keeps exactly what it had. The connected camera takes the body's name.
@MainActor
final class LunaBodyZoomTests: XCTestCase {
    private func session() -> OpenInstaCine.CameraSession {
        OpenInstaCine.CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder())
    }

    func testTheLunaUltraKeepsItsTelephotoZoom() {
        let unknown = session()
        let ultra = session()
        ultra.identify(.ultra)
        for session in [unknown, ultra] {
            XCTAssertEqual(session.zoomStops, [1, 2, 3, 6, 15])
            XCTAssertEqual(session.zoomMax, 15)
            XCTAssertEqual(session.opticalZoomStops, [1, 3])
            XCTAssertEqual(MonitorZoomCaption.label(factor: 3, opticalStops: session.opticalZoomStops), "TELE")
        }
    }

    func testTheLunaProHidesTelephotoOnlyZoom() {
        let pro = session()
        pro.identify(.pro)
        XCTAssertEqual(pro.zoomStops, [1, 2, 4], "no 3x lens chip")
        XCTAssertEqual(pro.zoomMax, 4)
        XCTAssertEqual(pro.zoomCeiling, 4)
        XCTAssertEqual(pro.opticalZoomStops, [1], "no tele mark on the zoom dial")
        XCTAssertEqual(OsmoMonitorPresentation.zoomTapStops(pro).singleTap, [1, 2, 4])
        for factor in [2.0, 3, 4] {
            XCTAssertNotEqual(MonitorZoomCaption.label(factor: factor, opticalStops: pro.opticalZoomStops), "TELE")
        }
        // Back to an Ultra on the next connection: its telephoto zoom returns.
        pro.identify(.ultra)
        XCTAssertEqual(pro.zoomStops, [1, 2, 3, 6, 15])
        XCTAssertEqual(pro.opticalZoomStops, [1, 3])
    }

    #if targetEnvironment(simulator)
        func testTheConnectedCameraTakesTheBodysName() {
            let session = session()
            session.reviewLive(
                camera: FoundCamera(id: UUID(), name: "Luna 1A2B", model: LunaShellMapping.cameraModel, modelId: nil),
                status: CameraStatus())
            XCTAssertEqual(session.connectedCamera?.model.name, "Luna", "a sighting does not say which body it is")
            session.identify(.pro)
            XCTAssertEqual(session.connectedCamera?.model.name, "Luna Pro")
            XCTAssertEqual(session.connectedCamera?.model.captureProfile?.zoom?.stops, [1, 2, 4])
            session.identify(.ultra)
            XCTAssertEqual(session.connectedCamera?.model.name, "Luna Ultra")
        }
    #endif
}
