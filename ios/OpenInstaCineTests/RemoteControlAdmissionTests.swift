import Insta360Apple
import Insta360AppleTestSupport
import Insta360Protocol
import OpenCineAppKit
import OpenCineCore
import OpenCineCameraControls
import OpenInstaViewCore
import XCTest

@testable import OpenInstaCine

/// SIMULATED actual facade and controllable first-send ports. No wall-clock wait or camera I/O.
@MainActor
final class RemoteControlAdmissionTests: XCTestCase {
  func testNativeHeldReadoutsUseRecordingFactsInsteadOfTheLegacyWireProjection() throws {
    let wire = RemoteLunaWire()
    let core = wire.connect()
    let facade = host(core)
    let model = AppModel(session: facade)
    defer { facade.disconnect(); core.close(.requested) }
    facade.status.videoFormat = VideoFormat(resolution: .p4K, frameRate: .fps30)
    facade.status.colorMode = .normal
    facade.status.availableColorModes = LunaShellMapping.colorModes
    facade.nativeRecordingFormat = try XCTUnwrap(LunaVideoResolution(rawValue: 48))
    facade.nativeRecordingColor = .iLog
    XCTAssertEqual(model.quickSnapshot(.resolution)?.selection, "25p")
    XCTAssertEqual(model.quickSnapshot(.color)?.selection, "I-Log")
  }

  func testUnknownRecordingFactCannotSendANativeFormatOrColorWrite() throws {
    let wire = RemoteLunaWire()
    let core = wire.connect()
    let facade = host(core)
    defer { facade.disconnect(); core.close(.requested) }
    facade.status.shootingMode = Int(ShootingMode.video.rawValue)
    facade.status.isRecording = false
    let current = try XCTUnwrap(LunaVideoResolution(rawValue: 48))
    facade.nativeRecordingFormat = current
    facade.nativeRecordingColor = .standard
    wire.camera.captureState = 4
    wire.camera.reportCapture()
    XCTAssertNil(core.current.recording.value, "A photo capture report declares no movie recording state")
    facade.setNativeRecordingFormat(try XCTUnwrap(LunaVideoResolution(rawValue: 49)))
    facade.setNativeRecordingColor(.iLog)
    XCTAssertEqual(facade.nativeRecordingFormat, current)
    XCTAssertEqual(facade.nativeRecordingColor, .standard)
    XCTAssertNil(facade.nativeFormatPin)
    XCTAssertNil(facade.nativeColorPin)
    XCTAssertTrue(wire.queued.isEmpty)
    XCTAssertTrue(wire.writes.isEmpty)
  }

  private func meterReadout(_ model: AppModel) throws -> MonitorOperatorSupplementaryCaptureReadout<CaptureSheet, Int> {
    let inputs = MonitorOperatorCaptureInputs<CaptureSheet, Int, MonitorOperatorLegacyCaptureIdentity>.captureSheetHost(model)
    return try XCTUnwrap(inputs.supplementaryReadouts.first { $0.id == "native.metering" })
  }
  func testNativeMeteringUnknownLockAndRetiredSourceNeverQueueACommand() async throws {
    let wire = RemoteLunaWire()
    let core = wire.connect()
    let facade = host(core)
    let model = AppModel(session: facade)
    defer { facade.disconnect(); core.close(.requested) }
    await drain { facade.control.snapshot?.session == core.id }
    facade.faceMetering = nil
    let unknown = try meterReadout(model)
    XCTAssertEqual(unknown.accessibilityValue, "Unknown")
    XCTAssertFalse(unknown.perform(admitted: true))
    facade.faceMetering = false
    let known = try meterReadout(model)
    XCTAssertEqual(known.accessibilityValue, "Matrix")
    XCTAssertFalse(known.perform(admitted: false), "Hidden, inactive, held or covered input is not admitted")
    facade.isLocked = true
    XCTAssertFalse(known.perform(admitted: true))
    facade.isLocked = false
    core.commandOwner.replaceSource()
    XCTAssertFalse(known.perform(admitted: true))
    XCTAssertEqual(facade.faceMetering, false)
    XCTAssertTrue(wire.queued.isEmpty)
    XCTAssertTrue(wire.writes.isEmpty)
  }
  func testNativeMeteringKnownFactQueuesTheActualOption46ForItsOwner() async throws {
    let wire = RemoteLunaWire()
    let core = wire.connect()
    let facade = host(core)
    let model = AppModel(session: facade)
    defer { facade.disconnect(); core.close(.requested) }
    await drain { facade.control.snapshot?.session == core.id }
    facade.faceMetering = false
    let shown = try meterReadout(model)
    XCTAssertTrue(shown.perform(admitted: true))
    await wire.waitUntilQueued(1)
    XCTAssertTrue(wire.enter(0))
    XCTAssertEqual(wire.writes, [try LunaProtocol.setFaceMetering(true, functionMode: LunaFunctionMode.normalVideo.rawValue)])
    XCTAssertEqual(facade.faceMetering, true)
    XCTAssertFalse(shown.perform(admitted: true), "The old Matrix readout cannot replay against the new Face target")
    wire.answer(0)
    XCTAssertTrue(wire.direct.isEmpty)
  }

