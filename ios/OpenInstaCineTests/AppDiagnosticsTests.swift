import OpenCineAppKit
import SwiftUI
import UIKit
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

/// SIMULATED launch over the shipping app root. The clock never uses wall time; callbacks
/// adapt a temporary consent domain rather than changing the operator's saved choice.
@MainActor final class StartupCompositionTests: XCTestCase {
    @MainActor private final class Clock {
        var now: Duration = .zero
        var waiting: [(Duration, CheckedContinuation<Void, any Error>)] = []
        func sleep(_ duration: Duration) async throws {
            try await withCheckedThrowingContinuation { waiting.append((now + duration, $0)) }
        }
        func advance(_ duration: Duration) {
            now += duration
            let ready = waiting.filter { $0.0 <= now }
            waiting.removeAll { $0.0 <= now }
            for (_, continuation) in ready { continuation.resume() }
        }
        func release() {
            let old = waiting
            waiting = []
            for (_, continuation) in old { continuation.resume() }
        }
    }

    private func settle(_ host: UIHostingController<AnyView>, _ done: () -> Bool) async -> Bool {
        for _ in 0..<2_000 {
            host.view.layoutIfNeeded()
            if done() { return true }
            await Task.yield()
        }
        return done()
    }

    private func identifiers(_ object: NSObject, seen: inout Set<ObjectIdentifier>) -> Set<String> {
        guard seen.insert(ObjectIdentifier(object)).inserted else { return [] }
        var result = Set<String>()
        let getter = NSSelectorFromString("accessibilityIdentifier")
        if object.responds(to: getter),
            let value = object.perform(getter)?.takeUnretainedValue() as? String
        {
            result.insert(value)
        }
        for element in object.accessibilityElements as? [NSObject] ?? [] {
            result.formUnion(identifiers(element, seen: &seen))
        }
        let count = object.accessibilityElementCount()
        if count > 0 && count < 512 {
            for index in 0..<count {
                if let child = object.accessibilityElement(at: index) as? NSObject {
                    result.formUnion(identifiers(child, seen: &seen))
                }
            }
        }
        if let view = object as? UIView {
            for child in view.subviews { result.formUnion(identifiers(child, seen: &seen)) }
        }
        return result
    }

    func testActualRootRunsSharedLaunchAndConsentWithTheExistingHostActions() async throws {
        let clock = Clock()
        let domain = "startup.hosted.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let consent = ReliabilityReportingConsent(defaults: defaults)
        var ticks = 0
        var choices: [Bool] = []
        let startup = MonitorAppStartup(
            reports: .init(
                isAvailable: { true }, hasDecision: { consent.hasDecision },
                setConsent: {
                    choices.append($0)
                    consent.setOptedIn($0)
                }, tick: { ticks += 1 }),
            sleep: { try await clock.sleep($0) })
        let host = UIHostingController(
            rootView: AnyView(
                AppRoot(startup: startup).transaction { $0.disablesAnimations = true }))
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 874, height: 402)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        defer {
            startup.retire()
            clock.release()
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        let started = await settle(host) { clock.waiting.count == 2 }
        XCTAssertTrue(started, "Actual root must mount the shared startup task")
        var seen = Set<ObjectIdentifier>()
        XCTAssertTrue(identifiers(host.view, seen: &seen).contains("monitor-launch-splash"))
        clock.advance(.milliseconds(2_249))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(startup.consentOffer)
        clock.advance(.milliseconds(1))
        let offered = await settle(host) { startup.consentOffer != nil }
        XCTAssertTrue(offered, "Actual root must offer consent at the original fade start")
        let offer = try XCTUnwrap(startup.consentOffer)
        let presented = await settle(host) {
            guard let sheet = host.presentedViewController else { return false }
            var seen = Set<ObjectIdentifier>()
            return identifiers(sheet.view, seen: &seen).contains("reliability.consent.decline")
        }
        XCTAssertTrue(presented, "The actual root must present its existing consent sheet")
        offer.choose(false)
        let dismissing = await settle(host) {
            host.presentedViewController == nil
                || host.presentedViewController?.isBeingDismissed == true
        }
        XCTAssertTrue(
            dismissing, "The existing choice callback must dismiss the actual consent sheet")
        XCTAssertEqual(choices, [false])
        XCTAssertTrue(ReliabilityReportingConsent(defaults: defaults).hasDecision)
        XCTAssertFalse(consent.isOptedIn)
        host.rootView = AnyView(Color.clear)
        let retired = await settle(host) { startup.isRetired }
        XCTAssertTrue(retired, "Removing the actual root must retire its shared callbacks")
        let count = ticks
        clock.release()
        offer.choose(true)
        startup.sceneChanged()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(ticks, count)
        XCTAssertEqual(choices, [false])
    }
}

/// SIMULATED render baseline from the original Branding source captured before extraction.
/// The app's actual assets, font and backdrop render on both sides of the shared seam.
@MainActor final class StartupAppearanceTests: XCTestCase {
    func testSharedSplashMatchesOriginalRenderedBrandContentInEveryLayout() throws {
        for (size, compact) in [
            (CGSize(width: 874, height: 402), false),
            (CGSize(width: 402, height: 874), false),
            (CGSize(width: 300, height: 300), true),
            (CGSize(width: 402, height: 874), true),
        ] {
            let original = ImageRenderer(
                content: OriginalStartupSplash(compact: compact)
                    .frame(width: size.width, height: size.height).environment(\.colorScheme, .dark)
            )
            let shared = ImageRenderer(
                content: LaunchSplashContent(compact: compact)
                    .frame(width: size.width, height: size.height).environment(\.colorScheme, .dark)
            )
            original.scale = 1
            shared.scale = 1
            let before = try XCTUnwrap(original.uiImage)
            let after = try XCTUnwrap(shared.uiImage)
            let beforePixels = try XCTUnwrap(before.cgImage?.dataProvider?.data)
            let afterPixels = try XCTUnwrap(after.cgImage?.dataProvider?.data)
            XCTAssertEqual(before.size, after.size)
            XCTAssertTrue(
                (beforePixels as Data) == (afterPixels as Data),
                "Shared launch must preserve original pixels at \(size), compact=\(compact)")
            for (name, image) in [("original", before), ("shared", after)] {
                let attachment = XCTAttachment(image: image)
                attachment.name =
                    "launch-\(name)-\(Int(size.width))x\(Int(size.height))-compact-\(compact)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}

private struct OriginalStartupSplash: View {
    var compact: Bool = false

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width >= proxy.size.height
            let logoSize = min(proxy.size.width * (landscape ? 0.16 : 0.28), compact ? 72 : 96)

            ZStack {
                BrandBackdrop()

                if landscape {
                    HStack(spacing: max(32, proxy.size.width * 0.06)) {
                        OPCMonogramMark(size: logoSize)
                        OpenInstaCineWordmark(fontSize: compact ? 28 : 34)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, max(32, proxy.size.width * 0.08))
                } else {
                    VStack(spacing: 24) {
                        OPCMonogramMark(size: logoSize)
                        OpenInstaCineWordmark(fontSize: 30)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
