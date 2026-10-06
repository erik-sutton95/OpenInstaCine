import MonitorPresentation
import OpenCineAppKit
import OpenCineCore
import XCTest

@testable import OpenInstaCine

/// The cameras and pair pages in the words main showed (its `OsmoCameraPageAdapter`): the four
/// Luna pages, the pre-check, the nearby card, and a Bluetooth failure with main's action.
@MainActor
final class CameraPagePresentationTests: XCTestCase {
    func testThePairWizardKeepsTheLunaPagesAndPreCheck() {
        let model = AppModel()
        let page = CamerasMapping.wizard(model.cameras, model.pairingWizard(stillLooking: false))
        XCTAssertEqual(
            page.steps.map(\.title),
            ["Find your camera", "Approve on the camera", "Join camera Wi-Fi", "Open video link"])
        XCTAssertEqual(
            page.body,
            "Turn the Luna on and keep this iPhone nearby. It shows up by the last characters of its serial number.")
        XCTAssertEqual(page.instructions.first?.lines, ["Before pairing, force quit the Insta360 app."])
        let looking = model.pairingWizard(stillLooking: true)
        XCTAssertEqual(
            looking.choosing?.lines,
            [
                "Force quit the Insta360 app on every phone near the camera. Make sure the camera is on and activated, then move closer."
            ])
        XCTAssertEqual(looking.approveLines, ["Look for the connection request", "Tap Allow on the camera screen"])
        XCTAssertEqual(
            looking.joinLines,
            ["Leave the camera on. It brings up its own 5 GHz Wi-Fi", "Close the Insta360 app on other phones so the camera is free"])
        XCTAssertEqual(looking.label, "Scanning for camera…")
    }

    func testBluetoothOffAsksToTryAgainAndAPermissionOpensSettings() {
        let model = AppModel()
        model.discoveryFailure = ConnectionFailure(
            reason: .radioOff(.bluetooth), title: "Couldn’t connect over Camera Wi-Fi",
            message: "Bluetooth is off. Turn it on in Control Center or Settings, then try again.", actions: [.retry],
            code: "test.bluetooth.off")
        var page = CamerasMapping.wizard(model.cameras, model.pairingWizard(stillLooking: false))
        XCTAssertEqual(page.error, "Bluetooth is off. Turn it on in Control Center or Settings, then try again.")
        XCTAssertEqual(page.primaryAction, "Try again")
        XCTAssertTrue(page.instructions.isEmpty)
        model.discoveryFailure?.actions = [.openSettings, .retry]
        page = CamerasMapping.wizard(model.cameras, model.pairingWizard(stillLooking: false))
        XCTAssertEqual(page.primaryAction, "Open Settings")
    }

    func testANearbyLunaReadsAsMain() {
        let camera = NearbyCamera(id: "n1", name: "Luna Ultra 1A2B", model: "Luna Ultra", routes: [.cameraAccessPoint])
        XCTAssertEqual(
            AppModel.nearbyCard(camera),
            NearbyCardCopy(name: "Luna Ultra 1A2B", subtitle: "Insta360 · nearby", status: "Needs approval on the camera"))
    }
}
