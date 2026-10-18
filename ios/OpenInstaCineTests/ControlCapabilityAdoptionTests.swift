import Insta360Apple
import Insta360AppleTestSupport
import OpenCineCameraControls
import OpenCineCameraVocabulary
import OpenCineCore
import OpenInstaViewCore
import XCTest

@testable import OpenInstaCine

/// What Insta offers, read from the one control model the Luna integration provides (the app
/// sets no capability literal). Pins today's capture sheet gates before and after connection.
@MainActor
final class ControlCapabilityAdoptionTests: XCTestCase {
    /// Today's gates: focus modes and face metering, no aperture, no AUDIO tile, no native ISO.
    private func assertTodaysGates(_ model: AppModel, _ label: String) {
        let gates = model.captureCapabilities
        XCTAssertTrue(gates.focusMode, label)
        XCTAssertFalse(gates.aperture, label)
        XCTAssertFalse(gates.audio, label)
        XCTAssertTrue(gates.faceMetering, label)
        XCTAssertFalse(gates.nativeIsoHop, label)
        XCTAssertFalse(gates.isoLimit, label)
        XCTAssertEqual(gates, CaptureSheetCapabilities(controls: model.controlCapabilities), label)
    }

    func testBeforeConnectionTheProfileDecides() {
        let model = AppModel(session: OpenInstaCine.CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder()))
        assertTodaysGates(model, "before connection")
        let session = model.session
        XCTAssertTrue(session.hasGimbal && session.supportsZoom && session.supportsTapFocus)
        XCTAssertFalse(session.reportsMeteredEV)
    }

    func testTheConnectedSessionProvidesTheModel() {
        let luna = FakeLuna().connectedSession()
        let facade = OpenInstaCine.CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder())
        facade.lunaSessionOverride = luna
        let model = AppModel(session: facade)
        assertTodaysGates(model, "connected")
        let controls = model.controlCapabilities
        XCTAssertEqual(controls, luna.controlCapabilities(codecColor: model.recordingCodecColor))
        XCTAssertEqual(controls.iris.support, .unsupported)
        XCTAssertEqual(controls.audio.support, .unsupported)
        XCTAssertEqual(controls.zoom.offer?.stops, [1, 2, 3, 6, 15])
    }

    func testBackendInputsRestrictConnectedControlsWithoutChangingPreConnectionProfile() {
        let camera = FakeLuna()
        var declarations: CameraCapabilities? = []
        let luna = camera.connectedSession(backendCapabilities: { declarations })
        let facade = OpenInstaCine.CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder())
        facade.lunaSessionOverride = luna
        let model = AppModel(session: facade)
        XCTAssertEqual(model.controlCapabilities.focus.support, .unsupported)
        XCTAssertFalse(facade.supportsFocusMode || facade.supportsTapFocus || facade.supportsZoom
            || facade.hasGimbal || facade.supportsFaceMetering)
        XCTAssertFalse(model.captureCapabilities.focusMode || model.captureCapabilities.faceMetering)
        declarations = [.focus, .zoom, .gimbal, .exposure]
        XCTAssertTrue(facade.supportsFocusMode && facade.supportsTapFocus && facade.supportsZoom
            && facade.hasGimbal && facade.supportsFaceMetering)
        facade.lunaSessionOverride = nil
        XCTAssertTrue(facade.supportsFocusMode && facade.supportsZoom && facade.hasGimbal,
            "a disconnected known model returns to the agreed static profile")
    }
}
