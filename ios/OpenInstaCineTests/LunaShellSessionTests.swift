import Insta360Apple
import Insta360AppleTestSupport
import Insta360Protocol
import OpenCineCameraControls
import OpenCineCore
import OpenCineHostedTestSupport
import OpenCineMedia
import OpenInstaViewCore
import XCTest

@testable import OpenInstaCine

// LunaCameraSession tests and FakeLuna live in OpenCineInsta360 (Insta360AppleTests,
// Insta360AppleTestSupport). These drive the app shell over a FakeLuna session.

@MainActor
final class CoreRecordControlTests: XCTestCase {
    private func waitUntil(_ condition: @MainActor @Sendable () -> Bool) async throws {
        let held = await HostedCondition.wait(until: condition)
        XCTAssertTrue(held, "timed out")
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
    func testActualLunaConnectionPortProducesSessionScopedMediaService() async throws {
        let shell = OpenInstaCine.CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder())
        let first = shell.openSession()
        let media = try XCTUnwrap(shell.mediaService(for: first.id))
        XCTAssertEqual(media.sessionID, first.id)
        XCTAssertNil(shell.mediaService(for: CameraSessionID()))
        do { _ = try await media.openBrowse(); XCTFail("An unconnected source cannot browse") }
        catch let error as MediaServiceError { XCTAssertEqual(error, .unavailable) }
        let next = shell.openSession()
        XCTAssertNotEqual(next.id, first.id)
        XCTAssertNil(shell.mediaService(for: first.id))
        do { _ = try await media.openBrowse(); XCTFail("A replaced source cannot browse") }
        catch let error as MediaServiceError { XCTAssertEqual(error, .unavailable) }
        next.close(.requested)
    }
    private func waitUntil(_ condition: @MainActor @Sendable () -> Bool) async throws {
        let held = await HostedCondition.wait(until: condition)
        XCTAssertTrue(held, "timed out")
    }

    private static let otherProfile = CameraLabelProfile(
        shootingModeLabels: [.hyperLapse: "Hyper"], colorModeLabels: [.normal: "Neutral"],
        gimbalModeLabels: [.fpv: "FPV-X"], media: MediaHTTP.Route(host: "10.0.0.9", addressing: .storageQuery))

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
    /// (clip delete, clip star, internet hop). Settings keeps its routing rows before connection;
    /// the counter capability stays unknown until the common session declares it.
    func testMonitorLaysOutTheLunaProjection() {
        let shell = OpenInstaCine.CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder())
        var base = MonitorLayoutCapabilities()
        (base.clipDelete, base.clipStar, base.requiresInternetHop) = (true, true, true)
        var unconnected = base
        (unconnected.gimbal, unconnected.zoom, unconnected.focus, unconnected.headTracking, unconnected.timecode) =
            (true, true, true, true, false)
        XCTAssertEqual(OsmoMonitorPresentation.capabilities(shell), unconnected)
        let camera = FakeLuna()
        let core = camera.connectedSession()
        shell.control.bind(core)
        var luna = base
        // Luna lays out its one control model: zoom from its declared stops before the live range.
        (luna.gimbal, luna.zoom, luna.headTracking, luna.focus, luna.timecode) = (true, true, true, true, true)
        XCTAssertEqual(OsmoMonitorPresentation.capabilities(shell), luna, "declared zoom before the live range")
        core.configureLens(zoomDomain: 1...4)
        luna.zoom = true
        XCTAssertEqual(OsmoMonitorPresentation.capabilities(shell), luna, "no audio levels, no iris")
    }
}

/// A5-07: the host-emulated shutter angle follows a format change only for an established manual
/// video exposure (Core `ShutterAngle`); an unknown exposure never gets a hidden shutter SET.
@MainActor
final class ShutterAngleFormatRematchTests: XCTestCase {
    private func waitUntil(_ condition: @MainActor @Sendable () -> Bool) async throws {
        let held = await HostedCondition.wait(until: condition)
        XCTAssertTrue(held, "timed out")
    }

    private static func isShutterWrite(_ request: LunaRequest) -> Bool {
        request.command == .setPhotographyOptions
            && (try? LunaPhotographySettings(response: request.body))?.types.contains(21) == true
    }

