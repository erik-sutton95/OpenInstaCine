import OpenPocketViewCore
import XCTest

@testable import OpenInstaCine

@MainActor
final class SessionRecoveryChromeTests: XCTestCase {
    func testOperatorExitClearsHeldMonitor() {
        let model = AppModel()
        XCTAssertFalse(model.session.holdsMonitor)
        model.shell.present(ChromeEditorReturnTests.camera(model))
        model.session.holdsMonitor = true
        model.session.phase = .failed("link dropped")
        model.noteLinkPhase()
        XCTAssertTrue(model.isLive, "A held monitor stays up while recovering")
        model.session.sessionRecovery = .waitingForOperator(attemptsMade: 8)
        model.exitMonitorToOperatorMenu()
        XCTAssertFalse(model.isLive)
        XCTAssertFalse(model.session.holdsMonitor)
        XCTAssertEqual(model.session.sessionRecovery, .idle)
    }

    /// Outside recovery, the app's own link giving up closes the monitor, as leaving live did.
    func testAFailedLinkOutsideRecoveryClosesTheMonitor() {
        let model = AppModel()
        model.shell.present(ChromeEditorReturnTests.camera(model))
        model.session.phase = .failed("Turn on Bluetooth")
        model.noteLinkPhase()
        XCTAssertFalse(model.isLive)
        XCTAssertNotEqual(model.shell.route, .monitor)
    }
}
