import OpenCineAppKit
import OpenCineCameraVocabulary
import CoreGraphics
import Foundation
import Insta360Apple
import Insta360Protocol
import OpenCineCore
import OpenCineMotion
import OpenInstaViewCore

/// The operator's held gimbal stick; `LunaMotionService` streams its MOVEs.
struct LunaStickStream {
    var lastPan = 0.0
    var lastTilt = 0.0
    var isHeld = false

    mutating func reset() {
        lastPan = 0
        lastTilt = 0
        isHeld = false
    }
}

struct LunaQueuedZoomWrite {
    let factor: Double
    let session: LunaCameraSession?
    let admission: LunaCommandAdmission?
}

/// A constructed shutter operation. A missing operation must never acknowledge a Watch press.
enum ShutterPress {
    case record
    case photo(Task<Void, Never>)

    var photoTask: Task<Void, Never>? {
        if case .photo(let task) = self { return task }
        return nil
    }
}

extension CameraSession {
    // MARK: - Capabilities

    /// Luna's static control facts come from the integration's capture profile
    /// (`LunaCameraSession.captureProfile`), never app literals.
    private var profile: CameraCaptureProfile { LunaCameraSession.captureProfile }
    var hasGimbal: Bool { profile.hasGimbal == true }
    var supportsZoom: Bool { profile.supportsZoom == true }
    var supportsTapFocus: Bool { profile.supportsTapFocus == true }
    /// AF-C, AF-S and Product Showcase (option 93); see `LunaShellMapping.focusOptions`.
    var supportsFocusMode: Bool { profile.supportsFocusMode == true }
    /// Matrix / Face Priority metering (option 46), shown in the Exposure sheet.
    var supportsFaceMetering: Bool { profile.controls[.faceMetering] == .supported }
    var supportsAperture: Bool { profile.supportsAperture == true }
    /// Luna sends no metered EV; the EV meter reads the picture.
    var reportsMeteredEV: Bool { false }
    /// Auto ISO ceiling and native-ISO hop are Osmo camcap features; Luna has neither.
    var supportsIsoLimit: Bool { profile.nativeISO.ceiling == true }
    /// DJI camcap hop to the log curve's native ISO on a color change; the ISO sheet hides its toggle.
    var supportsNativeIsoHop: Bool { profile.nativeISO.hop == true }
    /// The one control model of the camera: the live session's when connected, else the shared
    /// pre-connection rule over Luna's static profile (the shared capture UI reads this).
    func controlCapabilities(codecColor: CaptureCodecColorChoices? = nil) -> ControlCapabilities {
        lunaSession?.controlCapabilities(codecColor: codecColor)
            ?? ControlCapabilities(beforeConnection: profile, motion: LunaCameraSession.motion,
                codecColor: codecColor)
    }
    /// Luna media browse runs over HTTP next to the live socket.
    /// The connection's Luna session: every request goes through it, and its admission is this
    /// facade's control link (it flips with the backend's handshake). Tests set the override.
    var lunaSession: LunaCameraSession? { lunaSessionOverride ?? backend.session }
    func configureShutterPresentation(usesAngle: Bool) {
        lunaSession?.configureShutter(presentation: usesAngle ? .emulatedAngle : .cameraValue)
    }
    var hasControlLink: Bool { lunaSession?.admitsControl == true }
    var bodyFamily: CameraBodyFamily { .other }
    var colorModes: [ColorMode] { LunaShellMapping.colorModes }

    var currentShootingMode: ShootingMode? { ShootingMode.fromStatus(status.shootingMode) }

    var canSendControl: Bool {
        guard case .live = phase, hasControlLink else {
            controlNote = "Connect the camera to use its controls."
            return false
        }
        guard !isLocked else {
            controlNote = "Controls locked"
            return false
        }
        return true
    }

    /// Every camera request goes through the connection's Luna session, which sends only while it
    /// is ready and owned (the Insta360 rule: commands only through `LunaCameraSession`).
    func sendLuna(_ request: LunaRequest, timeout: Duration? = nil) async throws -> Data {
        guard let session = lunaSession else { throw CancellationError() }
        return try await session.control(request, timeout: timeout)
    }

    func sendLuna(
        _ request: LunaRequest, through session: LunaCameraSession,
        admission: LunaCommandAdmission, timeout: Duration? = nil
    ) async throws -> Data {
        try await session.control(request, admission: admission, timeout: timeout)
    }

    /// Sends one Luna request off the main flow. Failure reverts through `onFail`.
    func sendControl(
        _ name: String, _ build: () throws -> LunaRequest, refresh: Bool = true,
        onFail: (@MainActor () -> Void)? = nil, onSuccess: (@MainActor (Data) -> Void)? = nil
    ) {
        sendControl(name, build, through: nil, suppliedAdmission: nil, refresh: refresh,
            onFail: onFail, onSuccess: onSuccess)
    }

    @discardableResult
    func sendControl(
        _ name: String, _ build: () throws -> LunaRequest, admission: LunaCommandAdmission,
        refresh: Bool = true, onFail: (@MainActor () -> Void)? = nil,
        onSuccess: (@MainActor (Data) -> Void)? = nil
    ) -> Task<Void, Never>? {
        guard let target = lunaSession, admission.admits(target.commandOwner) else { onFail?(); return nil }
        return sendControl(name, build, through: target, suppliedAdmission: admission, refresh: refresh,
            onFail: onFail, onSuccess: onSuccess)
    }

    @discardableResult
    private func sendControl(
        _ name: String, _ build: () throws -> LunaRequest, through target: LunaCameraSession?,
        suppliedAdmission admission: LunaCommandAdmission?, refresh: Bool = true,
        onFail: (@MainActor () -> Void)? = nil, onSuccess: (@MainActor (Data) -> Void)? = nil,
        onUnsent: (@MainActor () -> Void)? = nil
    ) -> Task<Void, Never>? {
        // This snapshot uses only the native owner, not the operator's expiring receipt.
        // Already-entered work finishes; its facade publication still belongs to this source.
        let source = target.map { LunaCommandAdmission(owner: $0.commandOwner, isCurrent: { true }) }
        let epoch = target?.current.epoch
        let request: LunaRequest
        do { request = try build() } catch {
            controlNote = "\(name): \(error.localizedDescription)"
            onFail?()
            return nil
        }
        return Task { @MainActor [weak self] in
            guard let self else { return }
            @MainActor func mayPublish() -> Bool {
                guard let admission else { return true }
                return target === self.lunaSession && source?.source == admission.source
                    && source?.admits(target?.commandOwner) == true && target?.current.epoch == epoch
            }
            do {
                let reply: Data
                if let admission {
                    guard let target else { throw LunaCommandAdmissionError.expired }
                    reply = try await self.sendLuna(request, through: target, admission: admission)
                } else {
                    reply = try await self.sendLuna(request)
                }
                guard mayPublish() else { return }
                ControlLiveLog.line("control: \(name) ok")
                onSuccess?(reply)
                // A success callback may synchronously replace the producer too.
                guard mayPublish() else { return }
                if refresh {
                    if admission != nil, let target, let source, let epoch {
                        self.scheduleSettingsRefresh(through: target, source: source, epoch: epoch)
                    } else { self.scheduleSettingsRefresh() }
                }
            } catch {
                guard mayPublish() else { return }
                if error is LunaCommandAdmissionError, admission != nil {
                    if let onUnsent { onUnsent() } else { onFail?() }
                    return
                }
                ControlLiveLog.line("control: \(name) failed \(error.localizedDescription)")
                self.noteCommandFailure()
                self.controlNote = "\(name) was not applied by the camera."
                onFail?()
            }
        }
    }