  func testRevokedOperationDoesNotCommitActualPinsBusyFocusOrCommonTargets() {
    let wire = RemoteLunaWire()
    let core = wire.connect()
    let host = host(core)
    defer {
      host.disconnect()
      core.close(.requested)
    }
    host.status.colorMode = .normal
    host.status.whiteBalance = .auto(tint: 0)
    let receipt = LunaCommandAdmission(owner: core.commandOwner, isCurrent: { true })
    core.commandOwner.replaceSource()
    host.setISO(.iso800, admission: receipt)
    host.setShutterDenom(100, admission: receipt)
    host.setWhiteBalanceAuto(admission: receipt)
    host.setWhiteBalanceCustom(kelvin: 6000, tint: 0, admission: receipt)
    host.setRecording(start: true, admission: receipt)
    host.pressShutter(admission: receipt)
    host.setColorMode(.iLog, admission: receipt)
    host.setZoom(3, admission: receipt)
    host.markFocus(at: .init(x: 0.1, y: 0.2), admission: receipt)
    XCTAssertTrue(host.control.pending.isEmpty)
    XCTAssertFalse(host.controlBusy)
    XCTAssertNil(host.pins.color)
    XCTAssertNil(host.zoomPin)
    XCTAssertNil(host.pendingZoomWrite)
    XCTAssertEqual(host.status.colorMode, .normal)
    XCTAssertEqual(host.focusPoint, .init(x: 0.5, y: 0.5))
    XCTAssertTrue(wire.queued.isEmpty)
    XCTAssertTrue(wire.writes.isEmpty)
    XCTAssertTrue(wire.direct.isEmpty)
    let record: () -> Void = host.toggleRecording
    let photo: () -> Void = host.pressShutter
    let color: (ColorMode) -> Void = host.setColorMode
    let focus: (CGPoint) -> Void = host.markFocus
    _ = (record, photo, color, focus)
  }

  func testActualCommonPortKeepsItsCapturedNativeSessionAndEnteredOutcome() async throws {
    let wire = RemoteLunaWire()
    let core = wire.connect()
    let host = host(core)
    defer {
      host.disconnect()
      core.close(.requested)
    }
    let receipt = LunaCommandAdmission(owner: core.commandOwner, isCurrent: { true })
    let dispatch = try XCTUnwrap(host.commandDispatchAdmission(receipt))
    let command = CameraCommand(
      .set(.whiteBalance(.kelvin(6000))),
      preconditions: CommandPreconditions(core.current))
    let send = Task { await dispatch.dispatch(command, on: core.id) }
    await wire.waitUntilQueued(1)
    XCTAssertTrue(wire.enter(0))
    core.commandOwner.replaceSource()
    wire.answer(0)
    let outcome = await send.value
    XCTAssertEqual(outcome.stage, .awaitingObservation)
    wire.clock.advance(.milliseconds(1))
    wire.camera.kelvin = 6000
    wire.camera.reportSettings()
    XCTAssertEqual(core.receipt(of: command.operation)?.stage, .confirmed)
    XCTAssertEqual(
      wire.writes,
      [
        try LunaProtocol.setWhiteBalanceKelvin(
          6000,
          functionMode: LunaFunctionMode.normalVideo.rawValue)
      ])
    XCTAssertTrue(wire.direct.isEmpty)
  }

