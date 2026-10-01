import Insta360Apple
import Insta360Protocol
import MonitorContracts
import OpenCineCore
import OpenPocketViewCore
import XCTest

@testable import OpenInstaCine

/// A Luna camera behind the session's link: it applies the real SET bodies the session builds
/// and answers readbacks in the real reply encodings.
@MainActor
private final class FakeLuna {
    var program: UInt64 = 0
    var iso: UInt64 = 0
    var shutterSeconds = 0.0
    var kelvin: UInt64 = 5600
    var colorMode: UInt64?
    /// Capture state (cmd 15); nil sends no reply at all.
    var captureState: UInt64? = 0
    /// The camera acknowledges SETs and record commands but stores nothing.
    var ignoresWrites = false
    /// A stored value changes this long after its SET is acknowledged.
    var applyDelay: Duration = .zero
    var silent = false
    private(set) var sent: [LunaRequest] = []
    private var lastApply: Task<Void, Never>?
    weak var session: LunaCameraSession?

    /// Confirmations return as soon as a readback matches, so only failure tests pass a short
    /// settle; the long default absorbs main-thread stalls while the host app launches.
    func makeSession(settle: Duration = .seconds(5)) -> LunaCameraSession {
        let session = LunaCameraSession(
            send: { [unowned self] in try await self.receive($0) },
            functionMode: { LunaFunctionMode.normalVideo.rawValue },
            readSettings: { [unowned self] in self.reportSettings() },
            readCapture: { [unowned self] in self.reportCapture() },
            timing: .init(
                settle: [.iso: settle, .shutter: settle, .whiteBalance: settle, .recording: settle],
                readbackInterval: .milliseconds(40)))
        self.session = session
        return session
    }

    /// A live session that has heard every report once.
    func connectedSession(settle: Duration = .seconds(5)) -> LunaCameraSession {
        let session = makeSession(settle: settle)
        session.linkChanged(.streaming, serial: "LUNA-TEST")
        reportDevice()
        reportSettings()
        reportCapture()
        return session
    }

    private func receive(_ request: LunaRequest) async throws -> Data {
        sent.append(request)
        guard !ignoresWrites else { return Data() }
        if applyDelay == .zero {
            apply(request)
        } else {
            // One control socket: the camera applies SETs in the order they arrived.
            let (delay, previous) = (applyDelay, lastApply)
            lastApply = Task { [weak self] in
                await previous?.value
                try? await Task.sleep(for: delay)
                self?.apply(request)
            }
        }
        return Data()
    }

    private func apply(_ request: LunaRequest) {
        switch request.command {
        case .setPhotographyOptions:
            let set = try! LunaPhotographySettings(response: request.body)
            if set.types.contains(21), let exposure = set.videoExposure {
                (program, iso, shutterSeconds) = (exposure.program, exposure.iso, exposure.shutterSeconds)
            }
            if set.types.contains(39) { kelvin = set.whiteBalanceKelvin ?? 0 }
        case .startCapture: captureState = 1
        case .stopCapture: captureState = 0
        default: break
        }
    }

    func reportSettings() {
        guard !silent else { return }
        var types = [21, 39]
        var exposure = try! ProtoMessage.integer(field: 1, value: program)
            + ProtoMessage.integer(field: 2, value: iso)
        if shutterSeconds > 0 { exposure += try! ProtoMessage.double(field: 3, value: shutterSeconds) }
        var nested = try! ProtoMessage.blob(field: 21, value: exposure)
            + ProtoMessage.integer(field: 39, value: kelvin)
        if let colorMode {
            types.append(35)
            nested += try! ProtoMessage.integer(field: 35, value: colorMode)
        }
        let packed = types.reduce(into: Data()) { $0 += ProtoMessage.varint(UInt64($1)) }
        let body = try! ProtoMessage.blob(field: 1, value: packed)
            + ProtoMessage.blob(field: 2, value: nested)
            + ProtoMessage.integer(field: 3, value: UInt64(LunaFunctionMode.normalVideo.rawValue))
        session?.ingest(settings: try! LunaPhotographySettings(response: body))
    }

