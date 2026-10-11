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
        // Camera access points stay readable, other networks do not.
        XCTAssertEqual(host.redact("ssid=OsmoPocket3-A1B2"), "ssid=OsmoPocket3-A1B2")
        XCTAssertEqual(host.redact("ssid=CafeWiFi"), "ssid=<redacted>")
        XCTAssertTrue(AppDiagnostics.reporting.gate === AppDiagnostics.gate)
        XCTAssertTrue(AppDiagnostics.reporting.consent === AppDiagnostics.consent)
        XCTAssertTrue(AppDiagnostics.reporting.origin === AppDiagnostics.origin)
        XCTAssertEqual(ReliabilityReportingConsent.defaultsKey, "opc.reliabilityReporting.optIn")
    }
}
