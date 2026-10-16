import OpenCineHostedAccessibility
import OpenCineHostedTestSupport
import OpenCineMedia
import SwiftUI
import XCTest

@testable import OpenInstaCine

/// What VoiceOver reaches on the live screen, read from the hosting view's accessibility
/// elements. XCUITest also inventories hidden controls, so it cannot show this.
@MainActor
final class LiveChromeAccessibilityTests: XCTestCase {
    private static let chrome: Set<String> = [
        "monitor.system.lock", "monitor.system.settings", "monitor.system.media",
        "monitor.system.record", "monitor.system.display", "monitor.system.zoom",
        "monitor.capture.iso", "monitor.capture.shutter",
    ]

    func testControlsOutOfSightStayOutOfTheAccessibilityTree() async throws {
        setenv("OPV_UI_REVIEW_SCREEN", "live", 1)
        defer { unsetenv("OPV_UI_REVIEW_SCREEN") }
        let model = AppModel()
        model.prepareStartup()
        // A window outside the app's scene reports no active phase; the zoom dial (like the
        // app's scene) only takes input, and AX, while active.
        let host = UIHostingController(
            rootView: LiveViewScreen().environment(model).environment(\.scenePhase, .active))
        host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        defer {
            window.isHidden = true
            window.rootViewController = nil
            model.session.disconnect()
        }

        let live = try await exposed(host.view) { Self.chrome.isSubset(of: $0) && $0.contains("monitor.assists.expand") }
        XCTAssertTrue(Self.chrome.isSubset(of: live), "Live: \(live.sorted())")
        // The palette handle is its own element (its glyph hides itself). Under the zoom dial
        // the palette stays reachable, dimmed, as on main.
        XCTAssertTrue(live.contains("monitor.assists.expand"), "Live: \(live.sorted())")

        // An open picker hides the zoom chip beneath it; the chip hides itself. (The readout
        // opens through its own gesture, so the test sets the state a tap sets.)
        model.captureSheet = .iso
        let picker = try await exposed(host.view) { $0.contains("monitor.capture.close") && !$0.contains("monitor.system.zoom") }
        XCTAssertTrue(picker.contains("monitor.capture.close"), "Picker: \(picker.sorted())")
        XCTAssertFalse(picker.contains("monitor.system.zoom"), "Picker: \(picker.sorted())")
        model.captureSheet = nil
        try await settle(host.view)

        // The zoom dial: the dimmed chrome beneath it is out of reach.
        let zoom = try element("monitor.system.zoom", in: host.view)
        let continuous = try XCTUnwrap(
            zoom.accessibilityCustomActions?.first { $0.name == "Continuous zoom" })
        XCTAssertTrue(continuous.actionHandler?(continuous) ?? false)
        let dial = try await exposed(host.view) { $0.contains("monitor.zoom.dial") && $0.isDisjoint(with: Self.chrome) }
        XCTAssertTrue(dial.contains("monitor.zoom.dial"), "Dial: \(dial.sorted())")
        XCTAssertTrue(dial.isDisjoint(with: Self.chrome), "Dial: \(dial.sorted())")
        XCTAssertFalse(dial.contains { $0.hasPrefix("monitor.telemetry.") }, "Dial: \(dial.sorted())")
        let close = try XCTUnwrap(HostedAccessibility.reachable(in: host.view).first { $0.accessibilityLabel == "Close zoom dial" })
        XCTAssertTrue(close.accessibilityActivate())
        try await settle(host.view)

        // A covering page.
        model.shell.open(.settings)
        let covered = try await exposed(host.view) { !$0.isEmpty && $0.isDisjoint(with: live) }
        XCTAssertTrue(covered.isDisjoint(with: live), "Covered: \(covered.sorted())")
    }