    func reportCapture() {
        guard !silent, let captureState else { return }
        let body = try! ProtoMessage.blob(
            field: 1, value: try! ProtoMessage.integer(field: 1, value: captureState))
        session?.ingest(capture: try! LunaCaptureStatus(captureStatusResponse: body))
    }

    /// Video mode, no battery or storage fields.
    func reportDevice() {
        let nested = try! ProtoMessage.integer(field: 40, value: 100)
            + ProtoMessage.integer(field: 41, value: 0)
        session?.ingest(device: try! LunaDeviceStatus(response: ProtoMessage.blob(field: 2, value: nested)))
    }
}

@MainActor
final class LunaCameraSessionTests: XCTestCase {
    private func submit(
        _ intent: CameraCommandIntent, to session: LunaCameraSession
    ) async -> (submitted: CommandReceipt, outcome: CommandReceipt) {
        let command = CameraCommand(intent, preconditions: CommandPreconditions(session.current))
        let submitted = await session.submit(command)
        let outcome = await session.outcome(of: command.operation) ?? submitted
        return (submitted, outcome)
    }

    /// The old hole: `LunaCameraBackend` advertised recording, exposure and white balance but
    /// never implemented `apply`. Every writable capability the session describes must reach
    /// the camera and confirm; a descriptor without an implementation fails here.
    func testEveryAdvertisedWritableCapabilityReachesTheCamera() async {
        let camera = FakeLuna()
        let session = camera.connectedSession()
        let described = session.current.capabilities.descriptors.values.filter {
            $0.access == .readWrite
        }
        XCTAssertTrue(
            Set(described.map(\.key)).isSuperset(of: [.iso, .shutter, .whiteBalance, .recording]),
            "the CORE-02 slice must be advertised")
        for descriptor in described {
            XCTAssertEqual(descriptor.availability, .available, "\(descriptor.key)")
            let intent: CameraCommandIntent
            if descriptor.key == .recording {
                intent = .startRecording
            } else {
                let reported = session.current.value(of: descriptor.key).value
                guard let value = descriptor.domain?.choices.last(where: { $0 != reported }) else {
                    XCTFail("\(descriptor.key) has no value to write")
                    continue
                }
                intent = .set(value)
            }
            let before = camera.sent.count
            let (_, outcome) = await submit(intent, to: session)
            XCTAssertEqual(outcome.stage, .confirmed, "\(descriptor.key): \(outcome.stage)")
            XCTAssertEqual(camera.sent.count, before + 1, "\(descriptor.key) never reached the camera")
        }
    }

    func testAcceptedWriteThatDoesNotStickIsNotApplied() async {
        let camera = FakeLuna()
        let session = camera.connectedSession(settle: .milliseconds(600))
        camera.ignoresWrites = true
        let (submitted, outcome) = await submit(.set(.iso(.manual(800))), to: session)
        XCTAssertEqual(submitted.stage, .awaitingObservation, "acknowledged is not confirmed")
        XCTAssertEqual(outcome.stage, .failed(.notApplied))
        XCTAssertEqual(session.current.value(of: .iso).value, .iso(.auto), "reported stays reported")
    }

    func testSlowSettleStaysPendingAndConfirmsFromReadback() async {
        let camera = FakeLuna()
        let session = camera.connectedSession()
        camera.applyDelay = .milliseconds(300)
        let command = CameraCommand(
            .set(.whiteBalance(.kelvin(3200))), preconditions: CommandPreconditions(session.current))
        let submitted = await session.submit(command)
        XCTAssertEqual(submitted.stage, .awaitingObservation)
        XCTAssertEqual(
            session.current.value(of: .whiteBalance).value, .whiteBalance(.kelvin(5600)),
            "a request is never written into the reported snapshot")
        let outcome = await session.outcome(of: command.operation)
        XCTAssertEqual(outcome?.stage, .confirmed)
        XCTAssertEqual(session.current.value(of: .whiteBalance).value, .whiteBalance(.kelvin(3200)))
        XCTAssertEqual(session.current.value(of: .whiteBalance).origin, .cameraReported)
    }

