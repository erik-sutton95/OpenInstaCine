import OpenCineMedia
import OpenInstaViewCore
import XCTest

@testable import OpenInstaCine

final class LunaMonitorSourceInputTests: XCTestCase {
    func testActualLunaConfigurationHasOnlyIlogFactsAndKeepsReportedTransfer() {
        let configuration = LiveAssistEngine.configuration
        XCTAssertEqual(Set(configuration.clipProfile.calibrations.keys), [.ilog])
        XCTAssertEqual(configuration.clipProfile.defaultISO, 100)
        XCTAssertEqual(configuration.clipProfile.unreportedISO, 100)
        XCTAssertEqual(Set(configuration.lookCurves.keys), [.ilog])
        XCTAssertEqual(configuration.inferTransfer?(16, 247, .rec709), .rec709)
        XCTAssertEqual(OpenInstaViewCore.ScopeExposureCeiling().resolvedISO(), 100)
    }
}