    /// One settings read shortly after a burst of writes (drums send many).
    func scheduleSettingsRefresh() {
        refreshDebounce.schedule { [weak self] in
            await self?.backend.refreshSettings()
        }
    }

    private func scheduleSettingsRefresh(
        through target: LunaCameraSession, source: LunaCommandAdmission, epoch: ControlEpoch
    ) {
        refreshDebounce.schedule { [weak self] in
            guard let self, self.lunaSession === target, source.admits(target.commandOwner),
                target.current.epoch == epoch
            else { return }
            await self.backend.refreshSettings()
        }
    }

    private var pinNow: TimeInterval { Date.timeIntervalSinceReferenceDate }

    // MARK: - Record / photo

    /// Rec lamp: start/stop video, or take a still in Photo. Record never lies: the
    /// lamp holds `controlBusy` until the Core session reports the outcome.
    func pressShutter() {
        _ = makeShutterPress(admission: nil, record: { toggleRecording(); return true })
    }

    @discardableResult
    func pressShutter(admission: LunaCommandAdmission) -> Task<Void, Never>? {
        makeShutterPress(admission: admission, record: {
            toggleRecording(admission: admission)
            return true
        })?.photoTask
    }

    func shutterPress(admission: LunaCommandAdmission?) -> ShutterPress? {
        makeShutterPress(admission: admission, record: { dispatchWatchRecording(admission: admission) })
    }

    private func makeShutterPress(admission: LunaCommandAdmission?, record: () -> Bool) -> ShutterPress? {
        let target: LunaCameraSession?
        if let admission {
            guard let captured = lunaSession, admission.admits(captured.commandOwner) else { return nil }
            target = captured
        } else { target = nil }
        let photoSource = target.map { LunaCommandAdmission(owner: $0.commandOwner, isCurrent: { true }) }
        let photoEpoch = target?.current.epoch
        guard canSendControl else { return nil }
        guard currentShootingMode?.isPhoto == true else {
            return record() ? .record : nil
        }
        controlBusy = true
        pins.photoInFlight = true
        controlNote = "Photo"
        guard let task = sendControl(
            "Photo", { try LunaProtocol.takePicture(mode: .normal) }, through: target,
            suppliedAdmission: admission, refresh: false,
            onFail: { [weak self] in
                self?.pins.photoInFlight = false
                self?.controlBusy = false
            },
            onSuccess: { [weak self] _ in
                self?.pins.photoInFlight = false
                self?.controlBusy = false
                if admission != nil {
                    Task { @MainActor [weak self] in
                        guard let self, self.lunaSession === target,
                            photoSource?.admits(target?.commandOwner) == true,
                            target?.current.epoch == photoEpoch
                        else { return }
                        await self.refreshMediaAfterCapture()
                    }
                } else { Task { await self?.refreshMediaAfterCapture() } }
            }, onUnsent: { [weak self] in
                guard let self, self.lunaSession === target,
                    admission?.source == target?.commandOwner.source
                else { return }
                self.pins.photoInFlight = false
                self.controlBusy = false
            }) else { return nil }
        return .photo(task)
    }

    func setShootingMode(_ mode: ShootingMode) {
        guard canSendControl else { return }
        guard let luna = LunaShellMapping.lunaShootingMode(mode) else { return }
        guard !status.isRecording else {
            controlNote = ControlHud.recordingColorLockNote
            return
        }
        let previous = status.shootingMode
        let wire = Int(mode.rawValue)
        pins.shootingMode = CameraValuePin(wire, now: pinNow, settle: 3)
        var next = status
        if previous != wire { next.clearModeDependentCapabilities() }
        next.shootingMode = wire
        status = next
        // The backend's settings bank follows the camera's reported mode, not this request.
        formatTable = [:]
        pins.format = nil
        sendControl(
            mode.label(in: profile), { try luna.request() },
            onFail: { [weak self] in
                guard let self else { return }
                self.pins.shootingMode = nil
                self.status.shootingMode = previous
            },
            onSuccess: { [weak self] _ in
                Task { await self?.backend.refreshStatus() }
            })
    }

    // MARK: - Exposure

    func setEv(_ ev: EvComp) {
        guard canSendControl else { return }
        pins.ev = CameraValuePin(ev, now: pinNow)
        status.evComp = ev
        let mode = backend.functionMode
        exposureCoalescer.submit(key: "ev") { [weak self] in
            self?.sendControl(
                "EV \(ev.label)", { try LunaProtocol.setExposureBias(Double(ev.thirds) / 3, functionMode: mode) },
                onFail: { [weak self] in self?.pins.ev = nil })
        }
    }

    /// Luna's ISO ceiling is not an operator setting in the official app.
    func setIsoLimit(_ limit: IsoLimit) {
        controlNote = "Auto ISO ceiling is managed by the camera."
    }

    func refreshIsoLimit() async {}

    func setFacePriorityEnabled(_ on: Bool) {
        if on {
            evBeforeFacePriority = status.evComp ?? .zero
            return
        }
        let restore = FacePriorityExposure.restoreEV(saved: evBeforeFacePriority)
        evBeforeFacePriority = nil
        guard status.expoMode == .auto, status.evComp != restore else { return }
        setEv(restore)
    }

    func setFov(_ fov: FovSetting) {}

    /// Angle is operator intent, never a value inferred back from delayed telemetry.
    func setShutterAngle(_ degrees: Double) {
        guard canSendControl, currentShootingMode?.isPhoto != true else { return }
        let angle = ShutterAngle.nearestDegrees(degrees)
        OperatorPrefs.shutterAngleDegrees = angle
        setShutterDenom(
            ShutterAngle.denom(degrees: angle, fps: status.fps, available: status.availableShutterDenoms))
    }

    // MARK: - AE / AWB lock (no native Luna lock: pin the applied Auto values)

    var canLockAutoExposure: Bool {
        autoExposureLock == nil && AutoExposureLock.capture(status) != nil
    }

    /// Pins the applied Auto exposure as Manual. Luna sends it as one exposure message.
    @discardableResult
    func lockAutoExposure() -> Bool {
        guard autoExposureLock == nil, canSendControl, let lock = AutoExposureLock.capture(status)
        else { return false }
        setExpoMode(.manual)
        setISO(lock.isoIndex)
        setShutterDenom(lock.shutterDenom)
        autoExposureLock = lock
        ControlLiveLog.line("ae-lock: ISO \(lock.isoIndex.label) 1/\(lock.shutterDenom)")
        return true
    }

    func unlockAutoExposure() {
        guard autoExposureLock != nil else { return }
        setExpoMode(.auto)
    }

    var canLockAutoWhiteBalance: Bool { WhiteBalance.lockingAuto(status) != nil }

    /// Pins the live Auto Kelvin as Custom. The optimistic Custom lands first.
    func lockAutoWhiteBalance() {
        guard autoWhiteBalanceLock == nil, let wb = WhiteBalance.lockingAuto(status) else { return }
        setWhiteBalanceCustom(kelvin: wb.kelvin, tint: wb.tint)
        if status.whiteBalance == wb {
            autoWhiteBalanceLock = AutoWhiteBalanceLock(kelvin: wb.kelvin)
        }
    }

    // MARK: - White balance

    // MARK: - Focus mode and metering

    func setFocusMode(_ mode: OpenInstaViewCore.FocusMode) {
        setFocusOption(mode == .single ? .single : .continuousDefault)
    }

    func setFocusTrack(_ track: FocusTrackMode) {
        if let option = FocusOption.resolve(mode: .continuous, track: track) { setFocusOption(option) }
    }