    func testNoReadbackTimesOut() async {
        let camera = FakeLuna()
        let session = camera.connectedSession(settle: .milliseconds(600))
        camera.silent = true
        let (_, outcome) = await submit(.set(.whiteBalance(.auto)), to: session)
        XCTAssertEqual(outcome.stage, .timedOut)
    }

    /// A 500 reply (`LunaCameraBackend.send` throws `cameraRejectedRequest`) is a refusal.
    func testCameraRefusalIsARejection() async {
        let refusing = LunaCameraSession(
            send: { _ in throw LunaProtocolError.cameraRejectedRequest },
            functionMode: { LunaFunctionMode.normalVideo.rawValue }, readSettings: {},
            readCapture: {})
        refusing.linkChanged(.streaming, serial: nil)
        let (_, outcome) = await submit(.set(.whiteBalance(.auto)), to: refusing)
        XCTAssertEqual(outcome.stage, .rejected(.cameraRefused))
        XCTAssertEqual(refusing.current.connection, .ready, "a refusal is not a lost link")
    }

    func testUnknownStaysUnknown() {
        let camera = FakeLuna()
        camera.captureState = nil
        let session = camera.makeSession()
        session.linkChanged(.streaming, serial: nil)
        camera.reportDevice()
        XCTAssertNil(session.current.recording.value, "no capture report: unknown, not idle")
        XCTAssertNil(session.current.power.battery.value, "no battery report: unknown, not empty")
        XCTAssertNil(session.current.storage.value, "no storage report: unknown, not none")
        XCTAssertNil(session.current.device, "no serial: no invented identity")
        XCTAssertNil(session.current.value(of: .iso).value)
        // A photo capture state says nothing about video recording.
        camera.captureState = 4
        camera.reportCapture()
        XCTAssertNil(session.current.recording.value)
        camera.captureState = 1
        camera.reportCapture()
        XCTAssertEqual(session.current.recording.value, .recording)
        XCTAssertEqual(session.current.recording.origin, .cameraReported)
        camera.captureState = 4
        camera.reportCapture()
        XCTAssertNil(session.current.recording.value, "an unreadable state does not keep a stale one")
    }

    func testRecordingIsUnavailableUntilTheModeIsKnownAndISOUntilExposureIsKnown() async {
        let camera = FakeLuna()
        let session = camera.makeSession()
        session.linkChanged(.streaming, serial: nil)
        let (_, record) = await submit(.startRecording, to: session)
        XCTAssertEqual(record.stage, .rejected(.unavailable(.notReady)))
        let (_, iso) = await submit(.set(.iso(.manual(400))), to: session)
        XCTAssertEqual(iso.stage, .rejected(.unavailable(.notReady)))
    }

    func testExplicitStartWhileRecordingSendsNothing() async {
        let camera = FakeLuna()
        camera.captureState = 1
        let session = camera.connectedSession()
        let (_, start) = await submit(.startRecording, to: session)
        XCTAssertEqual(start.stage, .confirmed)
        XCTAssertTrue(camera.sent.isEmpty, "a start while recording must not reach the camera")
        camera.captureState = 0
        camera.reportCapture()
        let (_, stop) = await submit(.stopRecording, to: session)
        XCTAssertEqual(stop.stage, .confirmed)
        XCTAssertTrue(camera.sent.isEmpty, "a stop while idle must not reach the camera")
    }

