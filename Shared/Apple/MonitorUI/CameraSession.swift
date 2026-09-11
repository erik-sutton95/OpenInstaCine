import AVFoundation
import CoreGraphics
import Foundation
import MonitorContracts
import Observation
import OpenPocketViewCore

struct FoundCamera: Identifiable, Sendable {
    let id: UUID
    let name: String
    let model: CameraModel
    let modelId: Int?
    init(id: UUID, name: String, model: CameraModel, modelId: Int? = nil) {
        self.id = id
        self.name = name
        self.model = model
        self.modelId = modelId
    }
    func enriched(from saved: SavedCamera?) -> FoundCamera {
        guard name.isEmpty, let saved else { return self }
        return FoundCamera(id: id, name: saved.advertisedName, model: model, modelId: modelId)
    }
}

/// Shared monitor presentation state. No camera wire protocol is permitted in this facade.
@MainActor @Observable
final class CameraSession {
    var phase: ConnectionPhase = .idle
    var status = CameraStatus()
    var found: [FoundCamera] = []
    private(set) var connectedCamera: FoundCamera?
    private(set) var joinedSSID: String?
    private(set) var cachedSSID: String?
    var sourceLabel: String?
    private var previewTransfer: CameraPreviewTransfer?
    var monitorTransfer: MonitorTransfer? {
        switch previewTransfer {
        case .rec709: .rec709
        case .hlg: .hdr
        case .dLog: .dlog
        case .dLog2: .dlog2
        case nil: status.monitorTransfer
        }
    }
    var liveFPS = "—"
    var liveSignalBars = 0
    var isReconnecting = false
    var sessionRecovery: SessionRecoveryState = .idle
    var holdsMonitor = false
    var sessionRecoveryCardGraceElapsed = false
    var recoveryDeviceName = ""
    var feedRecovering = false
    var isFeedWarming = true
    var controlBusy = false
    var controlNote: String?
    var isLocked = false
    var gimbalPoseViewFlip = false
    var gimbalPoseInvertPan = false
    var gimbalYawTenthDeg: Int16? { nil }
    var gimbalPitchTenthDeg: Int16? { nil }
    var lastGimbalAttitudeHex = ""
    var lastGimbalAttitudeDump = ""
    var gimbalLimitPulse: UInt = 0
    var gimbalLimitContact: GimbalLimitWatch.Contact = []
    var gimbalLimitPanSign: Double = 0
    var gimbalLimitTiltSign: Double = 0
    var mediaFiles: [MediaFile] = []
    var mediaFetchInProgress = false
    var mediaFetchListedCount = 0
    var mediaNote: String?
    var isBrowsingMedia = false
    var mediaDownloadProgress: [String: Double] = [:]
    var mediaLocalFavorites: Set<String> = []
    var focusPoint = CGPoint(x: 0.5, y: 0.5)
    var focusOverlay: FocusOverlay { .focus }
    var dimmedFaces: [TrackingBox] { [] }
    var wantsFaceAF: Bool { false }
    var wantsFaceDetect: Bool { false }
    var zoomStop: Double = 1
    var zoomStops: [Double] { [1] }
    var zoomMax: Double { 1 }
    var zoomPinchPreview: Double?
    var zoomOptimistic: Double?
    var zoomColorHopPending = false
    var zoomReadout: Double { status.zoomFactor ?? 1 }
    var bodyFamily: CameraBodyFamily { .other }
    var colorModes: [ColorMode] { [] }
    var isFormatPinActive: Bool { false }
    var supportsFocusMode: Bool { capabilities.contains(.focus) }
    var supportsTapFocus: Bool { capabilities.contains(.focus) }
    var supportsCameraControls: Bool {
        !capabilities.intersection([
            .recording, .exposure, .captureFormat, .whiteBalance, .focus, .zoom, .gimbal,
        ]).isEmpty
    }
    var supportsGimbal: Bool { capabilities.contains(.gimbal) }
    var supportsGimbalControl: Bool { supportsGimbal }
    var cameraLUTSelections: [LUTSelection] { [.auto] }
    var supportsZoom: Bool { capabilities.contains(.zoom) }
    var supportsRecording: Bool { capabilities.contains(.recording) }
    var isFocusResetAvailable: Bool { false }
    var isOnCameraNetwork: Bool { backend.isOnCameraNetwork }
    var isLiveVideoStale: Bool { lastGoodFrameAt.map { Date().timeIntervalSince($0) > 3 } ?? true }
    var currentShootingMode: ShootingMode? {
        guard (0...255).contains(status.shootingMode) else { return nil }
        return ShootingMode(rawValue: UInt8(status.shootingMode))
    }
    var capabilities: CameraCapabilities { backend.capabilities }
    @ObservationIgnored let decoder = HevcDecoder()
    var videoLayer: AVSampleBufferDisplayLayer { decoder.displayLayer }
    @ObservationIgnored let cameraMedia = CameraMedia()
    @ObservationIgnored var videoPackets = 0
    @ObservationIgnored var accessUnits = 0
    @ObservationIgnored var framesEnqueued = 0
    @ObservationIgnored var droppedIncomplete = 0
    @ObservationIgnored var decoderErrors = 0
    @ObservationIgnored var hasVideoFormat = false
    @ObservationIgnored var nalTypes = ""
    @ObservationIgnored var lastKeyframeAge = "—"
    @ObservationIgnored let backend: any CameraBackend
    @ObservationIgnored private var controlTask: Task<Void, Never>?
    @ObservationIgnored private var controlQueue: [CameraControlIntent] = []
    @ObservationIgnored var mediaAssets: [String: CameraMediaAsset] = [:]
    @ObservationIgnored private var descriptors: [UUID: MonitorCamera] = [:]
    @ObservationIgnored private var frameRate = FrameRateSampler()
    @ObservationIgnored private var lastGoodFrameAt: Date?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var recoveryTask: Task<Void, Never>?
    @ObservationIgnored private var healthTask: Task<Void, Never>?
    @ObservationIgnored private(set) var generation = 0
    @ObservationIgnored private var recoveryCycle = 0
    @ObservationIgnored private var reconnectTarget: UUID?
    @ObservationIgnored private var expectedDisconnect = false
    @ObservationIgnored private var sceneInactive = false
    @ObservationIgnored private var dropGuard = SessionDropStormGuard()

