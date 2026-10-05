import CoreGraphics
import Foundation
import Insta360Apple
import Insta360Protocol
import OpenCineCore
import OpenPocketViewCore

/// Held gimbal stick streamed as Luna `GIMBAL_CONTROL` MOVE (cmd 226) at a fixed rate.
struct LunaStickStream {
    /// Official app range: sint32 ±99 on each VirtualRC axis.
    static let fullScale = 99.0
    static let interval: Duration = .milliseconds(50)
    var pan: Int32 = 0
    var tilt: Int32 = 0
    var lastPan = 0.0
    var lastTilt = 0.0
    var isHeld = false
    var task: Task<Void, Never>?

    mutating func reset() {
        task?.cancel()
        task = nil
        pan = 0
        tilt = 0
        lastPan = 0
        lastTilt = 0
        isHeld = false
    }
}

extension CameraSession {
    // MARK: - Capabilities

    var hasGimbal: Bool { true }
    var supportsZoom: Bool { true }
    var supportsTapFocus: Bool { true }
    /// AF-C, AF-S and Product Showcase (option 93); see `LunaShellMapping.focusOptions`.
    var supportsFocusMode: Bool { true }
    /// Matrix / Face Priority metering (option 46), shown in the Exposure sheet.
    var supportsFaceMetering: Bool { true }
    var supportsAperture: Bool { false }
    /// Luna sends no metered EV; the EV meter reads the picture.
    var reportsMeteredEV: Bool { false }
    /// Auto ISO ceiling and native-ISO hop are Osmo camcap features; Luna has neither.
    var supportsIsoLimit: Bool { false }
    /// DJI camcap hop to the log curve's native ISO on a color change; the ISO sheet hides its toggle.
    var supportsNativeIsoHop: Bool { false }
    /// Luna media browse runs over HTTP next to the live socket.
    /// The connection's Luna session: every request goes through it, and its admission is this
    /// facade's control link (it flips with the backend's handshake). Tests set the override.
    var lunaSession: LunaCameraSession? { lunaSessionOverride ?? backend.session }
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