    func testRecordingIsReportedOnlyByTheCamera() async {
        let camera = FakeLuna()
        let session = camera.connectedSession()
        camera.applyDelay = .milliseconds(150)
        let command = CameraCommand(.startRecording, preconditions: CommandPreconditions(session.current))
        let submitted = await session.submit(command)
        XCTAssertEqual(submitted.stage, .awaitingObservation)
        XCTAssertEqual(session.current.recording.value, .idle, "ACK is not a recording report")
        let outcome = await session.outcome(of: command.operation)
        XCTAssertEqual(outcome?.stage, .confirmed)
        XCTAssertEqual(session.current.recording.value, .recording)
        XCTAssertEqual(camera.sent.map(\.command), [.startCapture])
    }

    /// ISO and shutter share one Luna message: an ISO write keeps a still-pending shutter.
    func testExposureWriteCarriesThePendingShutter() async throws {
        let camera = FakeLuna()
        let session = camera.connectedSession()
        camera.applyDelay = .milliseconds(200)
        let shutter = CameraCommand(
            .set(.shutter(.duration(Rational(1, 100)))),
            preconditions: CommandPreconditions(session.current))
        _ = await session.submit(shutter)
        let iso = CameraCommand(
            .set(.iso(.manual(400))), preconditions: CommandPreconditions(session.current))
        _ = await session.submit(iso)
        let sent = try LunaPhotographySettings(response: try XCTUnwrap(camera.sent.last).body)
        XCTAssertEqual(sent.videoExposure?.exposureProgram, .manual)
        XCTAssertEqual(sent.videoExposure?.iso, 400)
        XCTAssertEqual(sent.videoExposure?.shutterSeconds ?? 0, 0.01, accuracy: 1e-9)
        let shutterOutcome = await session.outcome(of: shutter.operation)
        let isoOutcome = await session.outcome(of: iso.operation)
        XCTAssertEqual(shutterOutcome?.stage, .confirmed)
        XCTAssertEqual(isoOutcome?.stage, .confirmed)
        XCTAssertEqual(session.current.value(of: .shutter).value, .shutter(.duration(Rational(1, 100))))
    }

    func testRecordingProfileIsCameraReportedOrUnknown() {
        let camera = FakeLuna()
        let session = camera.connectedSession()
        XCTAssertNil(session.recordingProfile.value)
        camera.colorMode = LunaColorMode.iLog.rawValue
        camera.reportSettings()
        XCTAssertEqual(session.recordingProfile.value, "com.opencapture.insta360.luna.profile.i-log")
        XCTAssertEqual(session.recordingProfile.origin, .cameraReported)
        XCTAssertEqual(session.current.mode.value?.role, .video)
    }

    func testANewerWriteToTheSameSettingSupersedesTheOlder() async {
        let camera = FakeLuna()
        let session = camera.connectedSession(settle: .seconds(5))
        camera.applyDelay = .seconds(10)
        let older = await session.submit(
            CameraCommand(.set(.iso(.manual(400))), preconditions: CommandPreconditions(session.current)))
        XCTAssertEqual(session.receipt(of: older.operation)?.stage, .awaitingObservation)
        _ = await session.submit(
            CameraCommand(.set(.iso(.manual(1600))), preconditions: CommandPreconditions(session.current)))
        XCTAssertEqual(session.receipt(of: older.operation)?.stage, .failed(.superseded))
        session.close(.requested)
    }

    func testLinkLossEndsInFlightWritesAsUnknownAndANewLinkIsANewEpoch() async {
        let camera = FakeLuna()
        let session = camera.connectedSession(settle: .seconds(5))
        camera.applyDelay = .seconds(10)
        let epoch = session.current.epoch
        let command = CameraCommand(
            .set(.iso(.manual(1600))), preconditions: CommandPreconditions(session.current))
        _ = await session.submit(command)
        session.linkChanged(.idle, serial: nil)
        let outcome = await session.outcome(of: command.operation)
        XCTAssertEqual(outcome?.stage, .outcomeUnknown)
        guard case .recovering = session.current.connection else {
            return XCTFail("expected recovering, got \(session.current.connection)")
        }
        session.linkChanged(.streaming, serial: nil)
        XCTAssertEqual(session.current.epoch, epoch.next())
        let late = await session.submit(
            CameraCommand(
                .set(.iso(.manual(200))),
                preconditions: CommandPreconditions(
                    session: session.id, epoch: epoch,
                    capabilityRevision: session.current.capabilities.revision)))
        XCTAssertEqual(late.stage, .rejected(.staleEpoch), "an edit from the old link is refused")
    }

