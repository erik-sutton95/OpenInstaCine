import Insta360Apple
import Insta360AppleTestSupport
import Insta360Protocol
import OpenCineCore
import OpenPocketViewCore
import XCTest

@testable import OpenInstaCine

// LunaCameraSession tests and FakeLuna live in OpenCineInsta360 (Insta360AppleTests,
// Insta360AppleTestSupport). These drive the app shell over a FakeLuna session.

@MainActor
final class CoreRecordControlTests: XCTestCase {
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "timed out")
    }

    func testRecordLampNeverTogglesBlind() async throws {
        let camera = FakeLuna()
        camera.captureState = nil
        let shell = OpenInstaCine.CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder())
        shell.control.bind(camera.connectedSession())
        try await waitUntil { shell.control.snapshot != nil }
        shell.toggleRecording()
        try await waitUntil { !shell.controlBusy }
        XCTAssertTrue(camera.sent.isEmpty, "unknown recording must not send a toggle")
        XCTAssertNil(shell.control.isRecording)
        XCTAssertNotNil(shell.controlNote)

        camera.captureState = 1
        camera.reportCapture()
        try await waitUntil { shell.control.isRecording == true }
        XCTAssertTrue(shell.status.isRecording)
        shell.toggleRecording()
        XCTAssertTrue(shell.controlBusy, "the lamp holds until the camera reports")
        try await waitUntil { !shell.controlBusy }
        XCTAssertEqual(camera.sent.map(\.command), [.stopCapture])
        XCTAssertEqual(shell.control.isRecording, false)
        XCTAssertFalse(shell.status.isRecording)

        // A confirmed start while the camera already records sends nothing.
        camera.captureState = 1
        camera.reportCapture()
        try await waitUntil { shell.control.isRecording == true }
        shell.setRecording(start: true)
        try await waitUntil { !shell.controlBusy }
        XCTAssertEqual(camera.sent.count, 1)
        shell.control.unbind()
    }
}