    /// Sends one Luna request off the main flow. Failure reverts through `onFail`.
    func sendControl(
        _ name: String, _ build: () throws -> LunaRequest, refresh: Bool = true,
        onFail: (@MainActor () -> Void)? = nil, onSuccess: (@MainActor (Data) -> Void)? = nil
    ) {
        let request: LunaRequest
        do { request = try build() } catch {
            controlNote = "\(name): \(error.localizedDescription)"
            onFail?()
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let reply = try await self.sendLuna(request)
                ControlLiveLog.line("control: \(name) ok")
                onSuccess?(reply)
                if refresh { self.scheduleSettingsRefresh() }
            } catch {
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

    private var pinNow: TimeInterval { Date.timeIntervalSinceReferenceDate }

    // MARK: - Record / photo

    /// Rec lamp: start/stop video, or take a still in Photo. Record never lies: the
    /// lamp holds `controlBusy` until the Core session reports the outcome.
    func pressShutter() {
        guard canSendControl else { return }
        guard currentShootingMode?.isPhoto == true else {
            toggleRecording()
            return
        }
        controlBusy = true
        pins.photoInFlight = true
        controlNote = "Photo"
        sendControl(
            "Photo", { try LunaProtocol.takePicture(mode: .normal) }, refresh: false,
            onFail: { [weak self] in
                self?.pins.photoInFlight = false
                self?.controlBusy = false
            },
            onSuccess: { [weak self] _ in
                self?.pins.photoInFlight = false
                self?.controlBusy = false
                Task { await self?.refreshMediaAfterCapture() }
            })
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

    func setFocusMode(_ mode: OpenPocketViewCore.FocusMode) {
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
        guard canSendControl else { return }
        pins.faceMetering = CameraValuePin(on, now: pinNow, settle: 6)
        faceMetering = on
        let mode = backend.functionMode
        sendControl(
            on ? "Metering Face" : "Metering Matrix",
            { try LunaProtocol.setFaceMetering(on, functionMode: mode) },
            onFail: { [weak self] in self?.pins.faceMetering = nil })
    }

    // MARK: - Aperture, audio (not exposed by Luna's phone protocol)

    func setApertureStrategy(_ strategy: ApertureStrategy) {}
    func setAudioChannel(_ channel: AudioChannel) {}
    func setVocalBoost(_ boost: VocalBoost) {}
    func setWindNR(_ value: WindNoiseReduction) {}
    func setDirectionalAudio(_ value: DirectionalAudio) {}
    func refreshFocusTrack() async {}
    func clearGlamourIfEnabled() async {}
    func refreshAudioState() async {}

    // MARK: - Format and color

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
        let previous = status.videoFormat
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
        // Angle mode is ours: keep the chosen degrees and rewrite 1/N for the new fps.
        if OperatorPrefs.shutterUsesAngle, previous?.frameRate != frameRate, status.expoMode != .auto {
            let denom = ShutterAngle.denom(
                degrees: OperatorPrefs.shutterAngleDegrees, fps: frameRate.fps,
                available: status.availableShutterDenoms)
            if denom != status.shutterDenom { setShutterDenom(denom) }
        }
    }

    func setColorMode(_ mode: ColorMode) {
        guard canSendControl else { return }
        if status.isRecording, mode != status.colorMode {
            controlNote = ControlHud.recordingColorLockNote
            return
        }
        guard colorModes.contains(mode) else { return }
        let previous = status.colorMode
        pins.color = CameraValuePin(mode, now: pinNow, settle: 3)
        status.colorMode = mode
        applyDecoderColorScience()
        let luna = LunaShellMapping.lunaColorMode(mode)
        let functionMode = backend.functionMode
        sendControl(
            mode.label(in: profile), { try LunaProtocol.setColorMode(luna, functionMode: functionMode) },
            onFail: { [weak self] in
                self?.pins.color = nil
                self?.status.colorMode = previous
                self?.applyDecoderColorScience()
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
        queueZoomWrite(target)
    }

    func setZoomSlider(_ factor: Double) {
        guard !isLocked else { return }
        queueZoomWrite(min(max(factor, 1), zoomMax))
    }

    /// DJI slew has no Luna equivalent; the hold disc drives absolute factors.
    func setZoomSlew(_ value: UInt16) {}
    func setZoomStop() {}

    /// Latest-wins at ~12 Hz: the camera lens cannot follow a 60 Hz pinch.
    private func queueZoomWrite(_ factor: Double) {
        guard case .live = phase, hasControlLink else { return }
        pendingZoomWrite = factor
        guard zoomWriteTask == nil else { return }
        zoomWriteTask = Task { @MainActor [weak self] in
            while let self, let next = self.pendingZoomWrite {
                self.pendingZoomWrite = nil
                _ = await self.submitLens(.zoom(next))
                try? await Task.sleep(for: .milliseconds(80))
            }
            self?.zoomWriteTask = nil
            self?.scheduleSettingsRefresh()
        }
    }

    /// Preserves the app's existing lens pacing while using the connection's common receipts.
    /// Product Showcase stays on the integration-owned extension above.
    private func submitLens(
        _ value: OpenCineCore.SettingValue, through session: LunaCameraSession? = nil
    ) async -> Bool {
        guard let common = session ?? backend.session else { return false }
        let receipt = await common.submit(
            CameraCommand(.set(value), preconditions: CommandPreconditions(common.current)))
        switch receipt.stage {
        case .accepted, .awaitingObservation, .confirmed:
            scheduleSettingsRefresh()
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
        func shaped(_ v: Double) -> Int32 {
            let curved = linear ? v : v * abs(v)
            return Int32((curved * scale * LunaStickStream.fullScale).rounded())
        }
        gimbalStick.pan = shaped(panValue)
        gimbalStick.tilt = shaped(tiltValue)
        gimbalStick.lastPan = panValue
        gimbalStick.lastTilt = tiltValue
        if !gimbalStick.isHeld {
            gimbalStick.isHeld = true
            ControlLiveLog.line("control: gimbal stick stream")
            startStickStream()
        }
    }

    private func startStickStream() {
        gimbalStick.task?.cancel()
        gimbalStick.task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.gimbalStick.isHeld else { return }
                let pan = self.gimbalStick.pan
                let tilt = self.gimbalStick.tilt
                if let request = try? LunaProtocol.gimbalMove(upDown: tilt, leftRight: pan) {
                    _ = try? await self.sendLuna(request, timeout: .seconds(2))
                }
                try? await Task.sleep(for: LunaStickStream.interval)
            }
        }
    }

    func endGimbalStick(cancelMove: Bool = false) {
        guard gimbalStick.isHeld else { return }
        gimbalStick.reset()
        ControlLiveLog.line("control: gimbal stick rest")
        guard hasControlLink else { return }
        Task { [weak self] in _ = try? await self?.sendLuna(LunaProtocol.gimbalReleaseRequest()) }
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
    /// fw 1.1.15 reach: pitch -57.3...+90; yaw is one arc from about -125 through ±180
    /// to -58.5 (gap centred near -92, like the shell's `HeadTrack.Reach`), and SET_ANGLE
    /// takes yaw in -180...180 and routes around the stop itself. Declared once in
    /// `LunaCameraSession.motion`.
    static let gimbalPitchRange = LunaCameraSession.motion.bounds.tilt

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
        guard let request = try? LunaProtocol.gimbalGetAngleRequest(),
            let reply = try? await sendLuna(request, timeout: timeout),
            let angle = try? LunaGimbalAngle(response: reply)
        else { return nil }
        gimbalAngle = (angle, ProcessInfo.processInfo.systemUptime)
        return angle
    }

    /// Fire and forget: the camera re-targets on every SET_ANGLE (latest wins).
    func sendGimbalAngle(_ target: GimbalWaypoint) {
        let yaw = remainder(target.yawDeg, 360)  // unwrapped shell yaw back to ±180
        let pitch = min(max(target.pitchDeg, Self.gimbalPitchRange.lowerBound), Self.gimbalPitchRange.upperBound)
        guard let request = try? LunaProtocol.gimbalSetAngle(pitch: Float(pitch), yaw: Float(yaw))
        else { return }
        Task { [weak self] in _ = try? await self?.sendLuna(request, timeout: .seconds(2)) }
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
                    abs(remainder(Double(reading.angle.yaw) - aim.target.yawDeg, 360)) <= 0.5,
                    abs(Double(reading.angle.pitch) - aim.target.pitchDeg) <= 0.5
                { break }
                try? await Task.sleep(for: Self.gimbalSetInterval)
            }
            self?.finishGimbalAim(token: token)
        }
        return token
    }

    /// Head tracking steers with the stick (MOVE), not SET_ANGLE: fw 1.1.15 re-plans every
    /// SET as its own start-stop move, so a SET stream judders at the send rate (about 11
    /// deg/s rms at 30 Hz against 0.05 for the stick). Each tick reads GET_ANGLE, then
    /// commands the head's own rate plus a pull toward its exact angle.
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
        var rate = (yaw: 0.0, pitch: 0.0)  // modelled camera rate from the sent stick
        var last = ProcessInfo.processInfo.systemUptime
        while !Task.isCancelled {
            guard let aim = gimbalAim, aim.token == token, canSetGimbalConfiguration, !gimbalStick.isHeld
            else { break }
            let now = ProcessInfo.processInfo.systemUptime
            var pan: Int32 = 0
            var tilt: Int32 = 0
            // No reading for 0.3 s: stop rather than steer blind.
            if let reading = gimbalAngle, now - reading.at < 0.3 {
                let head = Self.headTrackReference(headTrackSamples, at: now + Self.headTrackLead)
                    ?? HeadTrackReference(yaw: aim.target.yawDeg, pitch: aim.target.pitchDeg)
                // The reading was taken about half a round trip before it arrived; the
                // head has kept turning since.
                let age = now - reading.at + Self.angleReadLatency
                let yaw = GimbalWaypoint.unwrapYaw(Double(reading.angle.yaw)) + rate.yaw * age
                let pitch = Double(reading.angle.pitch) + rate.pitch * age
                let wantPitch = min(max(head.pitch, Self.gimbalPitchRange.lowerBound), Self.gimbalPitchRange.upperBound)
                // Feed the head's rate forward, plus its acceleration times the stick's ease-in
                // lag so the camera speeds up in step with the head instead of trailing it.
                let lag = Self.stickLagSeconds * Self.headTrackAccelFeed
                let yawRate = head.yawRate + head.yawAccel * lag + Self.headTrackGain * (head.yaw - yaw)
                let pitchRate = head.pitchRate + head.pitchAccel * lag + Self.headTrackGain * (wantPitch - pitch)
                pan = Int32(min(max((yawRate / Self.stickPanDegPerSec).rounded(), -99), 99))
                tilt = Int32(min(max((pitchRate / Self.stickTiltDegPerSec).rounded(), -99), 99))
                #if DEBUG
                    headTrackLog.append([now, head.yaw, wantPitch, yaw, pitch, Double(pan), Double(tilt)])
                    if headTrackLog.count > 1500 { headTrackLog.removeFirst(300) }
                #endif
            }
            if let request = try? LunaProtocol.gimbalMove(upDown: tilt, leftRight: pan) {
                Task { [weak self] in _ = try? await self?.sendLuna(request, timeout: .seconds(2)) }
            }
            let k = 1 - exp(-(now - last) / Self.stickLagSeconds)
            last = now
            rate.yaw += (Double(pan) * Self.stickPanDegPerSec - rate.yaw) * k
            rate.pitch += (Double(tilt) * Self.stickTiltDegPerSec - rate.pitch) * k
            try? await Task.sleep(for: .seconds(Self.headTrackTick))
        }
        // A fresh task: this one is usually cancelled here, and a cancelled send never goes
        // out, which left the head coasting on the last stick value.
        guard hasControlLink, gimbalAim?.token == token || gimbalAim == nil, !gimbalStick.isHeld else { return }
        // Again shortly after, in case a last MOVE still in flight lands behind the first.
        Task { @MainActor [weak self] in
            for attempt in 0..<2 {
                guard let self, attempt == 0 || (self.gimbalAim == nil && !self.gimbalStick.isHeld) else { return }
                _ = try? await self.sendLuna(LunaProtocol.gimbalReleaseRequest())
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    /// Stick rate per VirtualRC unit and its ease-in lag, fw 1.1.15. The gyro reads 0.635
    /// and 0.54 deg/s per unit at steady speed; these are what tracked a 20° sine best
    /// against GET_ANGLE (lag 0.02 s, 8% overshoot).
    nonisolated(unsafe) static var stickPanDegPerSec = 0.75
    nonisolated(unsafe) static var stickTiltDegPerSec = 0.64
    static let stickLagSeconds = 0.23
    /// GET_ANGLE round trip is 20 to 40 ms on the camera AP; half of it, roughly.
    static let angleReadLatency = 0.015
    /// Live-tunable head tracking feel (debug remote `headTune`).
    /// Pull toward the head's exact angle (1/s).
    nonisolated(unsafe) static var headTrackGain = 4.0
    /// How far ahead of the newest AirPods sample the head is aimed (covers link latency).
    nonisolated(unsafe) static var headTrackLead = 0.0
    nonisolated(unsafe) static var headTrackTick = 0.033
    nonisolated(unsafe) static var headTrackAccelFeed = 1.0
    nonisolated(unsafe) static var headTrackFitWindow = 0.3

    /// Head angle at `time` with its rate (deg/s) and acceleration (deg/s²), from a
    /// quadratic least-squares fit of the last 250 ms of samples (a line with fewer than
    /// four), carried on past the newest sample; after 0.2 s without one it holds.
    static func headTrackReference(_ samples: [HeadTrackSample], at time: Double) -> HeadTrackReference? {
        guard let newest = samples.last else { return nil }
        let recent = samples.filter { newest.t - $0.t <= Self.headTrackFitWindow }
        let xs = recent.map { $0.t - newest.t }
        func fit(_ ys: [Double]) -> (value: Double, rate: Double, accel: Double) {
            let n = Double(xs.count)
            var s = [Double](repeating: 0, count: 5)
            var sy = [0.0, 0.0, 0.0]
            for (x, y) in zip(xs, ys) {
                var power = 1.0
                for k in 0..<5 {
                    s[k] += power
                    if k < 3 { sy[k] += power * y }
                    power *= x
                }
            }
            func det3(_ m: [[Double]]) -> Double {
                m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
                    + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
            }
            if xs.count >= 4 {
                let m = [[s[0], s[1], s[2]], [s[1], s[2], s[3]], [s[2], s[3], s[4]]]
                let d = det3(m)
                if abs(d) > 1e-12 {
                    func solve(_ column: Int) -> Double {
                        var c = m
                        for row in 0..<3 { c[row][column] = sy[row] }
                        return det3(c) / d
                    }
                    return (solve(0), solve(1), 2 * solve(2))
                }
            }
            let denominator = n * s[2] - s[1] * s[1]
            guard xs.count >= 2, abs(denominator) > 1e-12 else { return (ys.last ?? 0, 0, 0) }
            let rate = (n * sy[1] - s[1] * sy[0]) / denominator
            return ((sy[0] - rate * s[1]) / n, rate, 0)
        }
        // A stale head (no sample for 0.2 s) holds its last angle instead of drifting on.
        guard time - newest.t <= 0.2 else { return HeadTrackReference(yaw: newest.yaw, pitch: newest.pitch) }
        let yaw = fit(recent.map(\.yaw))
        let pitch = fit(recent.map(\.pitch))
        let h = max(time - newest.t, 0)
        return HeadTrackReference(
            yaw: yaw.value + yaw.rate * h + yaw.accel * h * h / 2,
            pitch: pitch.value + pitch.rate * h + pitch.accel * h * h / 2,
            yawRate: yaw.rate, pitchRate: pitch.rate, yawAccel: yaw.accel, pitchAccel: pitch.accel)
    }

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
            headTrackSamples.append(HeadTrackSample(t: t, yaw: target.yawDeg, pitch: target.pitchDeg))
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

    /// Target pose `time` seconds into a take: the shell's rounded-corner curve for
    /// A·B·C with smoothness, straight legs otherwise.
    nonisolated static func programPose(_ take: GimbalProgram, at time: TimeInterval) -> GimbalWaypoint? {
        guard let a = take.a, let b = take.b else { return nil }
        if let curve = GimbalProgramCurve(program: take) { return curve.position(at: time) }
        if time < take.durationAB || take.c == nil {
            return GimbalMoveEngine.lerp(a, b, u: min(max(time / take.durationAB, 0), 1))
        }
        return GimbalMoveEngine.lerp(b, take.c!, u: min((time - take.durationAB) / take.durationBC, 1))
    }

    nonisolated static func programDuration(_ take: GimbalProgram) -> TimeInterval {
        take.durationAB + (take.c == nil ? 0 : take.durationBC)
    }

    /// Countdown while the head goes to A, then stream the path at the SET rate.
    /// Loop plays the take backwards and forwards until stopped.
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
        guard canRunProgrammedMove, let a = gimbalProgram.a, gimbalAngle != nil else {
            controlNote = gimbalProgram.canRun ? ControlHud.gimbalPoseNotReady : ControlHud.programmedMoveNeedAB
            return
        }
        let take = gimbalProgram
        controlNote = nil
        stopGimbalAim()
        endGimbalStick(cancelMove: true)
        gimbalMoveRunning = true
        gimbalMovePaused = false
        gimbalMoveCanPause = false
        gimbalMoveClock = 0
        gimbalMoveTask?.cancel()
        gimbalMoveTask = Task { @MainActor [weak self] in
            self?.sendGimbalAngle(a)
            for remaining in (1...3).reversed() {
                guard let self, !Task.isCancelled, self.gimbalMoveRunning else { return }
                self.gimbalStartCountdown = remaining
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
            guard let self, !Task.isCancelled, self.gimbalMoveRunning else { return }
            self.gimbalStartCountdown = nil
            self.gimbalMoveCanPause = true
            ControlLiveLog.line("gimbal-move: start \(take.summary) duration=\(Self.programDuration(take))")
            let duration = Self.programDuration(take)
            var last = ProcessInfo.processInfo.systemUptime
            var reverse = false
            var loggedAt = 0.0
            while !Task.isCancelled, self.gimbalMoveRunning {
                guard case .live = self.phase, self.gimbalControlSceneActive else {
                    self.cancelProgrammedMove()
                    return
                }
                let now = ProcessInfo.processInfo.systemUptime
                if !self.gimbalMovePaused { self.gimbalMoveClock += now - last }
                last = now
                if self.gimbalMoveClock >= duration {
                    guard take.loop else { break }
                    self.gimbalMoveClock -= duration
                    reverse.toggle()
                }
                if !self.gimbalMovePaused,
                    let target = Self.programPose(
                        take, at: reverse ? duration - self.gimbalMoveClock : self.gimbalMoveClock)
                {
                    self.sendGimbalAngle(target)
                    if now - loggedAt >= 0.5, let reading = self.gimbalAngle {
                        loggedAt = now
                        ControlLiveLog.line(String(
                            format: "gimbal-move: t=%.2f target=%.1f,%.1f live=%.1f,%.1f",
                            self.gimbalMoveClock, target.yawDeg, target.pitchDeg,
                            reading.angle.yaw, reading.angle.pitch))
                    }
                }
                try? await Task.sleep(for: Self.gimbalSetInterval)
            }
            guard !Task.isCancelled, self.gimbalMoveRunning else { return }
            if let end = Self.programPose(take, at: reverse ? 0 : duration) { self.sendGimbalAngle(end) }
            ControlLiveLog.line("gimbal-move: done")
            self.finishProgrammedMove()
        }
    }

    func restartProgrammedMove() {
        guard gimbalControlSceneActive, !isLocked, gimbalMoveRunning, gimbalMovePaused else { return }
        cancelProgrammedMove()
        runProgrammedMove()
    }

    func pauseOrResumeProgrammedMove() {
        guard gimbalControlSceneActive, !isLocked, gimbalMoveRunning, gimbalMoveCanPause else { return }
        // The head settles on the last target (one 33 ms tick ahead); re-sending the
        // GET pose, ~70 ms stale, stepped it back.
        gimbalMovePaused.toggle()
        controlNote = nil
    }

    func cancelProgrammedMove() {
        gimbalMoveTask?.cancel()
        finishProgrammedMove()
    }

    private func finishProgrammedMove() {
        gimbalMoveTask = nil
        gimbalStartCountdown = nil
        gimbalMoveRunning = false
        gimbalMovePaused = false
        gimbalMoveCanPause = false
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
        guard supportsTapFocus else { return }
        if isTrackingActive { cancelSubjectTracking() }
        lastTapFocusAt = Date()
        faceBox = nil
        let x = min(max(Double(normalized.x), 0), 1)
        let y = min(max(Double(normalized.y), 0), 1)
        focusPoint = CGPoint(x: x, y: y)
        guard canSendControl else { return }
        do {
            try subjectTracking.focus(x: x, y: y, finished: controlFinished("Focus"))
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

    func clearLocalTracking() {
        subjectTracking.clear()
    }

    func showTracking(_ snapshot: LunaSubjectTracking.Snapshot) {
        searchBox = snapshot.searchBox.map(TrackingBox.init)
        subjectBox = snapshot.subjectBox.map(TrackingBox.init)
        isTracking = snapshot.tracking
    }

    /// An owner-sent request's outcome, reported like `sendControl` without a settings refresh.
    func controlFinished(_ name: String) -> @MainActor (Error?) -> Void {
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

struct HeadTrackReference: Equatable {
    var yaw: Double
    var pitch: Double
    var yawRate = 0.0
    var pitchRate = 0.0
    var yawAccel = 0.0
    var pitchAccel = 0.0
}

/// One head-tracking target at its measurement time (uptime seconds).
struct HeadTrackSample: Equatable {
    var t: Double
    var yaw: Double
    var pitch: Double
}

// MARK: - Timecode

extension CameraSession {
    /// Capture to phone delay of a live frame at best (official-app captures: frames land
    /// 90 to 200 ms after their camera clock stamp).
    static let frameLatencySeconds = 0.09

    /// The Luna's timecode is time of day from its own clock, which the phone app is
    /// expected to set (the camera's "Sync system time" asks for the app). Set it like the
    /// official app does on connect, but to the millisecond.
    func syncCameraClock() {
        frameClockOffset = nil
        lastTimecodeSecond = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            let zone = TimeZone.current
            let now = Date()
            guard let request = try? LunaProtocol.setClockRequest(
                unixSeconds: UInt64(now.timeIntervalSince1970),
                timeZoneSeconds: Int32(zone.secondsFromGMT(for: now)), zone: zone.identifier),
                (try? await self.sendLuna(request, timeout: .seconds(2))) != nil
            else { return }
            // Stamped at send: a GET round trip on the camera AP is about 4 ms (the clock
            // SET takes ~220 ms, but that is the camera's own processing).
            for count: UInt32 in 0..<2 {
                let milliseconds = UInt64((Date().timeIntervalSince1970 * 1000).rounded())
                if let request = try? LunaProtocol.syncTimeAccurateRequest(unixMilliseconds: milliseconds, count: count) {
                    _ = try? await self.sendLuna(request, timeout: .seconds(2))
                }
            }
            ControlLiveLog.line("luna: camera clock synced")
        }
    }

    /// Timecode of the live frame just received. Frame stamps run on a camera clock that
    /// does not follow its time of day (MEDIA_TIME jumped 2380 s when the camera time was
    /// set; the frame clock did not), so frames are pinned to the phone clock by their
    /// earliest arrival. With the camera clock synced to the phone, that is the camera's
    /// timecode. The HUD shows HH:MM:SS, so the status only changes once a second.
    func noteFrameClock(_ milliseconds: UInt64) {
        #if DEBUG
            lastFrameClock = milliseconds
        #endif
        let seen = Date().timeIntervalSince1970 - Double(milliseconds) / 1000 - Self.frameLatencySeconds
        let offset = min(frameClockOffset ?? seen, seen)
        frameClockOffset = offset
        let wall = Double(milliseconds) / 1000 + offset
        let second = Int(wall.rounded(.down))
        guard second != lastTimecodeSecond else { return }
        lastTimecodeSecond = second
        let timecode = LunaShellMapping.cameraTimecode(
            unixSeconds: wall, timeZoneSeconds: TimeZone.current.secondsFromGMT(), fps: status.fps)
        status.timecode = LunaShellMapping.timecodeText(timecode)
        (coreSession as? LunaCameraSession)?.ingest(timecode: timecode)
    }
}
