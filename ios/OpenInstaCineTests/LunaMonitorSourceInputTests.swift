import OpenCineMedia
import OpenInstaViewCore
import XCTest

@testable import OpenInstaCine

final class LunaMonitorSourceInputTests: XCTestCase {
    func testActualLunaConfigurationHasOnlyIlogFactsAndKeepsReportedTransfer() {
        let configuration = LiveAssistEngine.configuration
        XCTAssertTrue(configuration.clipProfile.calibrations.isEmpty)
        XCTAssertNil(configuration.clipProfile.defaultISO)
        XCTAssertEqual(Set(configuration.lookCurves.keys), [.ilog])
        XCTAssertEqual(configuration.inferTransfer?(16, 247, .rec709), .rec709)
        XCTAssertNil(OpenInstaViewCore.ScopeExposureCeiling().resolvedISO())
    }
}