  func testMismatchedCommonBindingAndOldRecordApprovalRefuseBeforeScheduling() async throws {
    let first = RemoteLunaWire()
    let successor = RemoteLunaWire()
    let a = first.connect()
    let b = successor.connect()
    let host = host(a)
    defer {
      host.disconnect()
      a.close(.requested)
      b.close(.requested)
    }
    await drain { host.control.snapshot?.session == a.id }
    let editor = try XCTUnwrap(host.control.recordEditor())
    let shown = LunaCommandAdmission(owner: a.commandOwner, isCurrent: { true })
    host.control.bind(b)
    XCTAssertNil(host.commandDispatchAdmission(shown))
    XCTAssertFalse(host.commitRecording(from: editor, admission: shown))
    XCTAssertFalse(host.controlBusy)
    XCTAssertTrue(first.queued.isEmpty)
    XCTAssertTrue(successor.queued.isEmpty)
    host.lunaSessionOverride = b
    a.commandOwner.replaceSource()
    XCTAssertFalse(host.commitRecording(from: editor, admission: shown))
    XCTAssertTrue(successor.writes.isEmpty)
  }

  func testOldZoomFinallyCannotConsumeOrReleaseTheSuccessorEntry() async throws {
    let first = RemoteLunaWire()
    let successor = RemoteLunaWire()
    let a = first.connect()
    let b = successor.connect()
    let host = host(a)
    defer {
      a.close(.requested)
      b.close(.requested)
    }
    host.setZoom(2, admission: .init(owner: a.commandOwner, isCurrent: { true }))
    await first.waitUntilQueued(1)
    XCTAssertTrue(first.enter(0))
    let oldTask = try XCTUnwrap(host.zoomWriteTask)
    let oldRevision = host.zoomWriteRevision
    host.disconnect()
    XCTAssertNil(host.zoomWriteTask)
    host.lunaSessionOverride = b
    host.control.bind(b)
    host.phase = .live
    host.setZoom(3, admission: .init(owner: b.commandOwner, isCurrent: { true }))
    await successor.waitUntilQueued(1)
    XCTAssertTrue(successor.enter(0))
    let newTask = try XCTUnwrap(host.zoomWriteTask)
    let newRevision = host.zoomWriteRevision
    XCTAssertNotEqual(newRevision, oldRevision)
    let nextReceipt = LunaCommandAdmission(owner: b.commandOwner, isCurrent: { true })
    host.setZoom(4, admission: nextReceipt)
    first.answer(0)
    await oldTask.value
    XCTAssertEqual(host.zoomWriteRevision, newRevision)
    XCTAssertNotNil(host.zoomWriteTask)
    XCTAssertEqual(host.pendingZoomWrite?.factor, 4)
    XCTAssertTrue(host.pendingZoomWrite?.session === b)
    XCTAssertEqual(host.pendingZoomWrite?.admission?.source, nextReceipt.source)
    XCTAssertEqual(
      first.writes,
      [
        try LunaProtocol.setZoomScale(
          2,
          functionMode: LunaFunctionMode.normalVideo.rawValue)
      ])
    XCTAssertEqual(
      successor.writes,
      [
        try LunaProtocol.setZoomScale(
          3,
          functionMode: LunaFunctionMode.normalVideo.rawValue)
      ])
    host.disconnect()
    successor.answer(0)
    await newTask.value
    XCTAssertNil(host.zoomWriteTask)
    XCTAssertNil(host.pendingZoomWrite)
    XCTAssertEqual(successor.writes.count, 1, "Close never flushes the unsent successor")
  }

  func testUnsentOldColorRefusalCannotRetractTheNewerPin() async throws {
    let wire = RemoteLunaWire()
    let core = wire.connect()
    let host = host(core)
    defer {
      host.disconnect()
      core.close(.requested)
    }
    host.status.colorMode = .normal
    let first = RemoteLunaGate()
    let oldTask = try XCTUnwrap(
      host.setColorMode(
        .iLog,
        admission: .init(owner: core.commandOwner, isCurrent: { first.isCurrent })))
    await wire.waitUntilQueued(1)
    let newTask = try XCTUnwrap(
      host.setColorMode(
        .dolbyVision,
        admission: .init(owner: core.commandOwner, isCurrent: { true })))
    await wire.waitUntilQueued(2)
    let successorPin = try XCTUnwrap(host.pins.color).id
    let note = host.controlNote
    first.revoke()
    XCTAssertFalse(wire.enter(0))
    await oldTask.value
    XCTAssertEqual(host.pins.color?.id, successorPin)
    XCTAssertEqual(host.status.colorMode, .dolbyVision)
    XCTAssertEqual(host.controlNote, note)
    XCTAssertTrue(wire.writes.isEmpty)
    XCTAssertTrue(wire.enter(1))
    wire.answer(1)
    await newTask.value
    XCTAssertEqual(
      wire.writes,
      [
        try LunaProtocol.setColorMode(
          .dolbyVision,
          functionMode: LunaFunctionMode.normalVideo.rawValue)
      ])
  }