    func setFocusOption(_ option: FocusOption) {
        guard canSendControl else { return }
        guard let af = LunaShellMapping.lunaAFMode(option) else {
            controlNote = "\(option.label) is not offered by this camera."
            return
        }
        pins.focus = CameraValuePin(option, now: pinNow, settle: 3)
        status.focusMode = option.focusMode
        status.focusTrack = option.track
        if af == .single || af == .continuous {
            guard let common = backend.session else {
                pins.focus = nil
                return
            }
            let focus: OpenCineCore.FocusMode = af == .single ? .single : .continuous
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !(await submitLens(.focusMode(focus), through: common)) { pins.focus = nil }
            }
            return
        }
        let mode = backend.functionMode
        sendControl(
            "Focus \(option.chip)", { try LunaProtocol.setAFMode(af, functionMode: mode) },
            onFail: { [weak self] in self?.pins.focus = nil })
    }

    /// fw 1.1.15 stores option 46 3.7 to 4.9 s after the SET.
    func setFaceMetering(_ on: Bool) {
        guard canSendControl, let target = lunaSession else { return }
        let admission = LunaCommandAdmission(owner: target.commandOwner, isCurrent: { true })
        let previous = faceMetering
        let pin = CameraValuePin(on, now: pinNow, settle: 6)
        pins.faceMetering = pin
        faceMetering = on
        let mode = backend.functionMode
        sendControl(
            on ? "Metering Face" : "Metering Matrix",
            { try LunaProtocol.setFaceMetering(on, functionMode: mode) },
            through: target, suppliedAdmission: admission,
            onFail: { [weak self] in
                guard let self, self.pins.faceMetering?.id == pin.id else { return }
                self.pins.faceMetering = nil
                self.faceMetering = previous
            })
    }

    // MARK: - Aperture, audio (not exposed by Luna's phone protocol)

    func setApertureStrategy(_ strategy: ApertureStrategy) {
        controlNote = "Aperture control unavailable"
    }
    func refreshFocusTrack() async {}
    func clearGlamourIfEnabled() async {}

    // MARK: - Format and color

    /// Real Luna identifiers are retained from the camera schema to the admitted native write.
    func setNativeRecordingFormat(_ value: LunaVideoResolution) {
        let previousRate = nativeRecordingFormat?.framesPerSecond
        guard canSendControl, currentShootingMode?.offersVideoFormat == true,
            LunaShellMapping.videoFormatValues.contains(value.rawValue), let target = lunaSession,
            target.current.recording.value == .idle
        else { return }
        let admission = LunaCommandAdmission(owner: target.commandOwner, isCurrent: { true })
        let previous = nativeRecordingFormat
        let pin = CameraValuePin(value, now: pinNow, settle: 3)
        nativeFormatPin = pin; nativeRecordingFormat = value
        let functionMode = backend.functionMode
        let label = MonitorCapturePresentation.recordingLabel(CameraRecordingFormat(
            dimensions: .init(width: value.width, height: value.height), frameRate: Rational.frameRate(value.framesPerSecond))) ?? "Format"
        sendControl(label, { try LunaProtocol.setRecordResolution(value.rawValue, functionMode: functionMode) },
            through: target, suppliedAdmission: admission, onFail: { [weak self] in
                guard let self, self.lunaSession === target, self.nativeFormatPin?.id == pin.id else { return }
                self.nativeFormatPin = nil; self.nativeRecordingFormat = previous
            })
        if let previousRate, let targetRate = Rational.frameRate(value.framesPerSecond),
            case .shutter(.duration)? = control.snapshot?.value(of: .shutter).value,
            let rematch = ShutterAngle.formatRematch(degrees: OperatorPrefs.shutterAngleDegrees,
                usesAngle: OperatorPrefs.shutterUsesAngle,
                manual: control.snapshot?.exposureProgram.value == .manual, isPhoto: status.isPhoto,
                previousFps: Int(previousRate.rounded()), nextFps: Int(targetRate.doubleValue.rounded()),
                available: status.availableShutterDenoms),
            rematch.denom != status.shutterDenom {
            setShutterDenom(rematch.denom)
        }
    }

    func setNativeRecordingColor(_ value: LunaColorMode) {
        guard canSendControl, currentShootingMode != nil, LunaColorMode.nativeRecordingChoices.contains(value),
            let target = lunaSession, target.current.recording.value == .idle else { return }
        let admission = LunaCommandAdmission(owner: target.commandOwner, isCurrent: { true })
        let previous = nativeRecordingColor
        let pin = CameraValuePin(value, now: pinNow, settle: 3)
        nativeColorPin = pin; nativeRecordingColor = value
        let functionMode = backend.functionMode
        sendControl(value.label, { try LunaProtocol.setColorMode(value, functionMode: functionMode) },
            through: target, suppliedAdmission: admission, onFail: { [weak self] in
                guard let self, self.lunaSession === target, self.nativeColorPin?.id == pin.id else { return }
                self.nativeColorPin = nil; self.nativeRecordingColor = previous
            })
    }

    func setVideoFormat(
        resolution: VideoResolution, frameRate: VideoFrameRate, fromOperator: Bool = true
    ) {
        guard canSendControl else { return }
        guard currentShootingMode?.offersVideoFormat != false else { return }
        guard !status.isRecording else {
            controlNote = ControlHud.recordingColorLockNote
            return
        }
        let format = VideoFormat(resolution: resolution, frameRate: frameRate)
        guard let raw = formatTable[format] else {
            controlNote = "\(format.chipLabel) is not available in this mode."
            return
        }
        let previousStatus = status
        let previous = previousStatus.videoFormat
        pins.format = CameraValuePin(format, now: pinNow, settle: 3)
        var next = status
        next.videoFormat = format
        next.videoResolution = resolution
        next.fps = frameRate.fps
        status = next
        let mode = backend.functionMode
        sendControl(
            format.chipLabel, { try LunaProtocol.setRecordResolution(raw, functionMode: mode) },
            onFail: { [weak self] in
                guard let self else { return }
                self.pins.format = nil
                self.status.videoFormat = previous
                self.status.videoResolution = previous?.resolution
                self.status.fps = previous?.frameRate.fps ?? self.status.fps
            })
        // The shared rematch policy requires known manual video exposure and a reported cadence.
        if let rematch = ShutterAngle.formatRematch(
            degrees: OperatorPrefs.shutterAngleDegrees,
            usesAngle: OperatorPrefs.shutterUsesAngle,
            manual: previousStatus.expoMode == .manual,
            isPhoto: currentShootingMode?.isPhoto != false,
            previousFps: previousStatus.fps, nextFps: frameRate.fps,
            available: previousStatus.availableShutterDenoms),
            rematch.denom != previousStatus.shutterDenom
        {
            setShutterDenom(rematch.denom)
        }
    }

    func setColorMode(_ mode: ColorMode) {
        setColorMode(mode, suppliedAdmission: nil)
    }

    @discardableResult
    func setColorMode(
        _ mode: ColorMode, admission: LunaCommandAdmission
    ) -> Task<Void, Never>? {
        setColorMode(mode, suppliedAdmission: admission)
    }

    @discardableResult
    private func setColorMode(
        _ mode: ColorMode, suppliedAdmission admission: LunaCommandAdmission?
    ) -> Task<Void, Never>? {
        let target: LunaCameraSession?
        if let admission {
            guard let captured = lunaSession, admission.admits(captured.commandOwner) else { return nil }
            target = captured
        } else { target = nil }
        guard canSendControl else { return nil }
        if status.isRecording, mode != status.colorMode {
            controlNote = ControlHud.recordingColorLockNote
            return nil
        }
        guard colorModes.contains(mode) else { return nil }
        let previous = status.colorMode
        let pin = CameraValuePin(mode, now: pinNow, settle: 3)
        pins.color = pin
        status.colorMode = mode
        applyDecoderColorScience()
        let luna = LunaShellMapping.lunaColorMode(mode)
        let functionMode = backend.functionMode
        return sendControl(
            mode.label(in: profile), { try LunaProtocol.setColorMode(luna, functionMode: functionMode) },
            through: target, suppliedAdmission: admission,
            onFail: { [weak self] in
                guard let self else { return }
                if admission != nil {
                    guard self.lunaSession === target, self.pins.color?.id == pin.id else { return }
                }
                self.pins.color = nil
                self.status.colorMode = previous
                self.applyDecoderColorScience()
            }, onUnsent: { [weak self] in
                guard let self, self.lunaSession === target, self.pins.color?.id == pin.id else { return }
                self.pins.color = nil
                self.status.colorMode = previous
                self.applyDecoderColorScience()
            })
    }

    // MARK: - Zoom (Luna option 53, a plain factor)

    var zoomStops: [Double] {
        var stops = LunaShellMapping.zoomChips.filter { $0 <= zoomCeiling }
        if let last = stops.last, zoomCeiling > last + 0.5 { stops.append(zoomCeiling) }
        return stops
    }
    var zoomMax: Double { zoomStops.last ?? 1 }

    var zoomReadout: Double {
        CamFov.readout(
            live: status.zoomFactor, preview: zoomPinchPreview, fallback: zoomStop,
            optimistic: zoomOptimistic, ceiling: zoomCeiling)
    }

    var zoomDialReadout: Double {
        CamFov.continuousReadout(
            live: status.zoomFactor, preview: zoomPinchPreview, fallback: zoomStop,
            optimistic: zoomOptimistic, ceiling: zoomCeiling)
    }

    func updateZoomPinch(magnification: Double) {
        guard supportsZoom, !isLocked else { return }
        if zoomPinchPreview == nil {
            zoomPinchAnchor = status.zoomFactor ?? zoomOptimistic ?? zoomStop
            zoomPin = nil
        }
        let factor = min(max(zoomPinchAnchor * magnification, 1), zoomMax)
        zoomPinchPreview = factor
        queueZoomWrite(factor)
    }

    func endZoomPinch() {
        if let preview = zoomPinchPreview {
            zoomStop = preview
            zoomPin = CameraValuePin(preview, now: Date.timeIntervalSinceReferenceDate)
            queueZoomWrite(preview)
        }
        zoomPinchPreview = nil
    }

    func setZoom(_ factor: Double) {
        setZoom(factor, suppliedAdmission: nil)
    }

    func setZoom(_ factor: Double, admission: LunaCommandAdmission) {
        setZoom(factor, suppliedAdmission: admission)
    }

    private func setZoom(_ factor: Double, suppliedAdmission admission: LunaCommandAdmission?) {
        if let admission {
            guard let target = lunaSession, admission.admits(target.commandOwner) else { return }
        }
        guard supportsZoom else { return }
        guard !isLocked else {
            controlNote = "Zoom locked"
            return
        }
        let target = min(max(factor, 1), zoomMax)
        zoomPinchPreview = nil
        zoomPin = CameraValuePin(target, now: Date.timeIntervalSinceReferenceDate)
        zoomStop = target
        controlNote = "Zoom \(CamFov.displayLabel(factor: target, ceiling: zoomCeiling))"
        queueZoomWrite(target, suppliedAdmission: admission)
    }

    func setZoomSlider(_ factor: Double) {
        setZoomSlider(factor, suppliedAdmission: nil)
    }

    func setZoomSlider(_ factor: Double, admission: LunaCommandAdmission) {
        setZoomSlider(factor, suppliedAdmission: admission)
    }

    private func setZoomSlider(_ factor: Double, suppliedAdmission admission: LunaCommandAdmission?) {
        if let admission {
            guard let target = lunaSession, admission.admits(target.commandOwner) else { return }
        }
        guard !isLocked else { return }
        queueZoomWrite(min(max(factor, 1), zoomMax), suppliedAdmission: admission)
    }

    /// DJI slew has no Luna equivalent; the hold disc drives absolute factors.
    func setZoomSlew(_ value: UInt16) {}
    func setZoomStop() {}

    /// Latest-wins at ~12 Hz: the camera lens cannot follow a 60 Hz pinch.
    private func queueZoomWrite(_ factor: Double) {
        queueZoomWrite(factor, suppliedAdmission: nil)
    }

    private func queueZoomWrite(_ factor: Double, suppliedAdmission admission: LunaCommandAdmission?) {
        let target: LunaCameraSession?
        if let admission {
            guard let captured = lunaSession, admission.admits(captured.commandOwner) else { return }
            target = captured
        } else { target = nil }
        guard case .live = phase, hasControlLink else { return }
        pendingZoomWrite = .init(factor: factor, session: target, admission: admission)
        guard zoomWriteTask == nil else { return }
        zoomWriteRevision &+= 1
        let revision = zoomWriteRevision
        zoomWriteTask = Task { @MainActor [weak self] in
            while let self, self.zoomWriteRevision == revision, !Task.isCancelled,
                let next = self.pendingZoomWrite
            {
                self.pendingZoomWrite = nil
                _ = await self.submitLens(.zoom(next.factor), through: next.session, admission: next.admission)
                try? await Task.sleep(for: .milliseconds(80))
            }
            guard let self, self.zoomWriteRevision == revision else { return }
            self.zoomWriteTask = nil
            self.scheduleSettingsRefresh()
        }
    }

    /// Preserves the app's existing lens pacing while using the connection's common receipts.
    /// Product Showcase stays on the integration-owned extension above.
    private func submitLens(
        _ value: OpenCineCore.SettingValue, through session: LunaCameraSession? = nil,
        admission: LunaCommandAdmission? = nil
    ) async -> Bool {
        guard let common = session ?? backend.session else { return false }
        let source = admission.map { _ in LunaCommandAdmission(owner: common.commandOwner, isCurrent: { true }) }
        let epoch = common.current.epoch
        let command = CameraCommand(.set(value), preconditions: CommandPreconditions(common.current))
        let receipt: CommandReceipt
        if let admission {
            guard session != nil, admission.admits(common.commandOwner) else { return false }
            receipt = await common.submit(command, admission: admission)
        } else {
            receipt = await common.submit(command)
        }
        if let admission {
            guard lunaSession === common, source?.source == admission.source,
                source?.admits(common.commandOwner) == true, common.current.epoch == epoch
            else { return false }
        }
        switch receipt.stage {
        case .accepted, .awaitingObservation, .confirmed:
            if let source { scheduleSettingsRefresh(through: common, source: source, epoch: epoch) }
            else { scheduleSettingsRefresh() }
            return true
        default:
            noteCommandFailure()
            controlNote = "\(value.key == .zoom ? "Zoom" : "Focus") was not applied by the camera."
            return false
        }
    }

    // MARK: - Gimbal

    var canSetGimbalConfiguration: Bool {
        hasGimbal && !isLocked && phase == .live && gimbalControlSceneActive && !holdsMonitor
            && !sessionRecovery.isRecovering && hasControlLink
    }

    /// Stream MOVE while the on-screen stick is held. `x`/`y` are −1…1 (right / up).
    func updateGimbalStick(
        x: Double, y: Double, sensitivity: Int = GimbalStick.defaultSensitivity,
        assistMirror: Bool = false, linear: Bool = false,
        mapping: GimbalStick.Mapping = .defaults
    ) {
        guard !isLocked, canSetGimbalConfiguration else {
            endGimbalStick(cancelMove: true)
            return
        }
        // The operator's stick always wins over an aim or a programmed move.
        if x != 0 || y != 0 {
            stopGimbalAim()
            if gimbalMoveRunning { cancelProgrammedMove() }
        }
        let dead = linear ? GimbalStick.deadzone : mapping.deadzone
        let magnitude = hypot(x, y)
        let scale = min(1, Double(sensitivity) / Double(GimbalStick.defaultSensitivity))
        var panValue = magnitude < dead ? 0 : x
        let tiltValue = magnitude < dead ? 0 : y
        if assistMirror { panValue = -panValue }
        // Ease-in curve: fine control near centre, full speed at the rim.
        func shaped(_ v: Double) -> Double { (linear ? v : v * abs(v)) * scale }
        gimbalStick.lastPan = panValue
        gimbalStick.lastTilt = tiltValue
        if !gimbalStick.isHeld {
            gimbalStick.isHeld = true
            ControlLiveLog.line("control: gimbal stick stream")
        }
        motion.hold(pan: shaped(panValue), tilt: shaped(tiltValue))
    }

    func endGimbalStick(cancelMove: Bool = false) {
        guard gimbalStick.isHeld else { return }
        gimbalStick.reset()
        motion.endHold()
        ControlLiveLog.line("control: gimbal stick rest")
        guard hasControlLink else { return }
        Task { [weak self] in await self?.motion.release() }
    }

    func performGimbalDoubleTap() {
        switch gimbalDoubleTap {
        case .recenter: recenterGimbal()
        case .level: levelGimbalToWorld()
        }
    }

    /// Level tilts the head to the world horizon, keeping yaw. SET_ANGLE is handle
    /// relative, so the target is the current handle pitch minus the head's IMU
    /// gravity pitch.
    func levelGimbalToWorld(refine: Bool = true) {
        let now = ProcessInfo.processInfo.systemUptime
        guard let reading = gimbalAngle, now - reading.at <= 0.5,
            let imuAt = lastIMUAt, now - imuAt <= 0.3, gimbalPose.sampleCount > 0
        else {
            controlNote = WorldLevelSnap.noLevelData
            return
        }
        let pitch = Double(reading.angle.pitch) - gimbalPose.pitchDeg
        aimGimbal(
            at: GimbalWaypoint(
                yawDeg: GimbalWaypoint.unwrapYaw(Double(reading.angle.yaw)), pitchDeg: pitch, zoom: zoomReadout,
                nativePitchDeg: -pitch))
        guard refine else { return }
        // The IMU pitch filter lags a recent move by ~0.5°: correct once from still.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self, self.gimbalAim == nil, !self.gimbalStick.isHeld, !self.gimbalMoveRunning,
                abs(self.gimbalPose.pitchDeg) > 0.3
            else { return }
            self.levelGimbalToWorld(refine: false)
        }
    }

    func recenterGimbal() {
        guard canSetGimbalConfiguration else { return }
        endGimbalStick(cancelMove: true)
        stopGimbalAim()
        sendControl(
            "Gimbal recenter", { try LunaProtocol.gimbalRecenterRequest() }, refresh: false,
            onSuccess: { [weak self] _ in
                // Recenter points the head at the handle's forward: that is yaw 0.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(1.5))
                    self?.gimbalPose.zeroYaw()
                }
            })
        controlNote = "Gimbal re-centered"
    }

    // MARK: - Absolute angle (cmd 226 SET_ANGLE / GET_ANGLE)

    /// GET_ANGLE poll while live: one small request per 100 ms is fresh enough for
    /// waypoints and head-track centring.
    static let gimbalAnglePollInterval: Duration = .milliseconds(100)
    /// SET_ANGLE stream period for moving targets (head tracking, programmed moves).
    /// fw 1.1.15: 30 Hz follows a moving target with ~60 ms lag and is visibly smoother
    /// than 20 Hz (~70 ms) or 10 Hz (~120 ms, steppy).
    static let gimbalSetInterval: Duration = .milliseconds(33)

    func startGimbalAnglePoll() {
        gimbalAnglePoll?.cancel()
        gimbalAnglePoll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Head tracking reads GET_ANGLE itself on every tick.
                if case .live = self.phase, self.hasControlLink, !self.isSteeringHead {
                    await self.readGimbalAngle()
                }
                try? await Task.sleep(for: Self.gimbalAnglePollInterval)
            }
        }
    }

    @discardableResult
    func readGimbalAngle(timeout: Duration = .seconds(1)) async -> LunaGimbalAngle? {
        guard let angle = await motion.readAngle(timeout: timeout) else { return nil }
        gimbalAngle = (angle, ProcessInfo.processInfo.systemUptime)
        return angle
    }

    /// Fire and forget: the camera re-targets on every SET_ANGLE (latest wins).
    func sendGimbalAngle(_ target: GimbalWaypoint) {
        Task { [weak self] in await self?.motion.aim(at: target) }
    }

    #if DEBUG
        /// Head-track recorder: 10 ms bins of camera-head rate (deg/s) from the gyro.
        func logIMU(_ samples: [LunaIMUSample]) {
            guard !headTrackLog.isEmpty || headTrackRecording else { return }
            let end = ProcessInfo.processInfo.systemUptime
            let stride = 10
            for start in Swift.stride(from: 0, to: samples.count, by: stride) {
                let slice = samples[start..<min(start + stride, samples.count)]
                let yaw = slice.reduce(0) { $0 + $1.gyro.z } / Double(slice.count) * 180 / .pi
                let pitch = slice.reduce(0) { $0 + $1.gyro.y } / Double(slice.count) * 180 / .pi
                let age = Double(samples.count - start) / 1000
                imuRateLog.append([end - age, yaw, pitch])
            }
            if imuRateLog.count > 6000 { imuRateLog.removeFirst(1000) }
        }
    #endif

    func ingestIMU(_ samples: [LunaIMUSample]) {
        #if DEBUG
            logIMU(samples)
        #endif
        gimbalPose.ingest(samples, commanding: gimbalStick.isHeld || gimbalAim != nil || gimbalMoveRunning)
        lastIMUAt = ProcessInfo.processInfo.systemUptime
    }

    /// Point the head at `target` (handle frame) with one SET_ANGLE, which the camera
    /// plans as a single smooth move. Ends once GET_ANGLE reads within 0.5°, or after 8 s.
    @discardableResult
    func aimGimbal(at target: GimbalWaypoint) -> UInt64? {
        guard canSetGimbalConfiguration, !gimbalStick.isHeld, !gimbalMoveRunning else { return nil }
        gimbalAimGeneration &+= 1
        let token = gimbalAimGeneration
        gimbalAim = (target, token)
        gimbalAimTask?.cancel()
        gimbalAimTask = Task { @MainActor [weak self] in
            var sent: GimbalWaypoint?
            let started = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                guard let self, let aim = self.gimbalAim, aim.token == token,
                    self.canSetGimbalConfiguration, !self.gimbalStick.isHeld
                else { break }
                if aim.target != sent {
                    self.sendGimbalAngle(aim.target)
                    sent = aim.target
                }
                let now = ProcessInfo.processInfo.systemUptime
                if now - started > 8 { break }
                if now - started > 0.3, let reading = self.gimbalAngle, reading.at > started + 0.2,
                    LunaMotionService.hasReached(reading.angle, aim.target)
                { break }
                try? await Task.sleep(for: Self.gimbalSetInterval)
            }
            self?.finishGimbalAim(token: token)
        }
        return token
    }

    /// Head tracking steers with the stick (`LunaHeadTrackSteering`): each tick reads
    /// GET_ANGLE, then sends the stick toward the AirPods head.
    private func steerHeadTrack(token: UInt64) async {
        isSteeringHead = true
        // Angles are read back to back beside the loop, so a slow or lost reply never
        // holds the loop (the head would coast on the last stick value meanwhile).
        let reader = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self, self.isSteeringHead {
                if await self.readGimbalAngle(timeout: .milliseconds(250)) == nil {
                    try? await Task.sleep(for: .milliseconds(20))
                }
            }
        }
        defer {
            isSteeringHead = false
            reader.cancel()
        }
        var steering = LunaHeadTrackSteering(now: ProcessInfo.processInfo.systemUptime)
        while !Task.isCancelled {
            guard let aim = gimbalAim, aim.token == token, canSetGimbalConfiguration, !gimbalStick.isHeld
            else { break }
            let now = ProcessInfo.processInfo.systemUptime
            let tuning = LunaHeadTrackSteering.Tuning(
                panDegPerSec: Self.stickPanDegPerSec, tiltDegPerSec: Self.stickTiltDegPerSec,
                gain: Self.headTrackGain, accelFeed: Self.headTrackAccelFeed)
            var pan: Int32 = 0
            var tilt: Int32 = 0
            // No reading for 0.3 s: stop rather than steer blind.
            if let reading = gimbalAngle, now - reading.at < 0.3 {
                let head =
                    OpenInstaViewCore.HeadTrack.reference(headTrackSamples, at: now + Self.headTrackLead, fitWindow: Self.headTrackFitWindow)
                    ?? OpenInstaViewCore.HeadTrack.Reference(yaw: aim.target.yawDeg, pitch: aim.target.pitchDeg)
                let step = steering.step(
                    yaw: GimbalWaypoint.unwrapYaw(Double(reading.angle.yaw)), pitch: Double(reading.angle.pitch),
                    readAt: reading.at, toward: head, now: now, tuning: tuning)
                pan = step.pan
                tilt = step.tilt
                #if DEBUG
                    headTrackLog.append([now, head.yaw, step.wantPitch, step.yaw, step.pitch, Double(pan), Double(tilt)])
                    if headTrackLog.count > 1500 { headTrackLog.removeFirst(300) }
                #endif
            }
            Task { [weak self, pan, tilt] in await self?.motion.steer(pan: pan, tilt: tilt) }
            steering.sent(pan: pan, tilt: tilt, now: now, tuning: tuning)
            try? await Task.sleep(for: .seconds(Self.headTrackTick))
        }
        // A fresh task: this one is usually cancelled here, and a cancelled send never goes
        // out, which left the head coasting on the last stick value.
        guard hasControlLink, gimbalAim?.token == token || gimbalAim == nil, !gimbalStick.isHeld else { return }
        // Again shortly after, in case a last MOVE still in flight lands behind the first.
        Task { @MainActor [weak self] in
            for attempt in 0..<2 {
                guard let self, attempt == 0 || (self.gimbalAim == nil && !self.gimbalStick.isHeld) else { return }
                await self.motion.release()
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    /// Live-tunable head tracking feel (debug remote `headTune`); defaults are the Luna's.
    nonisolated(unsafe) static var stickPanDegPerSec = LunaHeadTrackSteering.Tuning().panDegPerSec
    nonisolated(unsafe) static var stickTiltDegPerSec = LunaHeadTrackSteering.Tuning().tiltDegPerSec
    /// Pull toward the head's exact angle (1/s).
    nonisolated(unsafe) static var headTrackGain = LunaHeadTrackSteering.Tuning().gain
    /// How far ahead of the newest AirPods sample the head is aimed (covers link latency).
    nonisolated(unsafe) static var headTrackLead = 0.0
    nonisolated(unsafe) static var headTrackTick = 0.033
    nonisolated(unsafe) static var headTrackAccelFeed = LunaHeadTrackSteering.Tuning().accelFeed
    nonisolated(unsafe) static var headTrackFitWindow = 0.3

    private func finishGimbalAim(token: UInt64) {
        guard gimbalAim?.token == token else { return }
        gimbalAim = nil
        gimbalAimTask = nil
    }

    func stopGimbalAim() {
        guard let token = gimbalAim?.token else { return }
        gimbalAimTask?.cancel()
        finishGimbalAim(token: token)
    }

    func flipGimbal() {
        guard canSetGimbalConfiguration else { return }
        endGimbalStick(cancelMove: true)
        sendControl("Gimbal flip", { try LunaProtocol.gimbalFlipRequest() }, refresh: false)
    }

    func prepHeadTrackGimbal() {}

    func setGimbalMode(_ mode: GimbalMode) {
        guard canSetGimbalConfiguration else { return }
        let previous = gimbalMode
        pins.gimbalMode = CameraValuePin(mode, now: pinNow, settle: 3)
        gimbalMode = mode
        let luna = LunaShellMapping.lunaGimbalMode(mode)
        let functionMode = backend.functionMode
        sendControl(
            "Gimbal \(mode.label(in: profile))", { try LunaProtocol.setGimbalMode(luna, functionMode: functionMode) },
            onFail: { [weak self] in
                self?.pins.gimbalMode = nil
                self?.gimbalMode = previous
            })
    }

    func setGimbalSpeed(_ speed: GimbalSpeed) {
        guard canSetGimbalConfiguration else { return }
        let previous = gimbalSpeed
        pins.gimbalSpeed = CameraValuePin(speed, now: pinNow, settle: 3)
        gimbalSpeed = speed
        let luna = LunaShellMapping.lunaGimbalSpeed(speed)
        let functionMode = backend.functionMode
        sendControl(
            "Gimbal speed \(speed.label)",
            { try LunaProtocol.setGimbalFollowSpeed(luna, functionMode: functionMode) },
            onFail: { [weak self] in
                self?.pins.gimbalSpeed = nil
                self?.gimbalSpeed = previous
            })
    }

    // Head tracking: the shell hands over AirPods targets; `steerHeadTrack` follows them.
    func beginNativeHeadTrack() -> UInt64? {
        guard canSetGimbalConfiguration, !gimbalStick.isHeld, !gimbalMoveRunning,
            !isBrowsingMedia, !isLiveVideoStale, let live = freshGimbalWaypoint
        else { return nil }
        gimbalAimGeneration &+= 1
        let token = gimbalAimGeneration
        gimbalAim = (live, token)
        headTrackSamples = []
        gimbalAimTask?.cancel()
        gimbalAimTask = Task { @MainActor [weak self] in
            await self?.steerHeadTrack(token: token)
            self?.finishGimbalAim(token: token)
        }
        return token
    }

    /// `measuredAt` is the AirPods sample time (uptime); repeats of a sample are ignored.
    func updateNativeHeadTrack(target: GimbalWaypoint, token: UInt64, measuredAt: TimeInterval? = nil) -> Bool {
        guard let aim = gimbalAim, aim.token == token, !isBrowsingMedia, !isLiveVideoStale else {
            endNativeHeadTrack(token: token)
            return false
        }
        gimbalAim = (target, token)
        let t = measuredAt ?? ProcessInfo.processInfo.systemUptime
        if t > headTrackSamples.last?.t ?? -.infinity {
            headTrackSamples.append(OpenInstaViewCore.HeadTrack.Sample(t: t, yaw: target.yawDeg, pitch: target.pitchDeg))
            headTrackSamples.removeAll { t - $0.t > 1 }
            #if DEBUG
                headSampleLog.append([t, target.yawDeg, target.pitchDeg])
                if headSampleLog.count > 1500 { headSampleLog.removeFirst(300) }
            #endif
        }
        return true
    }

    func endNativeHeadTrack(token: UInt64) {
        guard gimbalAim?.token == token else { return }
        stopGimbalAim()
    }

    // MARK: - Programmed A·B·C moves (SET_ANGLE stream)

    func setGimbalWaypoint(_ slot: GimbalWaypointSlot) {
        guard hasGimbal, !isLocked else { return }
        guard !gimbalMoveRunning, !gimbalStick.isHeld else {
            controlNote = ControlHud.gimbalHoldStill
            return
        }
        guard let reading = gimbalAngle, ProcessInfo.processInfo.systemUptime - reading.at <= 0.3 else {
            controlNote = ControlHud.gimbalPoseNotReady
            return
        }
        let pitch = Double(reading.angle.pitch)
        gimbalProgram.setPoint(
            slot,
            GimbalWaypoint(
                yawDeg: GimbalWaypoint.unwrapYaw(Double(reading.angle.yaw)), pitchDeg: pitch,
                zoom: zoomReadout, nativePitchDeg: -pitch))
    }

    func clearGimbalWaypoint(_ slot: GimbalWaypointSlot) {
        cancelProgrammedMove()
        gimbalProgram[slot] = nil
    }

    func setGimbalLegDuration(ab: TimeInterval? = nil, bc: TimeInterval? = nil) {
        if gimbalMoveRunning { cancelProgrammedMove() }
        if let ab {
            let floor = GimbalProgram.minTravelDuration(from: gimbalProgram.a, to: gimbalProgram.b)
            gimbalProgram.durationAB = GimbalProgram.snapDuration(max(ab, floor))
        }
        if let bc {
            let floor = GimbalProgram.minTravelDuration(from: gimbalProgram.b, to: gimbalProgram.c)
            gimbalProgram.durationBC = GimbalProgram.snapDuration(max(bc, floor))
        }
    }

    func setGimbalSmoothness(_ value: Double) {
        guard value.isFinite else { return }
        cancelProgrammedMove()
        gimbalProgram.smoothness = min(1, max(0, value))
    }

    func clearGimbalProgram() {
        cancelProgrammedMove()
        gimbalProgram = GimbalProgram(
            durationAB: gimbalProgram.durationAB, durationBC: gimbalProgram.durationBC)
    }

    func setGimbalLoop(_ enabled: Bool) {
        cancelProgrammedMove()
        gimbalProgram.loop = enabled
    }

    // ponytail: lens zoom is not streamed with the move; add a zoom track when asked.
    var programmedZoomUnavailableReason: String? {
        gimbalProgram.changesZoom ? "Luna moves cannot change zoom. Set every point at one zoom." : nil
    }
    var supportsProgrammedMoves: Bool { true }
    var canRunProgrammedMove: Bool {
        programmedZoomUnavailableReason == nil && !isFeedWarming && !isLiveVideoStale
            && gimbalProgram.canRun
    }

    /// The shared owner executes the take; the adapter captures this connection and epoch.
    func runProgrammedMove() {
        guard gimbalControlSceneActive, hasGimbal, !isLocked else { return }
        if gimbalMoveRunning {
            cancelProgrammedMove()
            return
        }
        if let reason = programmedZoomUnavailableReason {
            controlNote = reason
            return
        }
        guard canRunProgrammedMove, gimbalAngle != nil else {
            controlNote = gimbalProgram.canRun ? ControlHud.gimbalPoseNotReady : ControlHud.programmedMoveNeedAB
            return
        }
        guard let source = programmedMoveSource() else {
            controlNote = "Connect the camera to use its controls."
            return
        }
        controlNote = nil
        stopGimbalAim()
        endGimbalStick(cancelMove: true)
        programmedMove.onChange = { [weak self] state in
            guard let self else { return }
            self.programmedMoveState = state
            if state.failure != nil {
                self.controlNote = "Programmed move was not applied by the camera."
                ControlLiveLog.line("gimbal-move: rejected")
            }
        }
        if !programmedMove.start(gimbalProgram, source: source, timing: LunaMotionService.programTiming) {
            controlNote = "Programmed move is unavailable for the current camera state."
        }
    }

    /// One immutable motion binding. Its wire service cannot look up a later backend session.
    func programmedMoveSource() -> MotionProgramSession.Source? {
        guard let session = lunaSession, session.admitsControl else { return nil }
        let epoch = session.current.epoch
        let generation = connectGeneration
        let isCurrent: @MainActor @Sendable () -> Bool = { [weak self] in
            guard let self else { return false }
            return self.lunaSession === session && self.connectGeneration == generation
                && self.phase == .live && self.gimbalControlSceneActive
                && session.admitsControl && session.current.epoch == epoch
        }
        let service = LunaMotionService(session: { isCurrent() ? session : nil })
        return MotionProgramSession.Source(motion: service, isCurrent: isCurrent)
    }

    func restartProgrammedMove() {
        guard gimbalControlSceneActive, !isLocked, gimbalMoveRunning, gimbalMovePaused else { return }
        cancelProgrammedMove()
        runProgrammedMove()
    }

    func pauseOrResumeProgrammedMove() {
        guard gimbalControlSceneActive, !isLocked, gimbalMoveRunning, gimbalMoveCanPause else { return }
        if gimbalMovePaused { _ = programmedMove.resume() }
        else { _ = programmedMove.pause() }
        controlNote = nil
    }

    func cancelProgrammedMove() {
        programmedMove.cancel()
        programmedMoveState = programmedMove.state
    }

    // MARK: - Focus and tracking

    /// Feed tap: inside a face box → Deep Track that face. A second tap on the same spot
    /// → Deep Track whatever is there. Anywhere else → tap-to-focus.
    func handleFeedTap(at normalized: CGPoint) {
        let x = min(max(Double(normalized.x), 0), 1)
        let y = min(max(Double(normalized.y), 0), 1)
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastFeedTap, Self.isDoubleTap(from: last, to: (now, x, y)) {
            lastFeedTap = nil
            startTracking(Self.doubleTapTrackBox(x: x, y: y))
            return
        }
        lastFeedTap = (now, x, y)
        if let box = FaceTrackTap.boxIfTapped(
            overlay: focusOverlay, x: x, y: y, sceneFaces: dimmedFaces)
        {
            startTracking(box)
            return
        }
        markFocus(at: CGPoint(x: x, y: y))
    }

    /// Second tap within the double-tap window and about a finger's width away.
    static func isDoubleTap(from first: (at: Double, x: Double, y: Double), to second: (at: Double, x: Double, y: Double))
        -> Bool
    {
        second.at - first.at <= GimbalStick.doubleTapWindow && hypot(second.x - first.x, second.y - first.y) <= 0.06
    }

    /// Double-tap Deep Track box: square on the 16:9 sensor, a fifth of the width, centred
    /// on the tap and kept inside the frame.
    static func doubleTapTrackBox(x: Double, y: Double) -> TrackingBox {
        let w = 0.2
        let h = w * 16 / 9
        return TrackingBox(
            x: min(max(x - w / 2, 0), 1 - w), y: min(max(y - h / 2, 0), 1 - h), width: w, height: h)
    }

    func markFocus(at normalized: CGPoint) {
        markFocus(at: normalized, suppliedAdmission: nil)
    }

    func markFocus(at normalized: CGPoint, admission: LunaCommandAdmission) {
        markFocus(at: normalized, suppliedAdmission: admission)
    }

    private func markFocus(at normalized: CGPoint, suppliedAdmission admission: LunaCommandAdmission?) {
        if let admission {
            guard let target = lunaSession, admission.admits(target.commandOwner) else { return }
        }
        guard supportsTapFocus else { return }
        if isTrackingActive {
            if let admission { cancelSubjectTracking(admission: admission) }
            else { cancelSubjectTracking() }
        }
        lastTapFocusAt = Date()
        faceBox = nil
        let x = min(max(Double(normalized.x), 0), 1)
        let y = min(max(Double(normalized.y), 0), 1)
        focusPoint = CGPoint(x: x, y: y)
        guard canSendControl else { return }
        do {
            if let admission {
                try subjectTracking.focus(x: x, y: y, admission: admission, finished: controlFinished("Focus", admission: admission))
            } else {
                try subjectTracking.focus(x: x, y: y, finished: controlFinished("Focus"))
            }
        } catch {
            controlNote = "Focus: \(error.localizedDescription)"
        }
    }

    /// Drag-to-track → Luna Deep Track (cmd 237) with the operator's rectangle.
    func startTracking(_ box: TrackingBox) {
        if box.isTooSmall {
            noteFrameTooSmall()
            return
        }
        guard canSendControl else { return }
        faceBox = nil
        do {
            try subjectTracking.start(
                .init(x: box.x, y: box.y, width: box.width, height: box.height),
                finished: controlFinished("Track"))
        } catch {
            controlNote = "Track: \(error.localizedDescription)"
        }
    }

    /// Stream-borne Deep Track state (media 0x85, every frame), read by the Luna owner. A
    /// tracking frame also drops the face box.
    func applyTrackFrame(_ frame: LunaTrackFrame) {
        if frame.state == .tracking { faceBox = nil }
        subjectTracking.ingest(frame)
    }

    /// The camera reports the end of tracking on notification 8315 (cancel).
    func applyTrackingState(_ state: UInt64) {
        subjectTracking.ingest(trackingState: state)
    }

    func cancelSubjectTracking() {
        subjectTracking.cancel(finished: controlFinished("Track clear"))
    }

    func cancelSubjectTracking(admission: LunaCommandAdmission) {
        subjectTracking.cancel(admission: admission, finished: controlFinished("Track clear", admission: admission))
    }

    func clearLocalTracking() {
        subjectTracking.clear()
    }

    func showTracking(_ snapshot: LunaSubjectTracking.Snapshot) {
        searchBox = snapshot.searchBox.map(TrackingBox.init)
        subjectBox = snapshot.subjectBox.map(TrackingBox.init)
        isTracking = snapshot.tracking
    }

    /// An owner-sent request's outcome, reported like `sendControl` without a settings refresh.
    func controlFinished(_ name: String) -> @MainActor @Sendable (Error?) -> Void {
        { [weak self] error in
            guard let self else { return }
            guard let error else {
                ControlLiveLog.line("control: \(name) ok")
                return
            }
            ControlLiveLog.line("control: \(name) failed \(error.localizedDescription)")
            self.noteCommandFailure()
            self.controlNote = "\(name) was not applied by the camera."
        }
    }

    /// Refusing an unsent supplied operation is not a camera failure. An entered outcome may
    /// still finish, but it publishes only to the same actual native source.
    func controlFinished(
        _ name: String, admission: LunaCommandAdmission
    ) -> @MainActor @Sendable (Error?) -> Void {
        let target = lunaSession
        let finish = controlFinished(name)
        return { [weak self] error in
            guard let self, let target, self.lunaSession === target,
                admission.source == target.commandOwner.source,
                !(error is LunaCommandAdmissionError)
            else { return }
            finish(error)
        }
    }

    func noteFrameTooSmall() {
        subjectTracking.clearBoxes()
        controlNote = "Frame Too Small"
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(ControlHud.toastHoldSeconds))
            guard let self, self.controlNote == "Frame Too Small" else { return }
            self.controlNote = nil
        }
    }

    func resetFocusPoint() {
        guard !isLocked else { return }
        markFocus(at: CGPoint(x: 0.5, y: 0.5))
    }

    var isFocusResetAvailable: Bool {
        FocusResetPolicy.isAvailable(
            x: Double(focusPoint.x), y: Double(focusPoint.y), tracking: isTrackingActive)
    }

    // MARK: - Gamepad

    func handleGamepadAction(_ action: GamepadOperatorAction) {
        switch action {
        case .record:
            guard !controlBusy else { return }
            pressShutter()
        case .recenter:
            performGimbalDoubleTap()
        case .flip:
            flipGimbal()
        case .track:
            handleGamepadTrackToggle()
        case .zoomChipIn:
            setZoom(CamFov.nextJump(from: zoomReadout, stops: zoomStops))
        case .zoomChipOut:
            setZoom(CamFov.previousJump(from: zoomReadout, stops: zoomStops))
        case .isoUp:
            nudgeISO(1)
        case .isoDown:
            nudgeISO(-1)
        case .shutterOpen:
            nudgeShutter(1)
        case .shutterClose:
            nudgeShutter(-1)
        }
    }

    private func nudgeISO(_ steps: Int) {
        guard let current = status.isoIndex,
            let next = IsoIndex.stepped(
                from: current, stops: steps, available: status.availableIsoIndices)
        else { return }
        setISO(next)
    }

    private func nudgeShutter(_ steps: Int) {
        guard
            let next = CamCapShutter.steppedDenom(
                from: status.shutterDenom, steps: steps, available: status.availableShutterDenoms)
        else { return }
        setShutterDenom(next)
    }

    func handleGamepadTrackToggle() {
        guard !isLocked else { return }
        switch GamepadFaceTrack.action(
            trackingActive: isTrackingActive, overlay: focusOverlay, sceneFaces: sceneFaces)
        {
        case .cancel: cancelSubjectTracking()
        case .track(let box): startTracking(box)
        case .none: break
        }
    }
}

