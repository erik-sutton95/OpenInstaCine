import CoreGraphics
import Foundation
import Insta360Protocol
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
    /// Luna phone protocol exposes no audio channel setting or meters.
    var supportsAudio: Bool { false }
    /// Luna reports no timecode; the REC timer carries elapsed time.
    var supportsTimecode: Bool { false }
    /// Auto ISO ceiling and native-ISO hop are Osmo camcap features; Luna has neither.
    var supportsIsoLimit: Bool { false }
    /// Luna media browse runs over HTTP next to the live socket.
    var hasControlLink: Bool { backend.isControlReady }
    var bodyFamily: CameraBodyFamily { .other }
    var colorModes: [ColorMode] { LunaShellMapping.colorModes }

    var currentShootingMode: ShootingMode? { ShootingMode.fromStatus(status.shootingMode) }

    private var canSendControl: Bool {
        guard case .live = phase, backend.isControlReady else {
            controlNote = "Connect the camera to use its controls."
            return false
        }
        guard !isLocked else {
            controlNote = "Controls locked"
            return false
        }
        return true
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
                let reply = try await self.backend.send(request)
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
        LunaRefreshDebounce.shared.schedule { [weak self] in
            await self?.backend.refreshSettings()
        }
    }

    private var pinNow: TimeInterval { Date.timeIntervalSinceReferenceDate }

    // MARK: - Record / photo

    /// Rec lamp: start/stop video, or take a still in Photo. Record never lies: the
    /// lamp holds `controlBusy` until capture status confirms.
    func pressShutter() {
        guard canSendControl else { return }
        let photo = currentShootingMode?.isPhoto == true
        controlBusy = true
        if photo {
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
            return
        }
        let starting = !status.isRecording
        let luna = currentShootingMode.flatMap(LunaShellMapping.lunaShootingMode) ?? .video
        pins.recording = CameraValuePin(starting, now: pinNow, settle: 4)
        sendControl(
            starting ? "Record" : "Stop",
            {
                starting
                    ? try LunaProtocol.startCaptureRequest(for: luna)
                    : try LunaProtocol.stopCaptureRequest(for: luna)
            },
            refresh: false,
            onFail: { [weak self] in
                self?.pins.recording = nil
                self?.controlBusy = false
            },
            onSuccess: { [weak self] _ in
                guard let self else { return }
                if starting { self.recordStartedAt = Date() }
                self.status.isRecording = starting
                if !starting {
                    self.recordStartedAt = nil
                    self.status.recordElapsedSec = 0
                    Task { await self.refreshMediaAfterCapture() }
                }
                self.controlBusy = false
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
        backend.functionMode = luna.functionMode.rawValue
        formatTable = [:]
        pins.format = nil
        sendControl(
            mode.label, { try luna.request() },
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

    private var currentISO: Int? {
        guard let index = status.isoIndex, index != .auto else { return nil }
        return index.isoValue
    }

    private var currentShutterSeconds: Double? {
        status.shutterDenom > 0 ? 1 / Double(status.shutterDenom) : nil
    }

    /// Luna has one exposure message: program + ISO + shutter. The shell's
    /// independent ISO / shutter drums map onto its four programs.
    private func sendExposure(iso: Int?, shutterSeconds: Double?, name: String) {
        let program: LunaExposureProgram
        switch (iso, shutterSeconds) {
        case (nil, nil): program = .automatic
        case (.some, nil): program = .isoPriority
        case (nil, .some): program = .shutterPriority
        case (.some, .some): program = .manual
        }
        let mode = backend.functionMode
        sendControl(
            name,
            {
                try LunaProtocol.setVideoExposure(
                    program: program, iso: iso.map(UInt64.init), shutterSeconds: shutterSeconds,
                    functionMode: mode)
            },
            onFail: { [weak self] in
                self?.pins.isoIndex = nil
                self?.pins.shutterDenom = nil
                self?.pins.expoMode = nil
            })
    }

    func setISO(_ index: IsoIndex) {
        guard canSendControl else { return }
        pins.isoIndex = CameraValuePin(index, now: pinNow)
        status.isoIndex = index
        status.iso = index.isoValue ?? status.iso
        let iso = index == .auto ? nil : index.isoValue
        let shutter = status.expoMode == .manual ? currentShutterSeconds : nil
        let mode: ExpoMode = (iso == nil && shutter == nil) ? .auto : .manual
        pins.expoMode = CameraValuePin(mode, now: pinNow)
        status.expoMode = mode
        LunaExposureCoalescer.shared.submit(key: "exposure") { [weak self] in
            self?.sendExposure(iso: iso, shutterSeconds: shutter, name: "ISO \(index.label)")
        }
    }

    func setShutterDenom(_ denom: Int) {
        guard canSendControl else { return }
        pins.shutterDenom = CameraValuePin(denom, now: pinNow)
        status.shutterDenom = denom
        pins.expoMode = CameraValuePin(.manual, now: pinNow)
        status.expoMode = .manual
        let iso = currentISO
        LunaExposureCoalescer.shared.submit(key: "exposure") { [weak self] in
            self?.sendExposure(
                iso: iso, shutterSeconds: 1 / Double(max(1, denom)), name: "1/\(denom)")
        }
    }

    func setExpoMode(_ mode: ExpoMode) {
        guard canSendControl else { return }
        autoExposureLock = nil
        pins.expoMode = CameraValuePin(mode, now: pinNow)
        status.expoMode = mode
        if mode == .auto {
            pins.isoIndex = CameraValuePin(.auto, now: pinNow)
            status.isoIndex = .auto
            sendExposure(iso: nil, shutterSeconds: nil, name: "Auto exposure")
            return
        }
        // Manual needs a shutter: keep the current one, else the 180° default.
        let fps = max(status.fps, 25)
        let denom = status.shutterDenom > 0 ? status.shutterDenom : fps * 2
        pins.shutterDenom = CameraValuePin(denom, now: pinNow)
        status.shutterDenom = denom
        sendExposure(iso: currentISO, shutterSeconds: 1 / Double(denom), name: "Manual exposure")
    }

    func setEv(_ ev: EvComp) {
        guard canSendControl else { return }
        pins.ev = CameraValuePin(ev, now: pinNow)
        status.evComp = ev
        let mode = backend.functionMode
        LunaExposureCoalescer.shared.submit(key: "ev") { [weak self] in
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

    func setWhiteBalanceAuto(tint: Int? = nil) {
        autoWhiteBalanceLock = nil
        fireWhiteBalance(.auto(tint: 0))
    }

    func setWhiteBalanceCustom(kelvin: Int, tint: Int) {
        let wb = WhiteBalance.custom(kelvin: min(max(kelvin, 2_000), 10_000), tint: 0)
        // Custom from AWB Lock keeps the locked value; the camera is already there.
        if autoWhiteBalanceLock != nil, status.whiteBalance == wb {
            autoWhiteBalanceLock = nil
            return
        }
        autoWhiteBalanceLock = nil
        fireWhiteBalance(wb)
    }

    private func fireWhiteBalance(_ wb: WhiteBalance) {
        guard canSendControl else { return }
        // fw 1.1.15 applies kelvin 3.5 to 3.9 s after the SET.
        pins.whiteBalance = CameraValuePin(wb, now: pinNow, settle: 5)
        status.whiteBalance = wb
        if wb.mode == .custom { status.whiteBalanceKelvin = wb.kelvin }
        status.whiteBalanceTint = 0
        let mode = backend.functionMode
        LunaExposureCoalescer.shared.submit(key: "wb") { [weak self] in
            self?.sendControl(
                wb.mode == .auto ? "WB Auto" : "WB \(wb.kelvin)K",
                {
                    wb.mode == .auto
                        ? try LunaProtocol.setWhiteBalanceAuto(functionMode: mode)
                        : try LunaProtocol.setWhiteBalanceKelvin(UInt64(wb.kelvin), functionMode: mode)
                },
                onFail: { [weak self] in self?.pins.whiteBalance = nil })
        }
    }

    // MARK: - Focus mode and metering

    func setFocusMode(_ mode: FocusMode) {
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
            mode.label, { try LunaProtocol.setColorMode(luna, functionMode: functionMode) },
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
            optimistic: zoomOptimistic)
    }

    var zoomDialReadout: Double {
        CamFov.continuousReadout(
            live: status.zoomFactor, preview: zoomPinchPreview, fallback: zoomStop,
            optimistic: zoomOptimistic)
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
        controlNote = "Zoom \(CamFov.displayLabel(factor: target))"
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
        guard case .live = phase, backend.isControlReady else { return }
        pendingZoomWrite = factor
        guard zoomWriteTask == nil else { return }
        zoomWriteTask = Task { @MainActor [weak self] in
            while let self, let next = self.pendingZoomWrite {
                self.pendingZoomWrite = nil
                let mode = self.backend.functionMode
                if let request = try? LunaProtocol.setZoomScale(next, functionMode: mode) {
                    _ = try? await self.backend.send(request)
                }
                try? await Task.sleep(for: .milliseconds(80))
            }
            self?.zoomWriteTask = nil
            self?.scheduleSettingsRefresh()
        }
    }

    // MARK: - Gimbal

    var canSetGimbalConfiguration: Bool {
        hasGimbal && !isLocked && phase == .live && gimbalControlSceneActive && !holdsMonitor
            && !sessionRecovery.isRecovering && backend.isControlReady
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
                    _ = try? await self.backend.send(request, timeout: .seconds(2))
                }
                try? await Task.sleep(for: LunaStickStream.interval)
            }
        }
    }

    func endGimbalStick(cancelMove: Bool = false) {
        guard gimbalStick.isHeld else { return }
        gimbalStick.reset()
        ControlLiveLog.line("control: gimbal stick rest")
        guard backend.isControlReady else { return }
        Task { _ = try? await backend.send(LunaProtocol.gimbalReleaseRequest()) }
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
                nativePitchDeg: -pitch),
            settleAndStop: true)
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
    /// takes yaw in -180...180 and routes around the stop itself.
    static let gimbalPitchRange = -57.0...90.0

    func startGimbalAnglePoll() {
        gimbalAnglePoll?.cancel()
        gimbalAnglePoll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if case .live = self.phase, self.backend.isControlReady { await self.readGimbalAngle() }
                try? await Task.sleep(for: Self.gimbalAnglePollInterval)
            }
        }
    }

    @discardableResult
    func readGimbalAngle() async -> LunaGimbalAngle? {
        guard let request = try? LunaProtocol.gimbalGetAngleRequest(),
            let reply = try? await backend.send(request, timeout: .seconds(1)),
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
        let backend = self.backend
        Task { _ = try? await backend.send(request, timeout: .seconds(2)) }
    }

    func ingestIMU(_ samples: [LunaIMUSample]) {
        gimbalPose.ingest(samples, commanding: gimbalStick.isHeld || gimbalAim != nil || gimbalMoveRunning)
        lastIMUAt = ProcessInfo.processInfo.systemUptime
    }

    /// Point the head at `target` (handle frame) and keep sending the latest target
    /// whenever it changes. `settleAndStop` ends once GET_ANGLE reads within 0.5°
    /// (Level, debug aim), or after 8 s.
    @discardableResult
    func aimGimbal(at target: GimbalWaypoint, settleAndStop: Bool = false) -> UInt64? {
        guard canSetGimbalConfiguration, !gimbalStick.isHeld, !gimbalMoveRunning else { return nil }
        gimbalAimGeneration &+= 1
        let token = gimbalAimGeneration
        gimbalAim = (target, token)
        gimbalAimTask?.cancel()
        gimbalAimTask = Task { @MainActor [weak self] in
            var sent: GimbalWaypoint?
            // Tracking glides the sent target along a straight vector: fw 1.1.15 drives
            // both axes at the same speed toward each SET_ANGLE, so a far target comes out
            // as a dog-leg (diagonal, then one axis). Short straight steps keep it straight.
            var glide = self?.freshGimbalWaypoint ?? target
            var lastTarget = target
            var velocity = (yaw: 0.0, pitch: 0.0)
            let started = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                guard let self, let aim = self.gimbalAim, aim.token == token,
                    self.canSetGimbalConfiguration, !self.gimbalStick.isHeld
                else { break }
                let next: GimbalWaypoint
                if settleAndStop {
                    next = aim.target
                } else {
                    // Lead the head along its own motion so the camera's stop-at-target
                    // planner never brakes between updates (that braking is the stepping).
                    let dt = 0.033  // gimbalSetInterval
                    let keep = Self.headTrackVelocityKeep
                    velocity.yaw = velocity.yaw * keep + (aim.target.yawDeg - lastTarget.yawDeg) / dt * (1 - keep)
                    velocity.pitch = velocity.pitch * keep + (aim.target.pitchDeg - lastTarget.pitchDeg) / dt * (1 - keep)
                    lastTarget = aim.target
                    var ahead = aim.target
                    ahead.yawDeg += velocity.yaw * Self.headTrackLeadSeconds
                    ahead.pitchDeg += velocity.pitch * Self.headTrackLeadSeconds
                    next = Self.smooth(from: glide, toward: ahead, keep: Self.headTrackSmoothing)
                }
                glide = next
                if next != sent {
                    self.sendGimbalAngle(next)
                    sent = next
                }
                if settleAndStop {
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - started > 8 { break }
                    if now - started > 0.3, let reading = self.gimbalAngle, reading.at > started + 0.2,
                        abs(remainder(Double(reading.angle.yaw) - aim.target.yawDeg, 360)) <= 0.5,
                        abs(Double(reading.angle.pitch) - aim.target.pitchDeg) <= 0.5
                    { break }
                }
                try? await Task.sleep(for: Self.gimbalSetInterval)
            }
            self?.finishGimbalAim(token: token)
        }
        return token
    }

    /// Live-tunable head tracking feel (debug remote `headTune`).
    nonisolated(unsafe) static var headTrackLeadSeconds = 0.15
    nonisolated(unsafe) static var headTrackSmoothing = 0.3
    nonisolated(unsafe) static var headTrackVelocityKeep = 0.6

    /// Exponential step toward `target`; `keep` is the share of the old value kept per tick.
    static func smooth(from current: GimbalWaypoint, toward target: GimbalWaypoint, keep: Double)
        -> GimbalWaypoint
    {
        var next = target
        next.yawDeg = current.yawDeg * keep + target.yawDeg * (1 - keep)
        next.pitchDeg = current.pitchDeg * keep + target.pitchDeg * (1 - keep)
        if abs(next.yawDeg - target.yawDeg) < 0.05, abs(next.pitchDeg - target.pitchDeg) < 0.05 { return target }
        return next
    }

    /// One 33 ms tick: close ~half the gap (light smoothing), capped at 2.5° along the
    /// straight line to the target (~75 °/s, the head's top speed), so both axes stay in
    /// proportion. Sub-0.05° remainders snap so a still head sends nothing new.
    static func glide(from current: GimbalWaypoint, toward target: GimbalWaypoint) -> GimbalWaypoint {
        let dy = target.yawDeg - current.yawDeg
        let dp = target.pitchDeg - current.pitchDeg
        let distance = (dy * dy + dp * dp).squareRoot()
        guard distance > 0.05 else { return target }
        let step = min(distance * 0.5, 2.5)
        var next = target
        next.yawDeg = current.yawDeg + dy / distance * step
        next.pitchDeg = current.pitchDeg + dp / distance * step
        return next
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
            "Gimbal \(mode.label)", { try LunaProtocol.setGimbalMode(luna, functionMode: functionMode) },
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

    // Head tracking streams the AirPods target as SET_ANGLE (latest wins).
    func beginNativeHeadTrack() -> UInt64? {
        guard !isBrowsingMedia, !isLiveVideoStale, let live = freshGimbalWaypoint else { return nil }
        return aimGimbal(at: live)
    }

    func updateNativeHeadTrack(target: GimbalWaypoint, token: UInt64) -> Bool {
        guard let aim = gimbalAim, aim.token == token, !isBrowsingMedia, !isLiveVideoStale else {
            endNativeHeadTrack(token: token)
            return false
        }
        gimbalAim = (target, token)
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

    /// Feed tap: inside a face box → Deep Track that face. Anywhere else → tap-to-focus.
    func handleFeedTap(at normalized: CGPoint) {
        let x = min(max(Double(normalized.x), 0), 1)
        let y = min(max(Double(normalized.y), 0), 1)
        if let box = FaceTrackTap.boxIfTapped(
            overlay: focusOverlay, x: x, y: y, sceneFaces: dimmedFaces)
        {
            startTracking(box)
            return
        }
        markFocus(at: CGPoint(x: x, y: y))
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
        // fw 1.1.15 official ROI with the camera upright, centred on the tap:
        // 0.1545 × 0.271…0.275 of the 16:9 preview (square on the sensor). The
        // smaller 0.0869 × 0.1545 box was captured with the camera lying on its side.
        let w = 0.1545
        let h = 0.2727
        let left = min(max(x - w / 2, 0), 1 - w)
        let top = min(max(y - h / 2, 0), 1 - h)
        let mode = backend.functionMode
        sendControl(
            "Focus",
            { try LunaProtocol.setTapFocus(x: left, y: top, width: w, height: h, functionMode: mode) },
            refresh: false)
    }

    /// Drag-to-track → Luna Deep Track (cmd 237) with the operator's rectangle.
    func startTracking(_ box: TrackingBox) {
        if box.isTooSmall {
            noteFrameTooSmall()
            return
        }
        guard canSendControl else { return }
        searchBox = box
        subjectBox = nil
        isTracking = false
        trackingSawLock = false
        faceBox = nil
        let left = min(max(box.centerX - box.width / 2, 0), 1)
        let top = min(max(box.centerY - box.height / 2, 0), 1)
        let width = min(box.width, 1 - left)
        let height = min(box.height, 1 - top)
        sendControl(
            "Track",
            { try LunaProtocol.openTracking(x: left, y: top, width: width, height: height) },
            refresh: false,
            onFail: { [weak self] in self?.clearLocalTracking() })
    }

    /// Stream-borne Deep Track state (media 0x85, every frame): tracking moves the
    /// green subject box with the camera's box; lost shows the last box white, like
    /// the search box, until the camera reacquires (it may pick a new subject) or the
    /// operator cancels; idle after a lock means the camera ended tracking.
    func applyTrackFrame(_ frame: LunaTrackFrame) {
        let box = TrackingBox(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
        switch frame.state {
        case .tracking:
            isTracking = true
            trackingSawLock = true
            lastSubjectPushAt = Date()
            searchBox = nil
            faceBox = nil
            subjectBox = box
        case .lost:
            guard trackingSawLock else { return }
            // Not `isTracking`: FocusOverlayPolicy would draw the search box as a green subject.
            isTracking = false
            subjectBox = nil
            searchBox = box
        case .idle:
            // Idle frames also arrive between cmd 237 and the lock; only a lock ending counts.
            if trackingSawLock { clearLocalTracking() }
        case nil:
            break
        }
    }

    /// The camera reports the end of tracking on notification 8315 (cancel).
    func applyTrackingState(_ state: UInt64) {
        switch state {
        case 1, 2:
            isTracking = true
            trackingSawLock = true
            lastSubjectPushAt = Date()
            if let search = searchBox {
                subjectBox = TrackingBox.subject(from: search)
                searchBox = nil
            }
        default:
            if trackingSawLock || searchBox != nil { clearLocalTracking() }
        }
    }

    func cancelSubjectTracking() {
        let had = isTrackingActive
        clearLocalTracking()
        guard had, backend.isControlReady else { return }
        sendControl("Track clear", { LunaProtocol.cancelTrackingRequest }, refresh: false)
    }

    func clearLocalTracking() {
        searchBox = nil
        subjectBox = nil
        isTracking = false
        trackingSawLock = false
        lastSubjectPushAt = nil
    }

    func noteFrameTooSmall() {
        searchBox = nil
        subjectBox = nil
        isTracking = false
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

/// Coalesces rapid drum edits into one send per key per ~120 ms (latest wins).
@MainActor
final class LunaExposureCoalescer {
    static let shared = LunaExposureCoalescer()
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
    static let shared = LunaRefreshDebounce()
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