    /// A1-06: Luna reports no metered EV. The meter reads the live picture, marked as an
    /// estimate, instead of standing unavailable while Settings says it meters the picture.
    func testTheEVMeterReadsThePictureWhenTheCameraMetersNone() async throws {
        setenv("OPV_UI_REVIEW_SCREEN", "live", 1)
        defer { unsetenv("OPV_UI_REVIEW_SCREEN") }
        let model = AppModel()
        model.prepareStartup()
        XCTAssertNil(model.session.status.meteredEv, "the camera meters nothing")
        let suite = "LiveChromeAccessibilityTests.pictureEV"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        model.session.pictureEV = PictureEVMeter(defaults: defaults)
        let wasOn = model.assist.evMeter
        model.assist.evMeter = true
        let host = UIHostingController(
            rootView: LiveViewScreen().environment(model).environment(\.scenePhase, .active))
        host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        defer {
            window.isHidden = true
            window.rootViewController = nil
            model.session.disconnect()
            model.assist.evMeter = wasOn
        }
        try await settle(host.view)

        // A SIMULATED picture whose luma samples all sit at one code.
        var luma = Array(repeating: 0, count: 256)
        luma[118] = 1_000
        let samples = ScopeSamples(
            histogramLuma: luma, histogramRed: luma, histogramGreen: luma, histogramBlue: luma, points: [])
        let source = model.frameSamples.openSource(.live)
        defer { model.frameSamples.closeSource(source) }
        model.frameSamples.publish(
            source, source: nil, transfer: .rec709,
            bundle: ScopeAssistBundle(samples: samples, transfer: .rec709))
        try await settle(host.view)

        // The established exclusion: a host with no accessibility tree cannot walk it.
        try XCTSkipIf(
            HostedAccessibility.reachable(in: host.view).isEmpty && !HostedAccessibility.enableRuntime(),
            "No accessibility tree: enable app accessibility")
        let meter = try element("monitor.ev.meter", in: host.view)
        let value = meter.accessibilityValue ?? ""
        XCTAssertTrue(value.hasPrefix("Estimated from picture"), value)
    }

    func testNativeMeteringReadoutReachesTheSharedLiveSurface() async throws {
        setenv("OPV_UI_REVIEW_SCREEN", "live", 1)
        defer { unsetenv("OPV_UI_REVIEW_SCREEN") }
        let model = AppModel()
        model.prepareStartup()
        let host = UIHostingController(rootView: LiveViewScreen().environment(model).environment(\.scenePhase, .active))
        host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
        defer { window.isHidden = true; window.rootViewController = nil; model.session.disconnect() }
        let cases: [(Bool?, String)] = [(false, "Matrix"), (true, "Face Priority"), (nil, "Unknown")]
        for (face, label) in cases {
            model.session.faceMetering = face
            try await settle(host.view)
            let meter = try element("monitor.capture.metering", in: host.view)
            XCTAssertEqual(meter.accessibilityValue, label)
        }
    }

    private func settle(_ view: UIView) async throws {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        view.layoutIfNeeded()
    }

    /// The identifiers VoiceOver reaches once `ready` holds for them: a render that is slow
    /// under load is never read half built. The caller's assertions then state what must hold.
    private func exposed(_ view: UIView, when ready: (Set<String>) -> Bool) async throws -> Set<String> {
        var ids = Set<String>()
        _ = await HostedCondition.wait {
            view.setNeedsLayout()
            view.layoutIfNeeded()
            ids = Set(HostedAccessibility.reachable(in: view).compactMap(Self.identifier))
            return ready(ids)
        }
        // The shared walk turns the accessibility runtime on wherever it can (a simulator), so
        // only a host where it cannot (a device without assistive access) may skip.
        try XCTSkipIf(ids.isEmpty && !HostedAccessibility.enableRuntime(), "No accessibility tree: enable app accessibility")
        return ids
    }

    private func element(_ id: String, in view: UIView) throws -> NSObject {
        try XCTUnwrap(HostedAccessibility.reachable(in: view).first { Self.identifier($0) == id }, id)
    }

    /// The `monitor.` identifiers VoiceOver reaches; containers count too, since Record and the
    /// zoom dial carry their identifiers on one.
    private static func identifier(_ object: NSObject) -> String? {
        HostedAccessibility.identifier(object).flatMap { $0.hasPrefix("monitor.") ? $0 : nil }
    }
}
