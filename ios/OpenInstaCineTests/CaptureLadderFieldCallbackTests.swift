import OpenCineAppKit
import OpenCineCameraControls
import OpenCineCameraVocabulary
import OpenCineCore
import OpenCineCoreTestSupport
import OpenCineHostedAccessibility
import SwiftUI
import UIKit
import XCTest

@testable import OpenInstaCine

/// SIMULATED camera traffic, production panel, native Kelvin action and the actual app hook.
@MainActor
final class CaptureLadderFieldCallbackTests: XCTestCase {
    func testNativeKelvinCommitClearsWhiteBalanceLockOnlyAfterAdmittedFieldInput() async throws {
        let runtimeReady = await HostedAccessibility.awaitRuntime()
        XCTAssertTrue(runtimeReady)
        let model = AppModel()
        var status = CameraStatus()
        status.expoMode = .manual
        status.iso = 200
        status.isoIndex = .iso200
        status.whiteBalance = .custom(kelvin: 4000, tint: 0)
        status.whiteBalanceKelvin = 4000
        status.whiteBalanceTint = 0
        model.session.status = status
        model.session.autoWhiteBalanceLock = AutoWhiteBalanceLock(kelvin: 4000)
        let camera = FakeCameraSession.lunaLike()
        await camera.cameraReportsStatus()
        model.control.bind(camera)
        let loaded = await waitUntil { model.control.captureField(.whiteBalance)?.isEditable == true }
        XCTAssertTrue(loaded)
        model.captureSheet = .wb
        let controller = UIHostingController(rootView: WhiteBalanceFieldPanel(model: model))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 420))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        defer {
            model.captureSheet = nil
            window.isHidden = true
            window.rootViewController = nil
            model.control.unbind()
            model.session.disconnect()
        }

        let kelvinTab = try await element(in: controller.view) { $0.accessibilityLabel == "Kelvin" }
        var wire = await camera.wire
        XCTAssertTrue(wire.isEmpty, "Mounting and initial selection cannot send")
        XCTAssertNotNil(model.session.autoWhiteBalanceLock)
        XCTAssertTrue(kelvinTab.accessibilityActivate(), "The actual panel tab must accept native input")
        let drum = try await element(in: controller.view) {
            $0.accessibilityLabel == "Value" && $0.accessibilityValue == "4000K"
        }
        wire = await camera.wire
        XCTAssertTrue(wire.isEmpty, "Opening the Kelvin tab cannot write or clear AWB lock")
        XCTAssertEqual(model.session.autoWhiteBalanceLock, AutoWhiteBalanceLock(kelvin: 4000))
        XCTAssertEqual(model.session.status, status)

        drum.accessibilityIncrement()
        let dispatched = await waitUntil { await camera.wire.count == 1 }
        XCTAssertTrue(dispatched, "The migrated field path must reach the admitted backend")
        wire = await camera.wire
        XCTAssertEqual(wire, ["set \(SettingValue.whiteBalance(.kelvin(4100)))"])
        XCTAssertNil(model.session.autoWhiteBalanceLock, "The real AppModel typed callback must clear AWB lock")
        var pendingPresentation = status
        pendingPresentation.whiteBalance = .custom(kelvin: 4100, tint: 0)
        pendingPresentation.whiteBalanceKelvin = 4100
        XCTAssertEqual(model.session.status, pendingPresentation, "The existing host still presents its pending request immediately")
        XCTAssertEqual(model.control.captureValue(.whiteBalance, selection: .reported), .whiteBalance(.kelvin(4000)))
        XCTAssertEqual(model.control.shown(.whiteBalance), .whiteBalance(.kelvin(4100)))
        model.captureSheet = nil
        await Task.yield()
        wire = await camera.wire
        XCTAssertEqual(wire.count, 1, "Dismissing the panel cannot replay a committed edit")
    }

    func testTypedNativeFieldCallbackClearsLockWithoutTheLegacyStatusProjection() async throws {
        let runtimeReady = await HostedAccessibility.awaitRuntime()
        XCTAssertTrue(runtimeReady)
        let model = AppModel()
        var status = CameraStatus()
        status.whiteBalance = .custom(kelvin: 4000, tint: 0)
        status.whiteBalanceKelvin = 4000
        status.whiteBalanceTint = 0
        model.session.status = status
        model.session.autoWhiteBalanceLock = AutoWhiteBalanceLock(kelvin: 4000)
        // A real independent control isolates the actual AppModel hook from the legacy status
        // projection, which would otherwise also clear the lock when it presents pending WB.
        let camera = FakeCameraSession.lunaLike()
        await camera.cameraReportsStatus()
        let control = MonitorControlModel()
        control.bind(camera)
        let loaded = await waitUntil { control.captureField(.whiteBalance)?.isEditable == true }
        XCTAssertTrue(loaded)
        let field = try XCTUnwrap(control.captureField(.whiteBalance))
        let choices = field.choices.filter { if case .whiteBalance(.kelvin) = $0.value { true } else { false } }
        var callbacks: [SettingValue] = []
        var labelWrites: [LadderWrite<SettingKey>] = []
        let ladder = LadderSheet(
            presentation: LadderSheetPresentation(title: "WB", subtitle: "Kelvin", tabs: [
                LadderTab(label: "Kelvin", key: SettingKey.whiteBalance,
                    ladder: CaptureLadder(current: field.label, values: choices.map(\.label)), applyOnActivate: false)
            ]), enabled: true, onWrite: { labelWrites.append($0) },
            control: control,
            host: LadderSheetHost(selectedTab: 0, selection: field.label,
                drum: .field(field, choices: choices), onSelectTab: { _ in }, onCommitted: { value in
                    callbacks.append(value)
                    model.captureDrumDidCommit(value)
                }))
        let controller = UIHostingController(rootView: ladder)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 420))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        defer {
            window.isHidden = true
            window.rootViewController = nil
            control.unbind()
            model.session.disconnect()
        }
        let drum = try await element(in: controller.view) {
            $0.accessibilityLabel == "Value" && $0.accessibilityValue == "4000K"
        }
        XCTAssertEqual(model.session.autoWhiteBalanceLock, AutoWhiteBalanceLock(kelvin: 4000))
        XCTAssertTrue(callbacks.isEmpty)
        let initialWire = await camera.wire
        XCTAssertTrue(initialWire.isEmpty)
        drum.accessibilityIncrement()
        let dispatched = await waitUntil { await camera.wire.count == 1 }
        XCTAssertTrue(dispatched)
        XCTAssertEqual(callbacks, [.whiteBalance(.kelvin(4100))])
        XCTAssertNil(model.session.autoWhiteBalanceLock, "Only the actual typed AppModel callback can clear this isolated host lock")
        XCTAssertEqual(model.session.status, status)
        XCTAssertNil(model.control.snapshot, "The app's status projection is not this test's command owner")
        XCTAssertTrue(labelWrites.isEmpty)
        let wire = await camera.wire
        XCTAssertEqual(wire, ["set \(SettingValue.whiteBalance(.kelvin(4100)))"])
        XCTAssertEqual(control.captureValue(.whiteBalance, selection: .reported), .whiteBalance(.kelvin(4000)))
    }

    private func element(in view: UIView, matching predicate: (NSObject) -> Bool) async throws -> NSObject {
        let published = await waitUntil {
            view.setNeedsLayout(); view.layoutIfNeeded()
            return HostedAccessibility.leaves(in: view).contains(where: predicate)
        }
        XCTAssertTrue(published)
        return try XCTUnwrap(HostedAccessibility.leaves(in: view).first(where: predicate),
            "The production capture panel must expose the actual native input element")
    }

    private func waitUntil(_ predicate: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if await predicate() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return await predicate()
    }
}

private struct WhiteBalanceFieldPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.captureSheet == .wb {
                CapturePickerPanel(sheet: .wb, isPresented: { model.captureSheet == .wb }) {
                    model.captureSheet = nil
                }
            }
        }
        .environment(model)
        .environment(\.scenePhase, .active)
        .preferredColorScheme(.dark)
    }
}