    func testCloseFinishesFeedsAndNeverSends() async {
        let camera = FakeLuna()
        let session = camera.connectedSession()
        let feed = session.snapshots()
        session.close(.requested)
        session.close(.requested)
        var last: CameraSnapshot?
        for await snapshot in feed { last = snapshot }
        XCTAssertEqual(last?.connection, .disconnected(.requested))
        let (_, after) = await submit(.startRecording, to: session)
        XCTAssertEqual(after.stage, .rejected(.sessionClosed))
        XCTAssertTrue(camera.sent.isEmpty)
    }
}

/// The app's record lamp through the Core seam: explicit start/stop from a fresh report.
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
        shell.attachCore(camera.connectedSession())
        try await waitUntil { shell.core.snapshot != nil }
        shell.toggleRecording()
        try await waitUntil { !shell.controlBusy }
        XCTAssertTrue(camera.sent.isEmpty, "unknown recording must not send a toggle")
        XCTAssertNil(shell.reportedRecording)
        XCTAssertNotNil(shell.controlNote)

        camera.captureState = 1
        camera.reportCapture()
        try await waitUntil { shell.reportedRecording == true }
        XCTAssertTrue(shell.status.isRecording)
        shell.toggleRecording()
        XCTAssertTrue(shell.controlBusy, "the lamp holds until the camera reports")
        try await waitUntil { !shell.controlBusy }
        XCTAssertEqual(camera.sent.map(\.command), [.stopCapture])
        XCTAssertEqual(shell.reportedRecording, false)
        XCTAssertFalse(shell.status.isRecording)

        // A confirmed start while the camera already records sends nothing.
        camera.captureState = 1
        camera.reportCapture()
        try await waitUntil { shell.reportedRecording == true }
        shell.setRecording(start: true)
        try await waitUntil { !shell.controlBusy }
        XCTAssertEqual(camera.sent.count, 1)
        shell.detachCore()
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
        a.attachCore(cameraA.connectedSession())
        b.attachCore(cameraB.connectedSession())
        try await waitUntil { a.reportedRecording == false && b.reportedRecording == false }
        a.setRecording(start: true)
        b.setRecording(start: true)
        try await waitUntil { !a.controlBusy && !b.controlBusy }
        XCTAssertEqual(cameraA.sent.map(\.command), [.startCapture])
        XCTAssertEqual(cameraB.sent.map(\.command), [.startCapture])
        XCTAssertEqual(a.reportedRecording, true)
        XCTAssertEqual(b.reportedRecording, true)

        let closedA = try XCTUnwrap(cameraA.session)
        a.detachCore()
        try await waitUntil { closedA.current.connection != .ready }
        b.setRecording(start: false)
        try await waitUntil { !b.controlBusy }
        XCTAssertEqual(cameraB.sent.map(\.command), [.startCapture, .stopCapture])
        XCTAssertEqual(b.reportedRecording, false)
        XCTAssertEqual(cameraA.sent.map(\.command), [.startCapture], "closing never sends a command")
        let shownB = try XCTUnwrap(cameraB.session).current
        XCTAssertEqual(shownB.connection, .ready)
        b.detachCore()
    }

    func testALeaseNeverTakesTheOwnersCallbacks() {
        let owner = AppModel().session
        let lease = OpenInstaCine.CameraSession(
            backend: owner.backend, borrowing: HevcDecoder(), controlsOnly: true)
        owner.activateBackend()
        lease.startScan()
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
        shell.attachCore(core)
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
        shell.detachCore()
    }
}