  func testEnteredOldControlSuccessAndErrorCannotPublishOntoAReplacementFacade() async throws {
    for reply in [Result<Data, Error>.success(Data([0xAB])), .failure(RemoteControlError.refused)] {
      let first = RemoteLunaWire()
      let second = RemoteLunaWire()
      let a = first.connect()
      let b = second.connect()
      let host = host(a)
      defer {
        host.disconnect()
        a.close(.requested)
        b.close(.requested)
      }
      var successes = 0
      var failures = 0
      let task = try XCTUnwrap(
        host.sendControl(
          "WB", { try LunaProtocol.setWhiteBalanceKelvin(6000) },
          admission: .init(owner: a.commandOwner, isCurrent: { true }),
          onFail: { failures += 1 }, onSuccess: { _ in successes += 1 }))
      await first.waitUntilQueued(1)
      XCTAssertTrue(first.enter(0))
      host.lunaSessionOverride = b
      host.controlNote = "Successor source"
      first.answer(0, reply: reply)
      await task.value
      XCTAssertEqual(successes, 0)
      XCTAssertEqual(failures, 0)
      XCTAssertEqual(host.controlNote, "Successor source")
      XCTAssertEqual(first.writes.count, 1, "The entered native transaction still completed")
      XCTAssertTrue(second.queued.isEmpty)
      XCTAssertTrue(second.writes.isEmpty)
    }
  }

  func testEnteredColorFailureCannotRetractANewerSameSourcePin() async throws {
    let wire = RemoteLunaWire()
    let core = wire.connect()
    let host = host(core)
    defer {
      host.disconnect()
      core.close(.requested)
    }
    host.status.colorMode = .normal
    let oldTask = try XCTUnwrap(
      host.setColorMode(
        .iLog, admission: .init(owner: core.commandOwner, isCurrent: { true })))
    await wire.waitUntilQueued(1)
    XCTAssertTrue(wire.enter(0))
    let newTask = try XCTUnwrap(
      host.setColorMode(
        .dolbyVision, admission: .init(owner: core.commandOwner, isCurrent: { true })))
    await wire.waitUntilQueued(2)
    let newPin = try XCTUnwrap(host.pins.color).id
    wire.answer(0, reply: .failure(RemoteControlError.refused))
    await oldTask.value
    XCTAssertEqual(host.pins.color?.id, newPin)
    XCTAssertEqual(host.status.colorMode, .dolbyVision)
    XCTAssertTrue(wire.enter(1))
    wire.answer(1)
    await newTask.value
    XCTAssertEqual(host.pins.color?.id, newPin)
    XCTAssertEqual(host.status.colorMode, .dolbyVision)
    XCTAssertEqual(wire.writes.count, 2)
  }

  func testEnteredPhotoSuccessAndErrorCannotReleaseTheSameEndpointAtANewEpoch() async throws {
    for reply in [Result<Data, Error>.success(Data([0xAB])), .failure(RemoteControlError.refused)] {
      let wire = RemoteLunaWire()
      let core = wire.connect()
      let host = host(core)
      defer {
        host.disconnect()
        core.close(.requested)
      }
      host.status.shootingMode = Int(ShootingMode.photo.rawValue)
      let task = try XCTUnwrap(
        host.pressShutter(
          admission: .init(owner: core.commandOwner, isCurrent: { true })))
      await wire.waitUntilQueued(1)
      XCTAssertTrue(wire.enter(0))
      let oldEpoch = core.current.epoch
      core.linkChanged(.streaming, serial: "SIMULATED-LUNA-REMOTE")
      XCTAssertNotEqual(core.current.epoch, oldEpoch)
      XCTAssertTrue(host.lunaSession === core, "The concrete endpoint object was reused")
      host.controlBusy = true
      host.pins.photoInFlight = true
      host.controlNote = "Successor photo"
      wire.answer(0, reply: reply)
      await task.value
      XCTAssertTrue(host.controlBusy)
      XCTAssertTrue(host.pins.photoInFlight)
      XCTAssertEqual(host.controlNote, "Successor photo")
      XCTAssertEqual(wire.writes.count, 1)
      XCTAssertTrue(wire.direct.isEmpty)
    }
  }

