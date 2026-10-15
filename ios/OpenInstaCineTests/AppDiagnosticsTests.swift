import OpenCineAppKit
import XCTest

@testable import OpenInstaCine

/// The holder wires the host values this app shipped with before diagnostics moved to OpenCine.
final class AppDiagnosticsTests: XCTestCase {
    func testHolderWiresThisAppsNamesDestinationAndRedaction() {
        let host = AppDiagnostics.host
        XCTAssertEqual(host.product, "OpenInstaCine")
        XCTAssertEqual(host.listingName, "Field monitor")
        XCTAssertEqual(
            host.release(version: "0.1.0", build: "107"), "com.opencapture.openinstacine@0.1.0+107")
        XCTAssertEqual(host.supportEmail, "support@opencapture.org")
        // Tests run a development build: reinstalls must not read as watchdog kills.
        XCTAssertEqual(host.environment, "development")
        XCTAssertFalse(host.tracksWatchdogTerminations)
        XCTAssertEqual(AppDiagnostics.gate.cameraIPv4Prefix, "192.168.42.")
        // Luna keeps no network readable (A6-10): DJI-looking and ordinary SSIDs are both redacted.
        XCTAssertEqual(host.redact("ssid=OsmoPocket3-A1B2"), "ssid=<redacted>")
        XCTAssertEqual(host.redact("ssid=EdgeRouter-5G"), "ssid=<redacted>")
        XCTAssertEqual(host.redact("ssid=CafeWiFi"), "ssid=<redacted>")
        XCTAssertTrue(AppDiagnostics.reporting.gate === AppDiagnostics.gate)
        XCTAssertTrue(AppDiagnostics.reporting.consent === AppDiagnostics.consent)
        XCTAssertTrue(AppDiagnostics.reporting.origin === AppDiagnostics.origin)
        XCTAssertEqual(ReliabilityReportingConsent.defaultsKey, "opc.reliabilityReporting.optIn")
    }
}
