import MonitorUI
import OpenCineCameraControls
import OpenInstaViewCore
import XCTest

@testable import OpenInstaCine

/// The live screen moved to OpenCineCameraControls; this app keeps typed values. These pin each
/// against the app's original expression, frozen here, and the level read (10 Hz) for time.
@MainActor
final class LiveScreenParityTests: XCTestCase {
    func testZoomLabelsMatchTheAppForEveryFactor() {
        let model = AppModel()
        for tenth in 5...Int(CamFov.maxFactor * 10) {
            let factor = Double(tenth) / 10
            XCTAssertEqual(
                CamFov.displayLabel(factor: factor, ceiling: model.zoomCeiling),
                CamFov.displayLabel(factor: factor, ceiling: model.session.zoomCeiling), "\(factor)")
        }
    }

    func testHostValuesMatchTheApp() {
        let model = AppModel()
        XCTAssertEqual(model.liveCapabilities, OsmoMonitorPresentation.capabilities(model.session))
        XCTAssertEqual(model.liveZoomCaption, OsmoMonitorPresentation.zoomCaption(model.session))
        XCTAssertEqual(model.livePictureEV?(), model.pictureEV)
        #if targetEnvironment(simulator)
            XCTAssertEqual(model.simulatorLiveColorMode, !MonitorUIReview.isActive && SimulatorLiveFeed.isConfigured ? .iLog : nil)
        #endif
    }

    func testLevelReadMatchesTheAppAndIsNotSlower() {
        let model = AppModel()
        let session = model.session
        func shared(_ now: TimeInterval, _ flip: Bool) -> MonitorLevelDisplay {
            model.liveLevelDisplay(session.liveLevelReading.mode(now: now, viewFlip: flip))
        }
        func frozen(_ now: TimeInterval, _ flip: Bool) -> MonitorLevelDisplay {
            LevelAssist.display(session.levelReading.mode(now: now, viewFlip: flip))
        }
        for flip in [false, true] {
            XCTAssertEqual(shared(0, flip), frozen(0, flip))
            XCTAssertEqual(shared(1_000, flip), frozen(1_000, flip))
        }
        func best(_ body: () -> Void) -> Double {
            (0..<5).map { _ in
                let start = ProcessInfo.processInfo.systemUptime
                body()
                return ProcessInfo.processInfo.systemUptime - start
            }.min()!
        }
        let iterations = 20_000
        var sink = 0
        let old = best { for i in 0..<iterations { if frozen(Double(i), false) == .unavailable { sink &+= 1 } } }
        let new = best { for i in 0..<iterations { if shared(Double(i), false) == .unavailable { sink &+= 1 } } }
        XCTAssertGreaterThanOrEqual(sink, 0)
        XCTAssertLessThanOrEqual(new, old * 1.5 + 0.002, "shared \(new * 1_000) ms vs app \(old * 1_000) ms")
    }
}