  func testEnteredCurrentColorCompletionDoesNotRecheckExpiredOperatorAuthority() async throws {
    let wire = RemoteLunaWire()
    let core = wire.connect()
    let host = host(core)
    defer {
      host.disconnect()
      core.close(.requested)
    }
    host.status.colorMode = .normal
    let gate = RemoteLunaGate()
    let task = try XCTUnwrap(
      host.setColorMode(
        .iLog, admission: .init(owner: core.commandOwner, isCurrent: { gate.isCurrent })))
    await wire.waitUntilQueued(1)
    XCTAssertTrue(wire.enter(0))
    gate.revoke()
    wire.answer(0, reply: .failure(RemoteControlError.refused))
    await task.value
    XCTAssertNil(host.pins.color, "The entered current-source failure keeps its original rollback")
    XCTAssertEqual(host.status.colorMode, .normal)
    XCTAssertEqual(
      host.controlNote, ColorMode.iLog.label(in: host.profile) + " was not applied by the camera.")
    XCTAssertEqual(wire.writes.count, 1)
  }

  func testUnsentFocusRefusalDoesNotPublishACameraFailureOntoTheSuccessor() async throws {
    let wire = RemoteLunaWire()
    let core = wire.connect()
    let host = host(core)
    defer {
      host.disconnect()
      core.close(.requested)
    }
    let receipt = LunaCommandAdmission(owner: core.commandOwner, isCurrent: { true })
    let finish = host.controlFinished("Focus", admission: receipt)
    let done = RemoteControlCompletion()
    try host.subjectTracking.focus(x: 0.4, y: 0.6, admission: receipt) { error in
      finish(error)
      done.finish(error)
    }
    await wire.waitUntilQueued(1)
    core.commandOwner.replaceSource()
    host.controlNote = "Successor source"
    XCTAssertFalse(wire.enter(0))
    let error = await done.value()
    XCTAssertEqual(error as? LunaCommandAdmissionError, .expired)
    XCTAssertEqual(host.controlNote, "Successor source")
    XCTAssertTrue(wire.writes.isEmpty)
    XCTAssertTrue(wire.direct.isEmpty)
  }

  func testShownWatchNativeSourceStaysRetiredAcrossABAUntilRepublished() throws {
    let first = RemoteLunaWire()
    let second = RemoteLunaWire()
    let a = first.connect()
    let b = second.connect()
    let host = host(a)
    let model = AppModel(session: host)
    defer {
      host.disconnect()
      a.close(.requested)
      b.close(.requested)
    }
    model.publishWatchState()
    let shown = try XCTUnwrap(model.watchCommandSource)
    XCTAssertTrue(shown.admits(a.commandOwner))
    XCTAssertTrue(model.watchSourceSession === a)
    a.commandOwner.replaceSource()
    XCTAssertFalse(shown.isCurrent)
    XCTAssertEqual(model.watchCommandSource?.source, shown.source)
    model.publishWatchState()
    XCTAssertNotEqual(model.watchCommandSource?.source, shown.source)
    XCTAssertTrue(model.watchCommandSource?.admits(a.commandOwner) == true)
    host.lunaSessionOverride = b
    XCTAssertFalse(model.watchCommandSource?.admits(b.commandOwner) == true)
    model.publishWatchState()
    XCTAssertTrue(model.watchSourceSession === b)
    XCTAssertEqual(model.watchSourceEpoch, b.current.epoch)
    model.noteLeftLive()
    XCTAssertNil(model.watchCommandSource)
    XCTAssertNil(model.watchSourceSession)
    XCTAssertNil(model.watchSourceEpoch)
    XCTAssertTrue(first.writes.isEmpty)
    XCTAssertTrue(second.writes.isEmpty)
  }