/// Coalesces rapid drum edits into one send per key per ~120 ms (latest wins). One per session.
@MainActor
final class LunaExposureCoalescer {
    private var pending: [String: () -> Void] = [:]
    private var scheduled: Set<String> = []

    func submit(key: String, _ work: @escaping () -> Void) {
        pending[key] = work
        guard scheduled.insert(key).inserted else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            self.scheduled.remove(key)
            let work = self.pending.removeValue(forKey: key)
            work?()
        }
    }
}

@MainActor
final class LunaRefreshDebounce {
    private var task: Task<Void, Never>?

    func schedule(_ work: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await work()
        }
    }
}

// MARK: - Timecode

extension CameraSession {
    /// The Luna's timecode is time of day from its own clock, which the phone app is
    /// expected to set (the camera's "Sync system time" asks for the app).
    func syncCameraClock() {
        frameTimecode.reset()
        Task { @MainActor [weak self] in
            guard let session = self?.lunaSession, await session.syncClock() else { return }
            ControlLiveLog.line("luna: camera clock synced")
        }
    }

    /// Timecode of the live frame just received. The HUD shows HH:MM:SS, so the status only
    /// changes once a second.
    func noteFrameClock(_ milliseconds: UInt64) {
        #if DEBUG
            lastFrameClock = milliseconds
        #endif
        guard
            let timecode = frameTimecode.note(
                frameClock: milliseconds, arrival: Date().timeIntervalSince1970,
                timeZoneSeconds: TimeZone.current.secondsFromGMT())
        else { return }
        lunaSession?.ingest(timecode: timecode)
    }
}