    func testAnglePreferenceDescribesEmulationAndUsesReportedCadence() throws {
        let previous = OperatorPrefs.shutterUsesAngle
        defer { OperatorPrefs.shutterUsesAngle = previous }
        OperatorPrefs.shutterUsesAngle = false
        let camera = FakeLuna()
        camera.program = LunaExposureProgram.manual.rawValue
        camera.iso = 400
        camera.shutterSeconds = 1.0 / 50
        let luna = camera.connectedSession()
        let raw = try XCTUnwrap(LunaVideoResolution.rawValue(width: 3840, height: 2160, framesPerSecond: 25))
        let body = try ProtoMessage.blob(field: 1, value: ProtoMessage.varint(31))
            + ProtoMessage.blob(field: 2, value: ProtoMessage.integer(field: 31, value: raw))
            + ProtoMessage.integer(field: 3, value: UInt64(LunaFunctionMode.normalVideo.rawValue))
        luna.ingest(settings: try LunaPhotographySettings(response: body))
        let facade = OpenInstaCine.CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder())
        facade.lunaSessionOverride = luna
        let model = AppModel(session: facade)
        model.shutterUsesAngle = true
        XCTAssertEqual(luna.current.capabilities.descriptors[.shutter]?.semantics.implementation, .emulated)
        XCTAssertEqual(luna.current.value(of: .shutter).value, .shutter(.angle(180)))
        XCTAssertEqual(luna.current.value(of: .shutter).origin, .protocolDerived)
        model.shutterUsesAngle = false
        XCTAssertEqual(luna.current.capabilities.descriptors[.shutter]?.semantics.implementation, .native)
        XCTAssertEqual(luna.current.value(of: .shutter).value, .shutter(.duration(Rational(1, 50))))
    }

    private static func exposures(_ camera: FakeLuna) -> [LunaExposure] {
        camera.sent.filter(isShutterWrite).compactMap { try? LunaPhotographySettings(response: $0.body).videoExposure }
    }

    /// A live Luna shell at 4K25 with Angle on (emulated in Core), bound to `luna`. The session
    /// carries the backend's admitted port: native format and colour picks are admitted writes,
    /// which a session without one refuses as expired before they reach the camera.
    private func angleShell(program: LunaExposureProgram, iso: UInt64) async throws
        -> (FakeLuna, OpenInstaCine.CameraSession, AppModel)
    {
        let camera = FakeLuna()
        camera.program = program.rawValue
        camera.iso = iso
        camera.shutterSeconds = 1.0 / 50
        let luna = camera.connectedSession(admittedSends: true)
        let raw = try XCTUnwrap(LunaVideoResolution.rawValue(width: 3840, height: 2160, framesPerSecond: 25))
        let body = try ProtoMessage.blob(field: 1, value: ProtoMessage.varint(31))
            + ProtoMessage.blob(field: 2, value: ProtoMessage.integer(field: 31, value: raw))
            + ProtoMessage.integer(field: 3, value: UInt64(LunaFunctionMode.normalVideo.rawValue))
        luna.ingest(settings: try LunaPhotographySettings(response: body))
        let shell = OpenInstaCine.CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder())
        shell.lunaSessionOverride = luna
        shell.phase = .live
        shell.control.bind(luna)
        let model = AppModel(session: shell)
        model.shutterUsesAngle = true
        try await waitUntil { shell.control.snapshot?.capabilities[.shutter]?.semantics.implementation == .emulated }
        var status = shell.status
        (status.shootingMode, status.fps, status.shutterDenom) = (Int(ShootingMode.video.rawValue), 25, 50)
        status.availableShutterDenoms = [8000, 1000, 500, 250, 125, 100, 60, 50, 25]
        shell.status = status
        shell.nativeRecordingFormat = LunaVideoResolution(rawValue: raw)
        return (camera, shell, model)
    }

    /// II-061: an Angle tab pick reaches the camera as its 1/N, with no "not applied" note.
    func testAnglePickSetsTheShutter() async throws {
        let (usesAngle, degrees) = (OperatorPrefs.shutterUsesAngle, OperatorPrefs.shutterAngleDegrees)
        defer { (OperatorPrefs.shutterUsesAngle, OperatorPrefs.shutterAngleDegrees) = (usesAngle, degrees) }
        let (camera, shell, model) = try await angleShell(program: .manual, iso: 400)
        model.commit(.shutterAngle(90), from: .sheet(nil))
        try await waitUntil { Self.exposures(camera).contains { abs($0.shutterSeconds - 1.0 / 100) < 1e-9 } }
        try await waitUntil { shell.control.pending[.shutter] == nil }
        XCTAssertNil(shell.controlNote)
        shell.control.unbind()
    }

    /// II-069 / II-070: Manual from Auto with Angle remembered sends a manual shutter.
    func testManualFromAutoInAngleModeSendsAShutter() async throws {
        let (usesAngle, degrees) = (OperatorPrefs.shutterUsesAngle, OperatorPrefs.shutterAngleDegrees)
        defer { (OperatorPrefs.shutterUsesAngle, OperatorPrefs.shutterAngleDegrees) = (usesAngle, degrees) }
        let (camera, shell, _) = try await angleShell(program: .automatic, iso: 400)
        shell.setExpoMode(.manual)
        try await waitUntil { Self.exposures(camera).contains { $0.shutterSeconds > 0 } }
        try await waitUntil { shell.control.pending[.shutter] == nil }
        XCTAssertNil(shell.controlNote)
        shell.control.unbind()
    }

    /// IA-116 twin: Auto ISO with a fixed shutter (shutter priority) reads Manual, not Auto.
    func testShutterPriorityReadsManualInAngleMode() async throws {
        let (usesAngle, degrees) = (OperatorPrefs.shutterUsesAngle, OperatorPrefs.shutterAngleDegrees)
        defer { (OperatorPrefs.shutterUsesAngle, OperatorPrefs.shutterAngleDegrees) = (usesAngle, degrees) }
        let (_, shell, _) = try await angleShell(program: .shutterPriority, iso: 0)
        try await waitUntil { shell.status.expoMode != nil }
        XCTAssertEqual(shell.status.expoMode, .manual)
        shell.control.unbind()
    }

    /// II-062: a native format change keeps 180 degrees for a fixed shutter (Manual and shutter priority).
    func testNativeFormatChangeKeepsTheAngle() async throws {
        let (usesAngle, degrees) = (OperatorPrefs.shutterUsesAngle, OperatorPrefs.shutterAngleDegrees)
        defer { (OperatorPrefs.shutterUsesAngle, OperatorPrefs.shutterAngleDegrees) = (usesAngle, degrees) }
        OperatorPrefs.shutterAngleDegrees = 180
        for (program, iso) in [(LunaExposureProgram.manual, UInt64(400)), (.shutterPriority, 0)] {
            let (camera, shell, _) = try await angleShell(program: program, iso: iso)
            let next = try XCTUnwrap(LunaVideoResolution.rawValue(width: 3840, height: 2160, framesPerSecond: 50)
                .flatMap(LunaVideoResolution.init(rawValue:)))
            shell.setNativeRecordingFormat(next)
            try await waitUntil { Self.exposures(camera).contains { abs($0.shutterSeconds - 1.0 / 100) < 1e-9 } }
            shell.control.unbind()
        }
    }

    /// Owner 2026-10-20 (Luna Ultra, Angle 180, shutter priority): changing the frame rate flashed
    /// a derived angle until the camera confirmed. The readout is sampled through the whole native
    /// sequence, in its worst order: tap (format pin), the camera's format readback beating the ack
    /// (the shell pin clears, the camera clamps its own speed to 1/125 at 120 fps), the ack and the
    /// re-sent 1/250, its confirmation. It never leaves 180 degrees.
    @MainActor private final class SequenceProbe {
        var gated = false
        var readouts: [String] = []
    }

    func testNativeFormatChangeHoldsTheAngleReadout() async throws {
        let (usesAngle, degrees) = (OperatorPrefs.shutterUsesAngle, OperatorPrefs.shutterAngleDegrees)
        defer { (OperatorPrefs.shutterUsesAngle, OperatorPrefs.shutterAngleDegrees) = (usesAngle, degrees) }
        OperatorPrefs.shutterAngleDegrees = 180
        let (camera, shell, model) = try await angleShell(program: .shutterPriority, iso: 0)
        let luna = try XCTUnwrap(shell.lunaSessionOverride)
        camera.reportsSinglePrecisionShutter = true
        let probe = SequenceProbe()
        func sample(_ step: String) { probe.readouts.append("\(step): \(model.shutterAngleReadout(selection: .pending).value)") }
        sample("before")
        let raw = try XCTUnwrap(LunaVideoResolution.rawValue(width: 3840, height: 2160, framesPerSecond: 120))
        let next = try XCTUnwrap(LunaVideoResolution(rawValue: raw))
        let cadence = try ProtoMessage.blob(field: 1, value: ProtoMessage.varint(31))
            + ProtoMessage.blob(field: 2, value: ProtoMessage.integer(field: 31, value: raw))
            + ProtoMessage.integer(field: 3, value: UInt64(LunaFunctionMode.normalVideo.rawValue))
        camera.beforeReply = { [weak shell] request in
            guard !probe.gated, let shell,
                (try? LunaPhotographySettings(response: request.body))?.types.contains(31) == true else { return }
            probe.gated = true
            sample("tap")
            // The camera's readback beats the ack: new rate, a speed it clamped itself, no shell pin.
            camera.shutterSeconds = 1.0 / 125
            luna.ingest(settings: try! LunaPhotographySettings(response: cadence))
            camera.reportSettings()
            shell.nativeFormatPin = nil
            try? await self.waitUntil {
                shell.control.snapshot?.value(of: .frameRate).value == .frameRate(Rational(120))
                    && shell.control.snapshot?.value(of: .shutter).value != .shutter(.angle(180))
            }
            sample("readback before ack")
        }
        shell.setNativeRecordingFormat(next)
        sample("after tap")
        try await waitUntil { probe.gated }
        try await waitUntil { Self.exposures(camera).contains { abs($0.shutterSeconds - 1.0 / 250) < 1e-9 } }
        sample("re-sent")
        try await waitUntil {
            guard shell.control.pending[.shutter] == nil,
                case .shutter(.angle(let angle))? = shell.control.snapshot?.value(of: .shutter).value else { return false }
            return abs(angle - 172.8) < 1e-6
        }
        sample("confirmed")
        XCTAssertEqual(probe.readouts.count, 6, "\(probe.readouts)")
        XCTAssertTrue(probe.readouts.allSatisfy { $0.hasSuffix(": 180°") }, "\(probe.readouts)")
        shell.control.unbind()
    }

    /// Behavior audit II-093: a native colour pick applies the preview colour science at once and a
    /// refusal restores it, as the pre-refactor `setColorMode` did.
    func testNativeColorAppliesThePreviewAtOnceAndARefusalRestoresIt() async throws {
        let (camera, shell, _) = try await angleShell(program: .manual, iso: 400)
        shell.status.colorMode = .normal
        shell.applyDecoderColorScience()
        let flat = LunaShellMapping.previewColorMode(recording: .iLog, recoveryOff: OperatorPrefs.lunaFlatPreview)
        shell.setNativeRecordingColor(.iLog)
        XCTAssertEqual(shell.status.colorMode, .iLog)
        XCTAssertEqual(shell.decoder.incomingColorMode, flat)
        try await waitUntil { camera.sent.contains { $0.command == .setPhotographyOptions
            && (try? LunaPhotographySettings(response: $0.body))?.types.contains(LunaPhotographyType.colorMode.rawValue) == true } }
        camera.refuses = true
        shell.setNativeRecordingColor(.standard)
        XCTAssertEqual(shell.status.colorMode, .normal)
        try await waitUntil { shell.controlNote != nil }
        XCTAssertEqual(shell.status.colorMode, .iLog, "a refused colour restores the previous preview")
        XCTAssertEqual(shell.decoder.incomingColorMode, flat)
        shell.control.unbind()
    }

    /// CodeRabbit #46: a format the camera refuses keeps the angle; no new 1/N is sent.
    func testRefusedNativeFormatSendsNoRematch() async throws {
        let (usesAngle, degrees) = (OperatorPrefs.shutterUsesAngle, OperatorPrefs.shutterAngleDegrees)
        defer { (OperatorPrefs.shutterUsesAngle, OperatorPrefs.shutterAngleDegrees) = (usesAngle, degrees) }
        OperatorPrefs.shutterAngleDegrees = 180
        let (camera, shell, _) = try await angleShell(program: .manual, iso: 400)
        camera.refuses = true
        let next = try XCTUnwrap(LunaVideoResolution.rawValue(width: 3840, height: 2160, framesPerSecond: 50)
            .flatMap(LunaVideoResolution.init(rawValue:)))
        shell.setNativeRecordingFormat(next)
        try await waitUntil { shell.controlNote != nil }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(camera.sent.contains(where: Self.isShutterWrite), "a refused format sends no shutter")
        shell.control.unbind()
    }

    func testFormatChangeWithUnknownExposureSendsNoShutter() async throws {
        let (usesAngle, degrees) = (OperatorPrefs.shutterUsesAngle, OperatorPrefs.shutterAngleDegrees)
        defer { (OperatorPrefs.shutterUsesAngle, OperatorPrefs.shutterAngleDegrees) = (usesAngle, degrees) }
        (OperatorPrefs.shutterUsesAngle, OperatorPrefs.shutterAngleDegrees) = (true, 180)
        let camera = FakeLuna()
        let luna = camera.connectedSession()
        let shell = OpenInstaCine.CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder())
        shell.lunaSessionOverride = luna
        shell.phase = .live
        shell.control.bind(luna)
        try await waitUntil { shell.control.snapshot != nil }
        let from = VideoFormat(resolution: .p4K, frameRate: .fps25)
        shell.formatTable = [from: 1, VideoFormat(resolution: .p4K, frameRate: .fps30): 2]
        var status = shell.status
        (status.videoFormat, status.videoResolution, status.fps) = (from, .p4K, 25)
        (status.expoMode, status.shutterDenom, status.availableShutterDenoms) = (nil, 50, [50, 60])
        shell.status = status

        shell.setVideoFormat(resolution: .p4K, frameRate: .fps30)
        try await waitUntil { camera.sent.contains { $0.command == .setPhotographyOptions } }
        // Negative window: no hidden shutter SET may follow within it.
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(camera.sent.contains(where: Self.isShutterWrite), "no hidden shutter SET while exposure is unknown")
        shell.control.unbind()
    }
}