    init(backend: any CameraBackend) {
        self.backend = backend
        decoder.onPresentedFrame = { [weak self] in self?.noteLiveFrame() }
        // Source adapters provide periodic parameter sets/keyframes. Handoffs wait
        // for those; the shared renderer never emits camera-specific restart commands.
        decoder.onHandoffNeedsIDR = {}
        decoder.onParameterSetsChanged = {}
    }
    convenience init() { self.init(backend: UnavailableCameraBackend()) }

    /// SwiftUI may construct and discard candidate @State values. Only an active
    /// facade binds the shared backend; construction alone must not steal a live feed.
    func activateBackend() { backend.eventHandler = { [weak self] in self?.receive($0) } }
    func startScan() { startScan(reconnect: nil) }
    func startScan(reconnect id: UUID?) {
        activateBackend()
        disconnect()
        expectedDisconnect = false
        reconnectTarget = id
        isReconnecting = id != nil
        found = []
        phase = .scanning
        let token = generation
        runTask = Task { [weak self] in
            guard let self, !Task.isCancelled, token == generation else { return }
            do { try await self.backend.startScan() } catch {
                if token == self.generation {
                    self.phase = .failed(error.localizedDescription)
                    self.isReconnecting = false
                }
            }
        }
    }
    func reconnect(to id: UUID) {
        if let known = descriptors[id] {
            connect(
                FoundCamera(
                    id: known.id, name: known.name,
                    model: CameraModel(name: known.model, datalinkPort: 0, tcpPoke: false)))
        } else {
            startScan(reconnect: id)
        }
    }
    func connect(_ camera: FoundCamera) {
        activateBackend()
        runTask?.cancel()
        recoveryCycle += 1
        recoveryTask?.cancel()
        recoveryTask = nil
        generation += 1
        healthTask?.cancel()
        healthTask = nil
        controlTask?.cancel()
        controlTask = nil
        controlQueue = []
        controlBusy = false
        expectedDisconnect = true
        backend.disconnect()
        cameraMedia.resetSession()
        mediaFiles = []
        mediaAssets = [:]
        mediaLocalFavorites = []
        mediaDownloadProgress = [:]
        mediaFetchInProgress = false
        mediaFetchListedCount = 0
        mediaNote = nil
        expectedDisconnect = false
        isReconnecting = false
        reconnectTarget = nil
        connectedCamera = camera
        recoveryDeviceName = camera.name
        UserDefaults.standard.set(camera.id.uuidString, forKey: "MonitorEngine.lastMediaCamera")
        let descriptor =
            descriptors[camera.id]
            ?? MonitorCamera(
                id: camera.id, name: camera.name, model: camera.model.name,
                capabilities: backend.capabilities)
        descriptors[camera.id] = descriptor
        status = CameraStatus()
        isFeedWarming = true
        frameRate = FrameRateSampler()
        decoder.reset()
        lastGoodFrameAt = nil
        phase = .connectingGatt
        let token = generation
        runTask = Task { [weak self] in
            guard let self, !Task.isCancelled, token == generation else { return }
            do {
                try await backend.connect(to: descriptor)
                guard token == generation else { return }
                startHealthCheck()
            } catch {
                guard token == generation, !Task.isCancelled else { return }
                backend.disconnect()
                phase = .failed(error.localizedDescription)
            }
        }
    }
    func disconnect() {
        generation += 1
        recoveryCycle += 1
        expectedDisconnect = true
        controlTask?.cancel()
        controlTask = nil
        controlQueue = []
        controlBusy = false
        runTask?.cancel()
        runTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        healthTask?.cancel()
        healthTask = nil
        backend.disconnect()
        decoder.reset()
        connectedCamera = nil
        joinedSSID = nil
        sourceLabel = nil
        previewTransfer = nil
        phase = .idle
        holdsMonitor = false
        sessionRecovery = .idle
        isReconnecting = false
        isFeedWarming = true
        feedRecovering = false
        liveFPS = "—"
        liveSignalBars = 0
        cameraMedia.resetSession()
        isBrowsingMedia = false
    }
    func forgetWifiCreds(for camera: SavedCamera) {
        backend.forget(cameraID: camera.id)
        descriptors[camera.id] = nil
    }
    func leaveCameraNetwork() {
        expectedDisconnect = true
        healthTask?.cancel()
        healthTask = nil
        cancelSessionRecovery(clearHoldsMonitor: false)
        holdsMonitor = connectedCamera != nil
        liveFPS = "HOLD"
        liveSignalBars = 0
        backend.leaveCameraNetwork()
    }
    func rejoinSoftAPAfterInternetHop() async {
        let token = generation
        guard connectedCamera != nil else { return }
        expectedDisconnect = false
        isFeedWarming = true
        decoder.flushForRecovery()
        frameRate = FrameRateSampler()
        do {
            try await backend.rejoinCameraNetwork()
            guard token == generation, !Task.isCancelled else { return }
            startHealthCheck()
        } catch {
            guard token == generation, !Task.isCancelled else { return }
            controlNote = error.localizedDescription
            beginSessionRecovery(reason: error.localizedDescription)
        }
    }
    func noteSceneBecameInactive() { sceneInactive = true }
    func noteSceneBecameActive() {
        let shouldRecover = sceneInactive && connectedCamera != nil && isLiveVideoStale
        sceneInactive = false
        if shouldRecover {
            beginSessionRecovery(reason: "The camera connection paused while the app was inactive.")
        }
    }
    private func receive(_ event: CameraBackendEvent) {
        guard !expectedDisconnect else { return }
        switch event {
        case .discovered(let camera):
            descriptors[camera.id] = camera
            let item = FoundCamera(
                id: camera.id, name: camera.name,
                model: CameraModel(name: camera.model, datalinkPort: 0, tcpPoke: false))
            if let index = found.firstIndex(where: { $0.id == item.id }) {
                found[index] = item
            } else {
                found.append(item)
            }
            if reconnectTarget == item.id { connect(item) }
        case .phase(let value):
            switch value {
            case .idle: if expectedDisconnect { phase = .idle }
            case .scanning: phase = .scanning
            case .connecting: phase = .connectingGatt
            case .negotiating: phase = .pairing
            case .awaitingApproval: phase = .awaitingApproval
            case .readingWiFi: phase = .readingWifiCreds
            case .joiningWiFi: phase = .joiningWifi
            case .openingVideo: phase = .openingDatalink
            case .streaming:
                phase = .live
                isFeedWarming = true
            }
        case .information(let info):
            status.firmware = info.firmware
            sourceLabel = info.sourceLabel
            previewTransfer = info.previewTransfer
        case .status(let snapshot): applyStatus(snapshot)
        case .joinedWiFi(let ssid):
            joinedSSID = ssid
            cachedSSID = ssid
        case .videoAccessUnit(let data, _):
            videoPackets += 1
            accessUnits += 1
            if decoder.decode(accessUnit: [UInt8](data)) { framesEnqueued += 1 }
            hasVideoFormat = decoder.pictureSize.width > 0
        case .disconnected(let reason):
            if !expectedDisconnect, connectedCamera != nil, !sceneInactive {
                beginSessionRecovery(reason: reason)
            }
        case .note(let note): controlNote = note
        }
    }
    private func noteLiveFrame() {
        guard connectedCamera != nil, phase == .live, !expectedDisconnect else { return }
        let now = Date()
        lastGoodFrameAt = now
        frameRate.recordFrame(at: now.timeIntervalSinceReferenceDate)
        liveFPS = frameRate.intervalCount > 0 ? frameRate.formatted : "—"
        // This measures delivered picture continuity, not the camera's RF strength.
        liveSignalBars = 4
        if frameRate.intervalCount >= 2 {
            isFeedWarming = false
            feedRecovering = false
            holdsMonitor = false
            sessionRecovery = .idle
            sessionRecoveryCardGraceElapsed = false
        }
    }
    private func startHealthCheck() {
        healthTask?.cancel()
        let started = Date()
        let token = generation
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, self.generation == token else { return }
                if self.sceneInactive { continue }
                let age =
                    self.lastGoodFrameAt.map { Date().timeIntervalSince($0) }
                    ?? Date().timeIntervalSince(started)
                if age > 3 {
                    self.liveFPS = "LINK"
                    self.liveSignalBars = 0
                }
                if age > 15 {
                    self.beginSessionRecovery(reason: "No new camera picture has arrived.")
                    return
                }
            }
        }
    }
    func beginSessionRecovery(reason: String, trigger: SessionRecoveryTrigger = .datalinkLost) {
        guard recoveryTask == nil, let camera = connectedCamera,
            let descriptor = descriptors[camera.id], !expectedDisconnect
        else { return }
        holdsMonitor = true
        feedRecovering = true
        isFeedWarming = true
        liveFPS = "RECOV"
        liveSignalBars = 0
        recoveryDeviceName = camera.name
        if dropGuard.noteDrop(now: Date().timeIntervalSinceReferenceDate) {
            sessionRecovery = .pausedAfterRepeatedDrops(drops: dropGuard.dropsInWindow)
            sessionRecoveryCardGraceElapsed = true
            return
        }
        let token = generation
        recoveryCycle += 1
        let cycle = recoveryCycle
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.recoveryCycle == cycle { self.recoveryTask = nil } }
            for attempt in 1...3 {
                guard !Task.isCancelled, token == generation else { return }
                sessionRecovery = .retrying(attempt: attempt, maxAttempts: 3)
                sessionRecoveryCardGraceElapsed = attempt > 1
                backend.disconnect()
                try? await Task.sleep(for: .seconds(Double(attempt)))
                do {
                    try Task.checkCancellation()
                    decoder.flushForRecovery()
                    frameRate = FrameRateSampler()
                    try await backend.connect(to: descriptor)
                    guard token == generation else { return }
                    startHealthCheck()
                    let until = Date().addingTimeInterval(15)
                    while Date() < until, isFeedWarming, !Task.isCancelled {
                        try await Task.sleep(for: .milliseconds(200))
                    }
                    if !isFeedWarming { return }
                } catch { if Task.isCancelled { return } }
            }
            sessionRecovery = .waitingForOperator(attemptsMade: 3)
            sessionRecoveryCardGraceElapsed = true
        }
    }
    func retrySessionRecovery() {
        recoveryCycle += 1
        recoveryTask?.cancel()
        recoveryTask = nil
        dropGuard.reset()
        beginSessionRecovery(reason: "Operator retry", trigger: .operatorRetry)
    }
    func cancelSessionRecovery(clearHoldsMonitor: Bool = true) {
        recoveryCycle += 1
        recoveryTask?.cancel()
        recoveryTask = nil
        sessionRecovery = .idle
        if clearHoldsMonitor { holdsMonitor = false }
    }
    func cameraControlUnavailable(_ name: String = "Camera controls") {
        controlNote =
            "\(name) are not connected for this camera yet. Live monitoring and view assists are available."
    }
    /// Values cross the seam as physical units or semantic options, never DUML enums.
    private func option<T>(_ value: T) -> CameraParameterValue {
        .option(CameraOption(rawValue: String(describing: value)))
    }
    private func submit(_ intent: CameraControlIntent) {
        guard capabilities.contains(intent.requiredCapability) else {
            cameraControlUnavailable()
            return
        }
        guard phase == .live else {
            controlNote = "Connect the camera to use its controls."
            return
        }
        if isLocked {
            switch intent {
            case .stopGimbal, .stopTracking: break
            default: return
            }
        }
        switch intent {
        case .gimbal:
            controlQueue.removeAll {
                if case .gimbal = $0 { return true }
                return false
            }
        case .zoom:
            controlQueue.removeAll {
                if case .zoom = $0 { return true }
                return false
            }
        default: break
        }
        guard controlQueue.count < 16 else { return }
        controlQueue.append(intent)
        guard controlTask == nil else { return }
        let token = generation
        controlTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if token == generation {
                    controlTask = nil
                    controlBusy = false
                }
            }
            while !controlQueue.isEmpty, !Task.isCancelled, token == generation {
                let next = controlQueue.removeFirst()
                controlBusy = true
                do {
                    try await backend.apply(next)
                    if token == generation, !Task.isCancelled { controlNote = nil }
                } catch {
                    if token == generation, !Task.isCancelled {
                        controlNote = error.localizedDescription
                    }
                }
            }
        }
    }
    func pressShutter() {
        submit(
            currentShootingMode?.isPhoto == true ? .takePhoto : .record(start: !status.isRecording))
    }
    func setShootingMode(_ mode: ShootingMode) { submit(.parameter(.shootingMode, option(mode))) }
    func setIsoLimit(_ limit: IsoLimit) {
        submit(.parameter(.isoCeiling, .number(Double(limit.ceiling))))
    }
    func setFacePriorityEnabled(_ on: Bool) {
        if on || capabilities.contains(.exposure) {
            submit(.parameter(.facePriorityExposure, .boolean(on)))
        }
    }
    func setEv(_ ev: EvComp) {
        submit(.parameter(.exposureCompensationStops, .number(Double(ev.thirds) / 3)))
    }
    func refreshIsoLimit() async {
        if capabilities.contains(.exposure) { try? await backend.refreshStatus() }
    }
    func setFov(_ fov: FovSetting) { submit(.parameter(.fieldOfView, option(fov))) }
    func setExpoMode(_ mode: ExpoMode) { submit(.parameter(.exposureMode, option(mode))) }
    func updateZoomPinch(magnification: Double) { setZoom(zoomReadout * magnification) }
    func endZoomPinch() { zoomPinchPreview = nil }
    func setZoom(_ factor: Double) { submit(.zoom(factor: factor)) }
    func setZoomSlider(_ factor: Double) { setZoom(factor) }
    func setZoomSlew(_ value: UInt16) { cameraControlUnavailable("Zoom controls") }
    func setZoomStop() {}
    func setISO(_ index: IsoIndex) {
        submit(.parameter(.iso, index.isoValue.map { .number(Double($0)) } ?? .automatic))
    }
    func setShutterDenom(_ denom: Int) {
        if denom > 0 { submit(.parameter(.shutterSeconds, .number(1 / Double(denom)))) }
    }
    func setWhiteBalanceAuto(tint: Int? = nil) {
        submit(.parameter(.whiteBalanceMode, .automatic))
        if let tint { submit(.parameter(.whiteBalanceTint, .number(Double(tint)))) }
    }
    func setWhiteBalanceCustom(kelvin: Int, tint: Int) {
        submit(.parameter(.whiteBalanceMode, .option(.init(rawValue: "custom"))))
        submit(.parameter(.whiteBalanceKelvin, .number(Double(kelvin))))
        submit(.parameter(.whiteBalanceTint, .number(Double(tint))))
    }
    func setFocusMode(_ mode: FocusMode) { submit(.parameter(.focusMode, option(mode))) }
    func setFocusTrack(_ track: FocusTrackMode) {
        submit(.parameter(.focusTracking, option(track)))
    }
    func setFocusOption(_ value: FocusOption) { submit(.parameter(.focusOption, option(value))) }
    func setAudioChannel(_ channel: AudioChannel) {
        submit(.parameter(.audioChannels, option(channel)))
    }
    func setVocalBoost(_ boost: VocalBoost) { submit(.parameter(.vocalBoost, option(boost))) }
    func setWindNR(_ value: WindNoiseReduction) {
        submit(.parameter(.windReduction, option(value)))
    }
    func setDirectionalAudio(_ value: DirectionalAudio) {
        submit(.parameter(.audioDirection, option(value)))
    }
    func refreshFocusTrack() async {
        if capabilities.contains(.focus) { try? await backend.refreshStatus() }
    }
    func refreshAudioState() async {
        if capabilities.contains(.liveAudio) { try? await backend.refreshStatus() }
    }
    func setVideoFormat(resolution: VideoResolution, frameRate: VideoFrameRate) {
        submit(
            .videoFormat(
                resolution: resolution.sizeTitle, aspect: resolution.aspect?.rawValue ?? "",
                framesPerSecond: Double(frameRate.fps)))
    }
    func setColorMode(_ mode: ColorMode) { submit(.parameter(.colorProfile, option(mode))) }
    func updateGimbalStick(
        x: Double, y: Double, sensitivity: Int = GimbalStick.defaultSensitivity,
        assistMirror: Bool = false, linear: Bool = false
    ) {
        let scale = Double(GimbalStick.clampedSensitivity(sensitivity)) / 100
        submit(
            .gimbal(
                pan: min(1, max(-1, x * scale)) * (assistMirror ? -1 : 1),
                tilt: min(1, max(-1, y * scale))))
    }
    func prepHeadTrackGimbal() {
        if !supportsGimbalControl { cameraControlUnavailable("Gimbal controls") }
    }
    func recenterGimbal() { submit(.recenterGimbal) }
    func flipGimbal() { submit(.flipGimbal) }
    func endGimbalStick() { if supportsGimbalControl { submit(.stopGimbal) } }
    func handleFeedTap(at normalized: CGPoint) {
        submit(.focus(x: Double(normalized.x), y: Double(normalized.y)))
    }
    func startTracking(_ box: TrackingBox) {
        submit(.track(x: box.x, y: box.y, width: box.width, height: box.height))
    }
    func cancelSubjectTracking() { if supportsTapFocus { submit(.stopTracking) } }
    func handleGamepadAction(_ action: GamepadOperatorAction) {
        switch action {
        case .record: pressShutter()
        case .recenter: recenterGimbal()
        case .flip: flipGimbal()
        case .track: cameraControlUnavailable("Tracking controls")
        case .zoomChipIn: setZoom(zoomReadout + 1)
        case .zoomChipOut: setZoom(max(1, zoomReadout - 1))
        case .isoUp, .isoDown:
            if let current = status.isoIndex,
                let next = IsoIndex.stepped(
                    from: current, stops: action == .isoUp ? 1 : -1,
                    available: status.availableIsoIndices)
            {
                setISO(next)
            }
        case .shutterOpen, .shutterClose:
            let sorted = status.availableShutterDenoms.sorted()
            if let index = sorted.firstIndex(of: status.shutterDenom) {
                let next = index + (action == .shutterOpen ? -1 : 1)
                if sorted.indices.contains(next) { setShutterDenom(sorted[next]) }
            }
        }
    }
    func resetFocusPoint() { if supportsTapFocus { handleFeedTap(at: .init(x: 0.5, y: 0.5)) } }
    private func applyStatus(_ snapshot: CameraStatusSnapshot) {
        var next = CameraStatus()
        next.firmware = status.firmware
        next.batteryPercent = snapshot.batteryPercent ?? -1
        next.charging = snapshot.charging ?? false
        next.isRecording = snapshot.recording ?? false
        next.recordElapsedSec = snapshot.recordedSeconds ?? 0
        next.storageFreeMb = Int((snapshot.storageFreeBytes ?? 0) / 1_000_000)
        next.storageTotalMb = Int((snapshot.storageTotalBytes ?? 0) / 1_000_000)
        next.timecode = snapshot.timecode
        next.fps = Int(snapshot.captureFramesPerSecond ?? 0)
        for (parameter, value) in snapshot.parameters {
            switch (parameter, value) {
            case (.iso, .number(let number)):
                next.iso = Int(number)
                next.isoIndex = IsoIndex.allCases.first { $0.isoValue == Int(number) }
            case (.iso, .automatic): next.isoIndex = .auto
            case (.isoCeiling, .number(let ceiling)):
                next.isoLimit = IsoLimit.allCases.first { $0.ceiling == Int(ceiling) }
            case (.shutterSeconds, .number(let seconds)):
                if seconds > 0 { next.shutterDenom = Int((1 / seconds).rounded()) }
            case (.exposureCompensationStops, .number(let stops)):
                next.evComp = EvComp(thirds: Int((stops * 3).rounded()))
            case (.exposureMode, .option(let mode)):
                next.expoMode = ExpoMode.allCases.first { String(describing: $0) == mode.rawValue }
            case (.shootingMode, .option(let mode)):
                next.shootingMode =
                    ShootingMode.allCases.first { String(describing: $0) == mode.rawValue }.map {
                        Int($0.rawValue)
                    } ?? -1
            case (.colorProfile, .option(let mode)):
                next.colorMode = ColorMode.allCases.first {
                    String(describing: $0) == mode.rawValue
                }
            case (.focusMode, .option(let mode)):
                next.focusMode = FocusMode.allCases.first {
                    String(describing: $0) == mode.rawValue
                }
            case (.focusTracking, .option(let mode)):
                next.focusTrack = FocusTrackMode.allCases.first {
                    String(describing: $0) == mode.rawValue
                }
            case (.whiteBalanceKelvin, .number(let kelvin)): next.whiteBalanceKelvin = Int(kelvin)
            case (.whiteBalanceTint, .number(let tint)): next.whiteBalanceTint = Int(tint)
            case (.audioChannels, .option(let mode)):
                next.audioChannel = AudioChannel.allCases.first {
                    String(describing: $0) == mode.rawValue
                }
            case (.vocalBoost, .option(let mode)):
                next.vocalBoost = VocalBoost.allCases.first {
                    String(describing: $0) == mode.rawValue
                }
            case (.windReduction, .option(let mode)):
                next.windNR = WindNoiseReduction.allCases.first {
                    String(describing: $0) == mode.rawValue
                }
            case (.audioDirection, .option(let mode)):
                next.directionalAudio = DirectionalAudio.allCases.first {
                    String(describing: $0) == mode.rawValue
                }
            default: break
            }
        }
        if let mode = snapshot.parameters[.whiteBalanceMode] {
            switch mode {
            case .automatic: next.whiteBalance = .auto(tint: next.whiteBalanceTint ?? 0)
            case .option(let value) where value.rawValue == "auto":
                next.whiteBalance = .auto(tint: next.whiteBalanceTint ?? 0)
            case .option(let value) where value.rawValue == "custom":
                next.whiteBalance = .custom(
                    kelvin: next.whiteBalanceKelvin, tint: next.whiteBalanceTint ?? 0)
            default: break
            }
        }
        status = next
    }
    func clearMediaCache() {
        cameraMedia.clearCache(cameraID: mediaCameraID, preservingCatalog: true)
        mediaDownloadProgress = [:]
    }
    func mediaCacheByteCount() -> UInt64 { cameraMedia.cacheByteCount(cameraID: mediaCameraID) }
}