/// STATE-01 gate: two sessions in one process, each with its own backend, profile, zoom ceiling,
/// media host, EV calibration and Core session, never cross.
@MainActor
final class SessionIsolationTests: XCTestCase {
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "timed out")
    }

    private static let otherProfile = CameraProfile(
        shootingModeLabels: [.hyperLapse: "Hyper"], colorModeLabels: [.normal: "Neutral"],
        gimbalModeLabels: [.fpv: "FPV-X"], media: MediaHTTP.Route(host: "10.0.0.9", addressing: .djiV2))

    func testTwoSessionsRunConcurrentlyWithoutCrossover() async throws {
        let suite = "SessionIsolationTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let a = AppModel().session
        let b = OpenInstaCine.CameraSession(backend: AppModel.makeBackend(), profile: Self.otherProfile)
        a.pictureEV = PictureEVMeter(defaults: defaults)
        b.pictureEV = PictureEVMeter(defaults: defaults)
        b.zoomCeiling = 6

        // Callbacks: each backend reaches only its owner.
        XCTAssertFalse(a.backend === b.backend)
        a.activateBackend()
        b.activateBackend()
        let seen = MonitorCamera(id: UUID(), name: "Luna A", model: LunaProtocol.model, capabilities: [])
        a.backend.eventHandler?(.discovered(seen))
        XCTAssertEqual(a.found.map(\.id), [seen.id])
        XCTAssertTrue(b.found.isEmpty)

        // Labels, media host and zoom ceiling are the session's own.
        XCTAssertEqual(ShootingMode.hyperLapse.label(in: a.profile), "TimeShift")
        XCTAssertEqual(ShootingMode.hyperLapse.label(in: b.profile), "Hyper")
        XCTAssertEqual(ColorMode.normal.label(in: a.profile), "Standard")
        XCTAssertEqual(ColorMode(label: "Neutral", in: b.profile), .normal)
        XCTAssertNil(ColorMode(label: "Neutral", in: a.profile))
        let file = MediaFile(path: "/DCIM/Camera01/VID_0001.mp4", thumbPath: "/thumb.jpg")
        XCTAssertEqual(a.remotePlaybackURL(for: file)?.host, "192.168.42.1")
        XCTAssertTrue(a.remotePlaybackURL(for: file)?.path.hasPrefix("/DCIM/Camera01/") == true)
        XCTAssertEqual(b.remotePlaybackURL(for: file)?.host, "10.0.0.9")
        XCTAssertEqual(b.remotePlaybackURL(for: file)?.path, "/v2")
        XCTAssertEqual(a.zoomMax, 15)
        XCTAssertEqual(b.zoomMax, 6)
        a.zoomStop = 15
        b.zoomStop = 15
        XCTAssertEqual(a.zoomReadout, 15)
        XCTAssertEqual(b.zoomReadout, 6)
        XCTAssertEqual(CamFov.displayLabel(factor: a.zoomReadout, ceiling: a.zoomCeiling), "15×")
        XCTAssertEqual(CamFov.displayLabel(factor: 15), "12×", "the DJI default is unchanged")

        // EV calibration: A learns in auto; B (another camera, same transfer) keeps its own.
        let contextA = PictureEVContext(device: "A", transfer: .ilog, profile: "i-log", metering: "matrix")
        let contextB = PictureEVContext(device: "B", transfer: .ilog, profile: "i-log", metering: "matrix")
        var t = 0.0
        while t < 20 {
            t += 0.04
            _ = a.pictureEV.stops(picture: -0.5, context: contextA, evComp: 0, now: t)
            _ = b.pictureEV.stops(picture: -2.0, context: contextB, evComp: 0, now: t)
        }
        a.pictureEV.save()
        b.pictureEV.save()
        XCTAssertEqual(a.pictureEV.offset(for: contextA), -0.5, accuracy: 0.01)
        XCTAssertEqual(b.pictureEV.offset(for: contextB), -2.0, accuracy: 0.01)
        let stored = try XCTUnwrap(defaults.dictionary(forKey: PictureEVMeter.defaultsKey) as? [String: Double])
        XCTAssertEqual(try XCTUnwrap(stored[contextA.key]), -0.5, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(stored[contextB.key]), -2.0, accuracy: 0.01)

        // Commands and teardown: each Core session drives only its camera; closing A leaves B working.
        let cameraA = FakeLuna()
        let cameraB = FakeLuna()
        a.control.bind(cameraA.connectedSession())
        b.control.bind(cameraB.connectedSession())
        try await waitUntil { a.control.isRecording == false && b.control.isRecording == false }
        a.setRecording(start: true)
        b.setRecording(start: true)
        try await waitUntil { !a.controlBusy && !b.controlBusy }
        XCTAssertEqual(cameraA.sent.map(\.command), [.startCapture])
        XCTAssertEqual(cameraB.sent.map(\.command), [.startCapture])
        XCTAssertEqual(a.control.isRecording, true)
        XCTAssertEqual(b.control.isRecording, true)

        let closedA = try XCTUnwrap(cameraA.session)
        // The shell retires A's controls and closes its session; B is untouched.
        a.control.unbind()
        closedA.close(.requested)
        try await waitUntil { closedA.current.connection != .ready }
        b.setRecording(start: false)
        try await waitUntil { !b.controlBusy }
        XCTAssertEqual(cameraB.sent.map(\.command), [.startCapture, .stopCapture])
        XCTAssertEqual(b.control.isRecording, false)
        XCTAssertEqual(cameraA.sent.map(\.command), [.startCapture], "closing never sends a command")
        let shownB = try XCTUnwrap(cameraB.session).current
        XCTAssertEqual(shownB.connection, .ready)
        b.control.unbind()
    }

    func testALeaseNeverTakesTheOwnersCallbacks() {
        let owner = AppModel().session
        let lease = OpenInstaCine.CameraSession(
            backend: owner.backend, borrowing: HevcDecoder(), controlsOnly: true)
        owner.activateBackend()
        lease.startScan(reconnect: nil)
        lease.activateBackend()
        XCTAssertEqual(lease.phase, .idle, "a lease never scans or connects")
        let seen = MonitorCamera(id: UUID(), name: "Luna", model: LunaProtocol.model, capabilities: [])
        owner.backend.eventHandler?(.discovered(seen))
        XCTAssertEqual(owner.found.map(\.id), [seen.id])
        XCTAssertTrue(lease.found.isEmpty)
    }

    /// Plan 5.2: a picture-format change alone does not change control ownership.
    func testPictureOnlyReconfigurationKeepsTheControlEpoch() async throws {
        let camera = FakeLuna()
        camera.applyDelay = .milliseconds(150)
        let shell = OpenInstaCine.CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder())
        let core = camera.connectedSession()
        shell.control.bind(core)
        let epoch = core.current.epoch
        let command = CameraCommand(
            .set(.iso(.manual(800))), preconditions: CommandPreconditions(core.current))
        _ = await core.submit(command)
        // The stream restarts with a new format while the write settles.
        shell.decoder.reset()
        shell.decoder.onParameterSetsChanged?()
        XCTAssertEqual(core.current.epoch, epoch)
        let outcome = await core.outcome(of: command.operation)
        XCTAssertEqual(outcome?.stage, .confirmed)

        // A link re-establishment is a new epoch: a command admitted against the old one is stale.
        core.linkChanged(.streaming, serial: "LUNA-TEST")
        XCTAssertNotEqual(core.current.epoch, epoch)
        let stale = await core.submit(
            CameraCommand(.set(.iso(.manual(400))), preconditions: command.preconditions))
        XCTAssertEqual(stale.stage, .rejected(.staleEpoch))
        shell.control.unbind()
    }
}

@MainActor
final class LunaLayoutTests: XCTestCase {
    /// SHELL-01: the live monitor lays out what the Luna integration declares over the app base
    /// (clip delete, clip star, internet hop); with no camera nothing is declared.
    func testMonitorLaysOutTheLunaProjection() {
        let shell = OpenInstaCine.CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder())
        var base = MonitorLayoutCapabilities()
        (base.clipDelete, base.clipStar, base.requiresInternetHop) = (true, true, true)
        XCTAssertEqual(OsmoMonitorPresentation.capabilities(shell), base)
        let camera = FakeLuna()
        let core = camera.connectedSession()
        shell.control.bind(core)
        var luna = base
        (luna.gimbal, luna.headTracking, luna.focus, luna.timecode) = (true, true, true, true)
        XCTAssertEqual(OsmoMonitorPresentation.capabilities(shell), luna, "unconfigured lens range stays unknown")
        core.configureLens(zoomDomain: 1...4)
        luna.zoom = true
        XCTAssertEqual(OsmoMonitorPresentation.capabilities(shell), luna, "no audio levels, no iris")
    }
}
