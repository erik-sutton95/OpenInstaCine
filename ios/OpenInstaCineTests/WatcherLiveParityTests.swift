import MetalKit
import MonitorUI
import OpenCineAppKitApple
import OpenCineApple
import OpenCineCameraControls
import OpenCineRelay
import OpenInstaViewCore
import XCTest

@testable import OpenInstaCine

/// The watcher screen and the live assist source moved to OpenCineCameraControls. What stayed
/// app-specific is a typed brand value; these pin it and the shared source against the app's
/// original expressions, frozen here.
@MainActor
final class WatcherLiveParityTests: XCTestCase {
    func testLookProfileIsTheLunaProfileForEveryRelayedBody() {
        for nano in [nil, false, true] as [Bool?] {
            for name in [nil, "", "X5", "Ace Pro 2"] as [String?] {
                let state = WatcherRelayState(cameraModel: name, isNano: nano)
                XCTAssertEqual(AppModel.watcherBrand.lookProfile(state), LunaShellMapping.lookProfile)
            }
        }
    }

    func testZoomChoiceTitlesMatchTheApp() {
        for choices in [[100], [100, 200, 300], [100, 150, 200, 400], [50, 100, 1_200], [100, 1_000]] {
            XCTAssertEqual(
                WatcherLiveView.zoomChoiceTitles(choices),
                choices.map { raw in
                    CamFov.displayLabel(
                        factor: Double(raw) / 100, ceiling: Double(choices.max() ?? 1_200) / 100)
                }, "\(choices)")
        }
    }

    func testLiveAssistSourceReadsTheMonitoredSourceAsTheAppDid() {
        let model = AppModel()
        let source = model.liveAssistSource
        let frozenTransfer = model.monitorTransfer ?? model.monitorColorMode.map(MonitorTransfer.init) ?? .rec709
        XCTAssertEqual(source.readTransfer(), frozenTransfer)
        for transfer in [MonitorTransfer.rec709, .ilog] {
            XCTAssertEqual(
                source.readClipByte(transfer),
                model.monitorSamples.exposureCeiling.clipByte(transfer: transfer))
        }
    }

    func testScopeDisplayMatchesTheAppPanel() {
        defer { LiveHDRDisplay.app.setEnabled(false) }
        for hdr in [false, true] {
            LiveHDRDisplay.app.setEnabled(hdr)
            let options = InstaLivePicture.scopeDisplay(MTKView())
            XCTAssertEqual(options.hdr, LiveHDRDisplay.app.isEnabled)
            XCTAssertEqual(options.gain, LiveHDRDisplay.app.presentGain)
        }
    }
}