  private func host(_ core: LunaCameraSession) -> OpenInstaCine.CameraSession {
    let host = OpenInstaCine.CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder())
    host.lunaSessionOverride = core
    host.control.bind(core)
    host.phase = .live
    return host
  }
  private func drain(_ predicate: () -> Bool) async {
    for _ in 0..<2000 {
      if predicate() { return }
      await Task.yield()
    }
    XCTFail("Controllable source did not publish the expected state")
  }
}

@MainActor
private final class RemoteControlCompletion {
  private var completed = false
  private var error: Error?
  private var waiting: CheckedContinuation<Error?, Never>?
  func finish(_ error: Error?) {
    self.error = error
    completed = true
    waiting?.resume(returning: error)
    waiting = nil
  }
  func value() async -> Error? {
    if completed { return error }
    return await withCheckedContinuation { waiting = $0 }
  }
}

private final class RemoteLunaGate: @unchecked Sendable {
  private let lock = NSLock()
  private var active = true
  var isCurrent: Bool {
    lock.lock()
    defer { lock.unlock() }
    return active
  }
  func revoke() {
    lock.lock()
    active = false
    lock.unlock()
  }
}

private enum RemoteControlError: Error, Sendable { case refused }

private final class RemoteLunaClock: @unchecked Sendable {
  private let lock = NSLock()
  private var instant = MonotonicInstant.zero
  func read() -> MonotonicInstant {
    lock.lock()
    defer { lock.unlock() }
    return instant
  }
  func advance(_ amount: Duration) {
    lock.lock()
    instant = instant + amount
    lock.unlock()
  }
}

@MainActor
private final class RemoteLunaWire {
  final class Pending {
    let build: LunaCommandRequestBuilder
    let admission: LunaCommandAdmission
    let didDispatch: LunaCommandDidDispatch
    var continuation: CheckedContinuation<Data, Error>?
    var entered = false
    init(
      build: @escaping LunaCommandRequestBuilder, admission: LunaCommandAdmission,
      didDispatch: @escaping LunaCommandDidDispatch, continuation: CheckedContinuation<Data, Error>
    ) {
      self.build = build
      self.admission = admission
      self.didDispatch = didDispatch
      self.continuation = continuation
    }
  }
  let camera = FakeLuna()
  let clock = RemoteLunaClock()
  var queued: [Pending] = []
  var writes: [LunaRequest] = []
  var direct: [LunaRequest] = []
  private var waiting: [(Int, CheckedContinuation<Void, Never>)] = []
  func connect() -> LunaCameraSession {
    let session = LunaCameraSession(
      send: { [unowned self] request in
        direct.append(request)
        return Data()
      },
      functionMode: { LunaFunctionMode.normalVideo.rawValue }, readSettings: {}, readCapture: {},
      sendAdmitted: { [unowned self] build, admission, didDispatch in
        try await withCheckedThrowingContinuation { continuation in
          queued.append(
            .init(
              build: build, admission: admission,
              didDispatch: didDispatch, continuation: continuation))
          let ready = waiting.filter { queued.count >= $0.0 }
          waiting.removeAll { queued.count >= $0.0 }
          for (_, waiter) in ready { waiter.resume() }
        }
      }, now: { [clock] in clock.read() })
    camera.session = session
    session.linkChanged(.streaming, serial: "SIMULATED-LUNA-REMOTE")
    session.configureLens(zoomDomain: 1...15)
    camera.reportDevice()
    camera.reportSettings()
    camera.reportCapture()
    return session
  }
  func waitUntilQueued(_ count: Int) async {
    if queued.count >= count { return }
    await withCheckedContinuation { waiting.append((count, $0)) }
  }
  func enter(_ index: Int) -> Bool {
    let pending = queued[index]
    guard pending.continuation != nil, !pending.entered else { return false }
    do {
      try pending.admission.requireCurrent()
      writes.append(try pending.build())
      pending.entered = true
      pending.didDispatch()
      return true
    } catch {
      pending.continuation?.resume(throwing: error)
      pending.continuation = nil
      return false
    }
  }
  func answer(_ index: Int, reply: Result<Data, Error> = .success(Data())) {
    let pending = queued[index]
    guard pending.entered else { return }
    pending.continuation?.resume(with: reply)
    pending.continuation = nil
  }
}
