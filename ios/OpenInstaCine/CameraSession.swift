import AVFoundation
import CoreGraphics
import Foundation
import Insta360Apple
import Insta360Protocol
import MonitorUI
import Observation
import OpenCineAppKit
import struct OpenCineCore.CameraSessionID
import struct OpenCineCore.CameraValuePin
import OpenCineMedia
import OpenPocketViewCore
import UIKit
import os

/// Luna-owned session facade. Same view-facing surface as OpenPocketCine's
/// `CameraSession`, so every shared screen binds unchanged; the Osmo DUML spine is
/// replaced by `LunaCameraBackend` (BLE consent → camera Wi-Fi → UCD2 on TCP 6666).
///
/// Controls live in `CameraSessionControls.swift`, media in `CameraMedia.swift`,
/// Luna ↔ shell value mapping in `LunaShellMapping.swift`.
@MainActor
@Observable
final class CameraSession {
    var phase: ConnectionPhase = .idle {
        didSet {
            if oldValue != phase { onChromePublished?() }
        }
    }
    /// Watch relay and other chrome observers. Fires after a status publish or phase change.
    @ObservationIgnored var onChromePublished: (() -> Void)?
    /// Latest camera state. SwiftUI is notified at 5 Hz unless REC / mode / color / format
    /// flipped (`LiveChromeThrottle`), same as the Osmo shell.
    var status: CameraStatus {
        get {
            access(keyPath: \.status)
            return statusStorage
        }
        set {
            let previous = statusStorage
            statusStorage = newValue
            if let lock = autoExposureLock, !lock.holds(newValue) { autoExposureLock = nil }
            if let lock = autoWhiteBalanceLock, !lock.holds(newValue) {
                autoWhiteBalanceLock = nil
            }
            guard newValue != previous else { return }
            guard
                LiveChromeThrottle.shouldNotify(
                    previous: previous, next: newValue,
                    elapsed: CFAbsoluteTimeGetCurrent() - lastStatusMutation)
            else {
                scheduleStatusFlush()
                return
            }
            publishStatusNow()
        }
    }
    var found: [FoundCamera] = []
    /// AE Lock pins the applied Auto exposure as Manual; cleared when status stops holding it.
    var autoExposureLock: AutoExposureLock?
    /// WB Mode AWB Lock. Cleared like `autoExposureLock` when status stops holding it.
    var autoWhiteBalanceLock: AutoWhiteBalanceLock?
    private(set) var connectedCamera: FoundCamera?
    private(set) var joinedSSID: String?
    /// The shared connection flow's port (`LunaIntegration`) listens here: every backend event
    /// after this session has applied it.
    @ObservationIgnored var eventHandler: ((CameraBackendEvent) -> Void)?

    /// Only for the host's explicit Show Wi-Fi code sheet. Never advertised or logged.
    var watcherWiFiJoinCode: String? {
        guard let id = connectedCamera?.id, let wifi = backend.storedWiFi(cameraID: id)
        else { return nil }
        return CameraWiFiQRCode.payload(ssid: wifi.ssid, password: wifi.password)
    }
    var cachedSSID: String? { backend.credentials?.ssid }

    // Pipeline diagnostics. Not observed by live chrome.
    @ObservationIgnored var videoPackets = 0
    @ObservationIgnored var accessUnits = 0
    @ObservationIgnored var framesEnqueued = 0
    @ObservationIgnored var droppedIncomplete = 0
    @ObservationIgnored var decoderErrors = 0
    @ObservationIgnored var hasVideoFormat = false
    @ObservationIgnored var nalTypes = ""
    @ObservationIgnored var lastKeyframeAge = "—"
    @ObservationIgnored var incidentSettingsCovered = false
    var liveFPS = "—"
    /// Observable mirror of the decoded raster (`HevcDecoder` is not observable).
    private(set) var pictureAspect: CGFloat = LiveChromeMetrics.feedAspect
    private(set) var isVerticalPicture = false
    var liveSignalBars = 0
    @ObservationIgnored private var frameRate = FrameRateSampler()
    @ObservationIgnored private var signalBarsFilter = LinkSignalBars()
    @ObservationIgnored private var lastGoodFrameAt: Date?
    @ObservationIgnored private var consecutiveBadLiveFrames = 0
    @ObservationIgnored private var lastDecoderErrorCount = 0
    @ObservationIgnored private var recentCommandFailures = 0
    @ObservationIgnored private var statusStorage = CameraStatus()
    @ObservationIgnored private var lastStatusMutation: CFAbsoluteTime = 0
    @ObservationIgnored private var statusFlushTask: Task<Void, Never>?
    @ObservationIgnored private var linkTicker: Task<Void, Never>?
    @ObservationIgnored private var lastIFrameRequestAt = Date.distantPast

    @ObservationIgnored let backend: LunaCameraBackend
    /// False for a lease (borrowed decoder or controls-only editor) on another session's backend.
    @ObservationIgnored let ownsBackend: Bool
    /// Tests only: the Luna session requests go through instead of the backend's.
    @ObservationIgnored var lunaSessionOverride: LunaCameraSession?
    /// Per-integration labels and media addressing for this camera (STATE-01: no launch globals).
    @ObservationIgnored let profile: CameraLabelProfile
    /// This session's own drum coalescing and settings-read debounce (never shared).
    @ObservationIgnored let exposureCoalescer = LunaExposureCoalescer()
    @ObservationIgnored let refreshDebounce = LunaRefreshDebounce()
    /// Learned picture EV for this source only.
    @ObservationIgnored var pictureEV = PictureEVMeter()

    /// The assumptions behind this source's picture EV: camera, recording profile, metering.
    func pictureEVContext(transfer: MonitorTransfer) -> PictureEVContext {
        PictureEVContext(
            device: connectedCamera?.id.uuidString ?? "unknown", transfer: transfer,
            profile: status.colorMode.map { String($0.rawValue) } ?? "unknown",
            metering: faceMetering.map { $0 ? "face" : "matrix" } ?? "unknown")
    }
    @ObservationIgnored let log = Logger(subsystem: "com.opencapture.openinstacine", category: "session")
    @ObservationIgnored var scanTask: Task<Void, Never>?
    @ObservationIgnored var runTask: Task<Void, Never>?
    @ObservationIgnored var connectGeneration = 0
    @ObservationIgnored var reconnectTarget: UUID?
    @ObservationIgnored private var descriptors: [UUID: MonitorCamera] = [:]
    @ObservationIgnored private var expectedDisconnect = false
    @ObservationIgnored private var incidentSessionActive = false
    @ObservationIgnored private var sessionRecoveryTask: Task<Void, Never>?
    @ObservationIgnored private var sessionRecoveryGeneration = 0
    @ObservationIgnored private var recoveryCardGraceTask: Task<Void, Never>?
    @ObservationIgnored private var sessionDropStormGuard = SessionDropStormGuard()
    @ObservationIgnored private var recoveryCameraID: UUID?
    @ObservationIgnored private var needsForegroundRecover = false
    private static let recoveryCardGrace: Duration = .seconds(2.5)
    private static let recoveryScanDeadline: Duration = .seconds(30)
    private static let recoveryAttemptDeadline: Duration = .seconds(90)
    private(set) var isReconnecting = false
    private(set) var connectionTargetID: UUID?
    var sessionRecovery: SessionRecoveryState = .idle
    var holdsMonitor = false
    var sessionRecoveryCardGraceElapsed = false
    var recoveryDeviceName = ""
    private(set) var feedRecovering = false
    private(set) var isFeedWarming = true
    /// In-flight photo. A record start or stop in flight is the shared controls' `recordPending`.
    var photoBusy = false
    /// In-flight record or photo. UI disables the rec lamp while true.
    var controlBusy: Bool {
        get { photoBusy || control.recordPending }
        set { photoBusy = newValue }
    }
    var controlNote: String?
    var isLocked = false
    var isMultiviewBorrowed: Bool { false }
    /// Luna has no Multiview; kept so the shared shell compiles unchanged.
    private(set) var isMultiviewControlsOnly = false
    @ObservationIgnored var multiviewControlAdmission: (() -> Bool)?
    var multiviewPose: GimbalStickMapping { GimbalStickMapping() }

    /// ISO, shutter, white balance and record: the shared monitor controls, bound by the shell
    /// to the connected camera's common session (CameraSessionCore.swift).
    @ObservationIgnored let control = MonitorControlModel()

    // Luna settings bookkeeping (see LunaShellMapping).
    @ObservationIgnored var lunaSettings = LunaPhotographySettings.empty
    @ObservationIgnored var lunaDevice: LunaDeviceStatus?
    @ObservationIgnored var recordStartedAt: Date?
    @ObservationIgnored var pins = LunaControlPins()
    /// Accepted record formats for the current mode (VideoFormat ↔ Luna RecordResolution).
    @ObservationIgnored var formatTable: [VideoFormat: UInt64] = [:]
    /// Camera-reported gimbal mode/speed (Luna option 91). Nil until the first read.
    var gimbalMode: GimbalMode = .follow
    var gimbalSpeed: GimbalSpeed = .defaultSpeed
    /// Luna metering: true Face Priority, false Matrix, nil before the first read.
    var faceMetering: Bool?
    var gimbalRamp: GimbalRamp = OperatorPrefs.gimbalRamp
    var gimbalDoubleTap: GimbalDoubleTap = OperatorPrefs.gimbalDoubleTap
    var gimbalProgram = GimbalProgram()
    var gimbalMoveRunning = false
    var gimbalMovePaused = false
    var gimbalMoveCanPause = false
    var gimbalStartCountdown: Int?
    private(set) var gimbalControlSceneActive = true
    private(set) var gimbalPoseViewFlip = false
    private(set) var gimbalPoseInvertPan = false
    /// Camera-head world pitch from the IMU stream (Level) and the fallback pose.
    @ObservationIgnored var gimbalPose = LunaGimbalPoseEstimator()
    #if DEBUG
        @ObservationIgnored var headTrackLog: [[Double]] = []
        @ObservationIgnored var headSampleLog: [[Double]] = []
        @ObservationIgnored var imuRateLog: [[Double]] = []
        @ObservationIgnored var headTrackRecording = false
    #endif
    @ObservationIgnored var lastIMUAt: TimeInterval?
    /// Handle-relative gimbal angle from cmd 226 GET_ANGLE, polled while live.
    @ObservationIgnored var gimbalAngle: (angle: LunaGimbalAngle, at: TimeInterval)?
    @ObservationIgnored var gimbalAnglePoll: Task<Void, Never>?
    /// Latest SET_ANGLE target (head tracking) and its token; a sender streams it.
    @ObservationIgnored var gimbalAim: (target: GimbalWaypoint, token: UInt64)?
    @ObservationIgnored var gimbalAimTask: Task<Void, Never>?
    @ObservationIgnored var gimbalAimGeneration: UInt64 = 0
    /// Head-tracking targets stamped with their AirPods measurement time (last second).
    @ObservationIgnored var headTrackSamples: [HeadTrack.Sample] = []
    @ObservationIgnored var isSteeringHead = false
    /// Live frame stamps to time-of-day timecode, reset per live start.
    @ObservationIgnored var frameTimecode = LunaFrameTimecode()
    /// Phone wall-clock seconds minus the live frame clock (earliest arrival).
    var frameClockOffset: Double? { frameTimecode.offset }
    @ObservationIgnored var lastFeedTap: (at: Double, x: Double, y: Double)?
    #if DEBUG
        @ObservationIgnored var lastFrameClock: UInt64 = 0
    #endif
    /// Programmed A/B/C move runner (SET_ANGLE stream).
    @ObservationIgnored var gimbalMoveTask: Task<Void, Never>?
    @ObservationIgnored var gimbalMoveClock = 0.0
    var gimbalYawTenthDeg: Int16? { freshGimbalWaypoint.map { Int16(($0.yawDeg * 10).rounded()) } }
    var gimbalPitchTenthDeg: Int16? { freshGimbalWaypoint.map { Int16(($0.pitchDeg * 10).rounded()) } }
    /// Camera GET_ANGLE when fresh (handle frame, degrees, yaw unwrapped across the
    /// mechanical stop so moves never interpolate through it); IMU estimate otherwise.
    var liveGimbalWaypoint: GimbalWaypoint? {
        if let reading = gimbalAngle, ProcessInfo.processInfo.systemUptime - reading.at <= 0.5 {
            let pitch = Double(reading.angle.pitch)
            return GimbalWaypoint(
                yawDeg: GimbalWaypoint.unwrapYaw(Double(reading.angle.yaw)), pitchDeg: pitch, zoom: zoomReadout,
                nativePitchDeg: -pitch)
        }
        guard lastIMUAt != nil, gimbalPose.sampleCount > 0 else { return nil }
        return GimbalWaypoint(
            yawDeg: gimbalPose.yawDeg, pitchDeg: gimbalPose.pitchDeg, zoom: zoomReadout,
            nativePitchDeg: -gimbalPose.pitchDeg)
    }
    var freshGimbalWaypoint: GimbalWaypoint? {
        let now = ProcessInfo.processInfo.systemUptime
        let angleFresh = gimbalAngle.map { now - $0.at <= 0.5 } ?? false
        let imuFresh = lastIMUAt.map { now - $0 <= 0.3 } ?? false
        return angleFresh || imuFresh ? liveGimbalWaypoint : nil
    }
    var overlayGimbalWaypoint: GimbalWaypoint? { nil }
    @ObservationIgnored var lastGimbalAttitudeHex = ""
    @ObservationIgnored var lastGimbalAttitudeDump = ""
    @ObservationIgnored private(set) var levelReading = LevelReading()
    var gimbalLimitPulse: UInt = 0
    var gimbalLimitContact: GimbalLimitWatch.Contact = []
    var gimbalLimitPanSign: Double = 0
    var gimbalLimitTiltSign: Double = 0
    @ObservationIgnored var gimbalStick = LunaStickStream()
    /// Gimbal requests (MOVE stream, release, SET_ANGLE, GET_ANGLE) on the session's control path.
    @ObservationIgnored lazy var motion = LunaMotionService(session: { [weak self] in self?.lunaSession })

    // The shared actual library/cache owner. Source/playback compatibility stays in CameraMedia.
    var mediaLibrary: MonitorMediaLibraryModel<LunaMediaLibraryPayload>!
    @ObservationIgnored var mediaLibraryKey: String?
    @ObservationIgnored var mediaLibraryServiceID: CameraSessionID?
    private(set) var cameraGalleryOpen = false
    @ObservationIgnored let cameraMedia: CameraMedia
    var playbackMediaNote: String?

    // Focus / tracking / face AF
    var focusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    var searchBox: TrackingBox?
    var subjectBox: TrackingBox?
    var isTracking = false
    var faceBox: TrackingBox?
    private(set) var sceneFaces: [TrackingBox] = []
    /// Deep Track and tap focus on the connection's Luna session; the boxes above follow it.
    @ObservationIgnored lazy var subjectTracking = LunaSubjectTracking(
        session: { [weak self] in self?.lunaSession },
        changed: { [weak self] in self?.showTracking($0) })
    @ObservationIgnored var lastTapFocusAt: Date?
    @ObservationIgnored var tapFocusTask: Task<Void, Never>?
    @ObservationIgnored private let faceDetector = LiveFaceDetector()
    @ObservationIgnored private var faceTracks: [FaceTrack] = []
    @ObservationIgnored private var faceTarget: TrackingBox?
    @ObservationIgnored private var lastFaceAt: Date?
    @ObservationIgnored private var lastFaceHitAt: Date?
    @ObservationIgnored private var faceAFArmTask: Task<Void, Never>?
    private var faceAFArmed = false
    @ObservationIgnored var evBeforeFacePriority: EvComp?
    @ObservationIgnored private var lastFacePriorityEVAt = Date.distantPast
    @ObservationIgnored private var facePriorityAcquireAt: Date?

    var focusOverlay: FocusOverlay {
        if FaceAFPolicy.shouldHoldTapBox(secondsSinceTap: lastTapFocusAt.map { Date().timeIntervalSince($0) }) {
            let base = FocusOverlayPolicy.resolve(
                tracking: isTracking, search: searchBox, subject: subjectBox)
            switch base {
            case .search, .subject: return base
            case .focus, .face: return .focus
            }
        }
        return FaceAFPolicy.resolve(
            focusMode: status.focusMode, tracking: isTracking, search: searchBox,
            subject: subjectBox, face: faceBox)
    }
    var dimmedFaces: [TrackingBox] {
        let hiding: TrackingBox?
        if case .face(let box) = focusOverlay { hiding = box } else { hiding = nil }
        let occluder: TrackingBox?
        switch focusOverlay {
        case .subject(let box): occluder = box
        case .search(let box): occluder = box
        default: occluder = subjectBox
        }
        return SceneFacePolicy.dimmed(faces: sceneFaces, hiding: hiding, occluder: occluder)
    }
    /// Luna video AF is continuous; Vision face boxes ride on top of it.
    var wantsFaceAF: Bool { status.focusMode == .continuous && faceAFArmed }
    var wantsFaceDetect: Bool { wantsFaceAF || wantsFacePriorityMeter }
    var wantsFacePriorityMeter: Bool {
        OperatorPrefs.facePriorityExposureEnabled && status.expoMode == .auto
    }
    var isTrackingActive: Bool { isTracking || searchBox != nil || subjectBox != nil }

    // Zoom
    var zoomStop: Double = 1
    var zoomPinchPreview: Double?
    @ObservationIgnored var zoomPinchAnchor = 1.0
    @ObservationIgnored var lastZoomWriteAt = Date.distantPast
    @ObservationIgnored var pendingZoomWrite: Double?
    @ObservationIgnored var zoomWriteTask: Task<Void, Never>?
    var zoomPin: CameraValuePin<Double>?
    var zoomOptimistic: Double? { zoomPin?.expected }
    var zoomColorHopPending: Bool { false }
    /// Highest zoom the body accepts (fw 1.1.15 raised this; see LunaShellMapping).
    @ObservationIgnored var zoomCeiling = LunaShellMapping.defaultZoomCeiling
    var isFormatPinActive: Bool { pins.format != nil }

    @ObservationIgnored let decoder: HevcDecoder
    var videoLayer: AVSampleBufferDisplayLayer { decoder.displayLayer }

    /// `backend` is the one owner of its camera connection, created by the composition root
    /// (`AppModel.makeBackend()`). A session that borrows a decoder or only edits controls is a
    /// lease on it: it never rebinds the backend's callbacks and never connects.
    init(
        backend: LunaCameraBackend, profile: CameraLabelProfile = LunaShellMapping.profile,
        borrowing sharedDecoder: HevcDecoder? = nil, cameraMedia: CameraMedia? = nil,
        mediaStorage: MonitorMediaCacheStorage? = nil,
        controlsOnly: Bool = false
    ) {
        isMultiviewControlsOnly = controlsOnly
        ownsBackend = sharedDecoder == nil && !controlsOnly
        self.profile = profile
        self.cameraMedia = cameraMedia ?? CameraMedia(storage: mediaStorage)
        self.decoder = sharedDecoder ?? HevcDecoder()
        self.backend = backend
        adoptControl()
        decoder.onPresentedFrame = { [weak self] in self?.noteLiveFrame() }
        decoder.onPictureSizeChanged = { [weak self] in
            guard let self else { return }
            if self.pictureAspect != self.decoder.pictureAspect {
                self.pictureAspect = self.decoder.pictureAspect
            }
            if self.isVerticalPicture != self.decoder.isVerticalPicture {
                self.isVerticalPicture = self.decoder.isVerticalPicture
            }
        }
        decoder.onSourceFrame = { [weak self] lease in
            if let buffer = lease.pixelBuffer { self?.considerFaceAF(buffer) }
        }
        // A decoder handoff (look/scope toggle) needs an IDR. Luna sends a GOP every
        // ~2 s; ask once for an I-frame so the switch is not a two-second hold.
        decoder.onHandoffNeedsIDR = { [weak self] in self?.requestKeyframe(reason: "assist VT start") }
        decoder.onParameterSetsChanged = { [weak self] in
            self?.requestKeyframe(reason: "encoder format change")
        }
        configureMediaLibrary()
        activateBackend()
    }

    /// Only the backend's owner binds its callbacks (at scan/connect). A lease never does.
    func activateBackend() {
        guard ownsBackend else { return }
        backend.eventHandler = { [weak self] in self?.receiveBackend($0) }
        backend.onDeviceStatus = { [weak self] in self?.applyDeviceStatus($0) }
        backend.onSettings = { [weak self] in self?.applySettings($0) }
        backend.onCapture = { [weak self] in self?.applyCapture($0) }
        backend.onNotification = { [weak self] in self?.applyNotification($0) }
        backend.onTrackFrame = { [weak self] in self?.applyTrackFrame($0) }
        backend.onIMU = { [weak self] in self?.ingestIMU($0) }
        backend.onLog = { ControlLiveLog.line($0) }
    }

    // MARK: - Discovery and connection

    /// Scan for Luna cameras (BLE BE80) outside the shared flow (foreground and internet-hop
    /// reconnects of the live camera). If `id` is set, connect as soon as it appears.
    func startScan(reconnect id: UUID?) {
        guard ownsBackend else { return }
        activateBackend()
        connectGeneration += 1
        runTask?.cancel()
        reconnectTarget = id
        connectionTargetID = id
        isReconnecting = id != nil
        phase = .scanning
        found = []
        scanTask?.cancel()
        let token = connectGeneration
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.backend.startScan()
            } catch {
                guard token == self.connectGeneration, !Task.isCancelled else { return }
                // A saved camera can still reconnect over its saved Wi-Fi without BLE.
                if let id, backend.storedWiFi(cameraID: id) != nil, let camera = self.knownCamera(id) {
                    self.connect(camera)
                    return
                }
                self.phase = .failed(
                    "Turn on Bluetooth and allow OpenInstaCine to use it, then try connecting again.")
                self.isReconnecting = false
            }
        }
        // Give Bluetooth a few seconds (it wakes the camera Wi-Fi); a camera that never
        // advertises can still come back over its saved Wi-Fi.
        if let id, backend.storedWiFi(cameraID: id) != nil, let camera = knownCamera(id) {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard let self, token == self.connectGeneration, self.reconnectTarget == id else {
                    return
                }
                self.connect(camera)
            }
        }
    }

    /// The camera this session connected or saw, for reconnects that run without a scan hit.
    private func knownCamera(_ id: UUID) -> FoundCamera? {
        if let camera = connectedCamera, camera.id == id { return camera }
        return found.first { $0.id == id }
    }

    func reconnect(to id: UUID) {
        if case .live = phase, connectedCamera?.id == id, !sessionRecovery.isRecovering { return }
        if let camera = found.first(where: { $0.id == id }) {
            connect(camera)
            return
        }
        startScan(reconnect: id)
    }

    func connect(_ camera: FoundCamera) {
        connect(camera, preserveMonitor: holdsMonitor)
    }

    private func connect(_ camera: FoundCamera, preserveMonitor: Bool) {
        if case .live = phase, connectedCamera?.id == camera.id, !sessionRecovery.isRecovering {
            return
        }
        guard ownsBackend else { return }
        // A reconnect of the same camera keeps the common session the shell holds: it follows
        // the link (recovering, then a new control epoch).
        if !preserveMonitor { resetForConnection() }
        let generation = prepareConnection(to: camera, preserveMonitor: preserveMonitor)
        let descriptor =
            descriptors[camera.id]
            ?? MonitorCamera(
                id: camera.id, name: camera.name, model: LunaProtocol.model,
                capabilities: backend.capabilities)
        runTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == self.connectGeneration { self.runTask = nil } }
            do {
                self.expectedDisconnect = true
                self.backend.disconnect()
                self.expectedDisconnect = false
                try await self.backend.connect(to: descriptor)
            } catch is CancellationError {
                return
            } catch {
                guard generation == self.connectGeneration, !Task.isCancelled else { return }
                if case .idle = self.phase { return }
                let why = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                ControlLiveLog.line("session: connect failed at \(self.phase.label): \(why)")
                if preserveMonitor { return }
                self.phase = .failed(why)
                self.applyLinkPresentation()
            }
        }
    }

    /// A fresh status, link health and decoder for the next connection.
    private func resetForConnection() {
        statusStorage = CameraStatus()
        publishStatusNow()
        resetLinkHealthMeasurements()
        decoder.reset()
    }

    /// What every connect sets before the backend runs; returns its generation.
    private func prepareConnection(to camera: FoundCamera, preserveMonitor: Bool) -> Int {
        AppDiagnostics.reporting.setCameraSessionActive(true)
        connectGeneration += 1
        LocalVPNProbe.noteIfActive()
        backend.stopScan()
        scanTask?.cancel()
        runTask?.cancel()
        reconnectTarget = nil
        isReconnecting = preserveMonitor
        connectedCamera = camera
        configureMediaLibrary()
        connectionTargetID = camera.id
        if !incidentSessionActive { beginFeedIncidentSession() }
        if preserveMonitor { decoder.flushForRecovery() }
        faceAFArmed = false
        phase = .connectingGatt
        return connectGeneration
    }

    func disconnect() {
        AppDiagnostics.reporting.setCameraSessionActive(false)
        AppDiagnostics.incidents.endSession(now: ProcessInfo.processInfo.systemUptime)
        incidentSessionActive = false
        connectGeneration += 1
        reconnectTarget = nil
        connectionTargetID = nil
        isReconnecting = false
        cancelSessionRecovery()
        holdsMonitor = false
        scanTask?.cancel()
        runTask?.cancel()
        runTask = nil
        expectedDisconnect = true
        backend.stopScan()
        backend.disconnect()
        expectedDisconnect = false
        if let ssid = joinedSSID { WiFiJoiner.leave(ssid: ssid) }
        joinedSSID = nil
        connectedCamera = nil
        phase = .idle
        statusFlushTask?.cancel()
        statusFlushTask = nil
        statusStorage = CameraStatus()
        publishStatusNow()
        lunaSettings = .empty
        lunaDevice = nil
        recordStartedAt = nil
        pins = LunaControlPins()
        formatTable = [:]
        zoomStop = 1
        zoomPinchPreview = nil
        zoomPin = nil
        pendingZoomWrite = nil
        zoomWriteTask?.cancel()
        gimbalStick.reset()
        motion.endHold()
        gimbalAnglePoll?.cancel()
        gimbalAnglePoll = nil
        gimbalAngle = nil
        cancelProgrammedMove()
        gimbalProgram = GimbalProgram()
        controlBusy = false
        controlNote = nil
        focusPoint = CGPoint(x: 0.5, y: 0.5)
        clearLocalTracking()
        clearFaceAF()
        faceAFArmTask?.cancel()
        faceAFArmTask = nil
        faceAFArmed = false
        tapFocusTask?.cancel()
        isLocked = false
        videoPackets = 0
        accessUnits = 0
        framesEnqueued = 0
        hasVideoFormat = false
        needsForegroundRecover = false
        resetLinkHealthMeasurements()
        decoder.reset()
        resetMediaSession()
    }

    #if targetEnvironment(simulator)
        /// UI review only: pretend-live state for simulator screenshots.
        func reviewLive(camera: FoundCamera, status: CameraStatus) {
            connectedCamera = camera
            self.status = status
            phase = .live
        }
    #endif

    // MARK: - Backend events

    private func receiveBackend(_ event: CameraBackendEvent) {
        guard !expectedDisconnect else { return }
        defer { eventHandler?(event) }
        switch event {
        case .discovered(let camera):
            descriptors[camera.id] = camera
            let item = FoundCamera(
                id: camera.id, name: LunaIntegration.title(advertised: camera.name),
                model: LunaShellMapping.cameraModel, modelId: nil)
            if let index = found.firstIndex(where: { $0.id == item.id }) {
                if found[index].name != item.name { found[index] = item }
            } else {
                found.append(item)
            }
            if let target = reconnectTarget, target == item.id {
                reconnectTarget = nil
                connect(item)
            }
        case .phase(let value):
            switch value {
            case .idle: break
            case .scanning: if !isReconnecting || connectedCamera == nil { phase = .scanning }
            case .connecting: phase = .connectingGatt
            case .negotiating: phase = .pairing
            case .awaitingApproval: phase = .awaitingApproval
            case .readingWiFi: phase = .readingWifiCreds
            case .joiningWiFi: phase = .joiningWifi
            case .openingVideo: phase = .openingDatalink
            case .streaming:
                phase = .live
                isReconnecting = false
                recordFeedBreadcrumb(.sceneActivity, detail: "live")
                startLinkTicker()
                startGimbalAnglePoll()
                syncCameraClock()
                applyLinkPresentation()
            }
        case .information(let info):
            status.firmware = info.firmware
        case .joinedWiFi(let ssid):
            joinedSSID = ssid
        case .videoAccessUnit(let data, let milliseconds):
            noteFrameClock(milliseconds)
            ingestAccessUnit(data)
        case .disconnected(let reason):
            guard connectedCamera != nil else { return }
            ControlLiveLog.line("session: camera link dropped: \(reason)")
            beginSessionRecovery(reason: reason, trigger: .datalinkLost)
        case .note(let note):
            controlNote = note
        }
    }

    private func ingestAccessUnit(_ data: Data) {
        videoPackets += 1
        guard !isBrowsingMedia else { return }
        accessUnits += 1
        if decoder.decode(accessUnit: [UInt8](data)) { framesEnqueued += 1 }
        if !hasVideoFormat, decoder.hasFormat { hasVideoFormat = true }
    }

    /// Luna `IFRAME_REQUEST` (105). Rate limited: the body already sends a GOP every ~2 s.
    func requestKeyframe(reason: String) {
        guard hasControlLink, !isBrowsingMedia else { return }
        guard Date().timeIntervalSince(lastIFrameRequestAt) > 1 else { return }
        lastIFrameRequestAt = Date()
        ControlLiveLog.line("feed: I-frame request (\(reason))")
        Task { [weak self] in _ = try? await self?.sendLuna(LunaProtocol.keyframeRequest) }
    }

    // MARK: - Status mapping (Luna → shared CameraStatus)

    private func applyDeviceStatus(_ device: LunaDeviceStatus) {
        lunaDevice = device
        var next = status
        LunaShellMapping.apply(device: device, to: &next)
        if let mode = device.shootingMode {
            let wire = Int(LunaShellMapping.shootingMode(mode).rawValue)
            let held = CameraValuePin.reconcile(
                &pins.shootingMode, reported: wire, now: Date.timeIntervalSinceReferenceDate)
            if held != nil {
                // Keep the operator's pending mode until the camera reports it.
            } else if next.shootingMode != wire {
                next.clearModeDependentCapabilities()
                next.shootingMode = wire
            }
        }
        status = next
    }

    private func applySettings(_ settings: LunaPhotographySettings) {
        if let mode = settings.functionMode, mode != backend.functionMode { return }
        lunaSettings.merge(settings)
        var next = status
        LunaShellMapping.apply(settings: lunaSettings, to: &next, pins: &pins, table: &formatTable)
        if let zoom = settings.zoom { reconcileZoom(zoom, into: &next) }
        if let gimbal = lunaSettings.gimbal {
            if let mode = gimbal.gimbalMode.flatMap(LunaShellMapping.gimbalMode) {
                if CameraValuePin.reconcile(
                    &pins.gimbalMode, reported: mode, now: Date.timeIntervalSinceReferenceDate,
                    confirms: { $0 == $1 }) == nil, gimbalMode != mode
                {
                    gimbalMode = mode
                }
            }
            if let speed = gimbal.gimbalFollowSpeed.map(LunaShellMapping.gimbalSpeed) {
                if CameraValuePin.reconcile(
                    &pins.gimbalSpeed, reported: speed, now: Date.timeIntervalSinceReferenceDate,
                    confirms: { $0 == $1 }) == nil, gimbalSpeed != speed
                {
                    gimbalSpeed = speed
                }
            }
        }
        if let face = lunaSettings.faceMetering {
            let shown = CameraValuePin.reconcile(
                &pins.faceMetering, reported: face, now: Date.timeIntervalSinceReferenceDate) ?? face
            if faceMetering != shown { faceMetering = shown }
        }
        if let limits = settings.gimbalStatus { applyGimbalLimits(limits) }
        applyCorePresentation(to: &next)
        status = next
        applyDecoderColorScience()
    }

    /// After a pending ISO, shutter or WB edit ends: the last Luna readouts plus the Core overlay.
    func refreshShownSettings() {
        var next = status
        if !lunaSettings.types.isEmpty {
            LunaShellMapping.apply(settings: lunaSettings, to: &next, pins: &pins, table: &formatTable)
        }
        applyCorePresentation(to: &next)
        status = next
    }

    private func reconcileZoom(_ zoom: Double, into next: inout CameraStatus) {
        next.zoomFactorOverride = zoom
        if zoomPin != nil {
            var pin = zoomPin
            _ = CameraValuePin.reconcile(
                &pin, reported: zoom, now: Date.timeIntervalSinceReferenceDate,
                confirms: { abs($0 - $1) < 0.05 })
            if pin == nil { zoomPin = nil }
        }
        if zoomPinchPreview == nil {
            let stop = LunaShellMapping.nearestStop(zoom, stops: zoomStops)
            if stop != zoomStop { zoomStop = stop }
        }
    }

    /// Record timer only. Recording itself is reported through the Core session.
    private func applyCapture(_ capture: LunaCaptureStatus) {
        var next = status
        let recording = capture.isRecording
        if recording, recordStartedAt == nil {
            recordStartedAt = Date().addingTimeInterval(-Double(capture.captureSeconds))
        }
        if !recording { recordStartedAt = nil }
        next.recordElapsedSec =
            recording
            ? max(Int(capture.captureSeconds), recordStartedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0)
            : 0
        status = next
        if photoBusy, !pins.photoInFlight { photoBusy = false }
    }

    private func applyNotification(_ note: LunaNotification) {
        switch note {
        case .tracking(let state, _, _):
            applyTrackingState(state)
        case .gimbalStatus(let limits):
            applyGimbalLimits(limits)
        case .captureStopped(let error, _):
            if error != 0 { controlNote = "Recording stopped by the camera (code \(error))." }
            Task { await refreshMediaAfterCapture() }
        default:
            break
        }
    }

    private func applyGimbalLimits(_ limits: LunaGimbalStatus) {
        var contact: GimbalLimitWatch.Contact = []
        if limits.yawLimit { contact.insert(.pan) }
        if limits.pitchLimit { contact.insert(.tilt) }
        if contact != gimbalLimitContact {
            if !contact.subtracting(gimbalLimitContact).isEmpty { gimbalLimitPulse &+= 1 }
            gimbalLimitContact = contact
            gimbalLimitPanSign = gimbalStick.lastPan
            gimbalLimitTiltSign = gimbalStick.lastTilt
        }
    }

    /// Scopes / false colour / Auto LUT follow the preview transfer. Luna bakes
    /// Color Recovery into the phone feed, so I-Log recording previews Rec.709
    /// unless the operator has turned Recovery off.
    func applyDecoderColorScience() {
        decoder.incomingColorMode = LunaShellMapping.previewColorMode(
            recording: status.colorMode, recoveryOff: OperatorPrefs.lunaFlatPreview)
    }

    // MARK: - Feed health

    private func startLinkTicker() {
        linkTicker?.cancel()
        linkTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.refreshLinkHealth()
                self.watchFeed()
                if let started = self.recordStartedAt, self.status.isRecording {
                    let elapsed = Int(Date().timeIntervalSince(started))
                    if elapsed != self.status.recordElapsedSec {
                        self.status.recordElapsedSec = elapsed
                    }
                }
                self.publishFeedIncidentSnapshot()
            }
        }
    }

    /// Luna video is TCP: no loss, but the socket can stall. Two silent seconds ask
    /// for an I-frame; six restart the stream; the transport drop owns recovery.
    private func watchFeed() {
        guard case .live = phase, !isBrowsingMedia, !sessionRecovery.isRecovering else { return }
        guard let silence = backend.secondsSinceVideo else { return }
        if silence > 6 {
            feedRecovering = true
            ControlLiveLog.line("feed: \(Int(silence))s without video, restarting live")
            Task {
                try? await backend.restartLive()
                feedRecovering = false
            }
        } else if silence > 2 {
            requestKeyframe(reason: "stall")
        }
    }

    var isLiveVideoStale: Bool {
        guard case .live = phase else { return false }
        if feedRecovering { return true }
        guard let silence = backend.secondsSinceVideo else { return decoder.lastPresentedAt != nil }
        return silence > FeedWatchdog.stallThreshold
    }

    func resetFeedWatchdog() {
        feedRecovering = false
    }

    private func resetLinkHealthMeasurements() {
        frameRate = FrameRateSampler()
        signalBarsFilter = LinkSignalBars()
        lastGoodFrameAt = nil
        consecutiveBadLiveFrames = 0
        lastDecoderErrorCount = 0
        recentCommandFailures = 0
        liveFPS = "—"
        liveSignalBars = 0
        isFeedWarming = true
        linkTicker?.cancel()
        linkTicker = nil
    }

    private func armFaceAFAfterFirstPicture() {
        guard !faceAFArmed, faceAFArmTask == nil else { return }
        faceAFArmTask = Task { @MainActor in
            while !Task.isCancelled, !self.faceAFArmed {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                let age = self.decoder.lastPresentedAt.map { Date().timeIntervalSince($0) }
                guard CameraSoftAP.isPresentedPictureFresh(secondsSinceLastPresented: age)
                else { continue }
                self.decoder.unlockHardwareDecoder()
                self.faceAFArmed = true
            }
            self.faceAFArmTask = nil
        }
    }

    private func noteLiveFrame() {
        lastGoodFrameAt = Date()
        consecutiveBadLiveFrames = 0
        armFaceAFAfterFirstPicture()
        let before = frameRate.displayFPS
        frameRate.recordFrame(at: Date.timeIntervalSinceReferenceDate)
        if frameRate.displayFPS != before {
            applyLinkPresentation()
        } else {
            refreshFeedWarmup()
        }
    }

    func refreshLinkHealth(at timestamp: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        frameRate.age(at: timestamp)
        let errors = decoder.decoderErrors
        if errors > lastDecoderErrorCount {
            consecutiveBadLiveFrames += errors - lastDecoderErrorCount
        }
        lastDecoderErrorCount = errors
        decoderErrors = errors
        if recentCommandFailures > 0 { recentCommandFailures -= 1 }
        applyLinkPresentation()
    }

    func noteCommandFailure() {
        recentCommandFailures = min(4, recentCommandFailures + 1)
    }

    private func applyLinkPresentation() {
        if sessionRecovery.isRecovering {
            if liveFPS != SessionRecoveryCopy.heldFrameBadge {
                liveFPS = SessionRecoveryCopy.heldFrameBadge
            }
            refreshFeedWarmup()
            return
        }
        let measured = frameRate.displayFPS
        let label = LiveViewLink.fpsChipLabel(
            connection: phase, recovering: feedRecovering, formattedFPS: frameRate.formatted,
            measuredFPS: measured)
        if label != liveFPS { liveFPS = label }
        let snapshot = CameraLinkHealthScorer.score(currentLinkHealthInputs())
        let bars = signalBarsFilter.update(score: snapshot.linkHealthScore)
        if bars != liveSignalBars { liveSignalBars = bars }
        refreshFeedWarmup()
    }

    private func refreshFeedWarmup() {
        if holdsMonitor, decoder.lastPresentedAt != nil {
            if isFeedWarming { isFeedWarming = false }
            return
        }
        if !isFeedWarming, decoder.lastPresentedAt != nil { return }
        let next = LiveFeedWarmup.isWarming(
            hasPresentedPicture: decoder.lastPresentedAt != nil,
            measuredFPS: frameRate.displayFPS,
            rollingIntervals: frameRate.intervalCount,
            recovering: feedRecovering,
            secondsSinceLastPresented: decoder.lastPresentedAt.map { Date().timeIntervalSince($0) })
        if next != isFeedWarming { isFeedWarming = next }
    }

    private func currentLinkHealthInputs() -> CameraLinkHealthInputs {
        let measured = frameRate.displayFPS
        return CameraLinkHealthInputs(
            phase: LiveViewLink.cameraLinkPhase(
                connection: phase, recovering: feedRecovering, measuredFPS: measured),
            ptpRoundTripMilliseconds: nil,
            liveViewFPS: measured > 0 ? measured : nil,
            targetLiveViewFPS: LunaShellMapping.previewFPS,
            secondsSinceLastGoodFrame: lastGoodFrameAt.map { Date().timeIntervalSince($0) },
            consecutiveBadFrames: consecutiveBadLiveFrames,
            recentCommandFailures: recentCommandFailures,
            isRecoveringStream: feedRecovering)
    }

    func noteSceneBecameInactive() {
        recordFeedBreadcrumb(.sceneActivity, detail: "inactive")
        gimbalControlSceneActive = false
        endGimbalStick(cancelMove: true)
        if case .live = phase { needsForegroundRecover = true }
    }

    func noteSceneBecameActive() {
        recordFeedBreadcrumb(.sceneActivity, detail: "active")
        gimbalControlSceneActive = true
        guard needsForegroundRecover else { return }
        needsForegroundRecover = false
        guard !sessionRecovery.isRecovering else { return }
        guard case .live = phase else {
            if let id = connectedCamera?.id { reconnect(to: id) }
            return
        }
        // iOS may have suspended the socket. A fresh picture within 3 s means it held.
        let started = Date()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, case .live = self.phase else { return }
            if self.hasFreshRecoveryPicture(since: started) { return }
            if self.hasControlLink {
                try? await self.backend.restartLive()
                try? await Task.sleep(for: .seconds(3))
                if self.hasFreshRecoveryPicture(since: started) { return }
            }
            self.beginSessionRecovery(reason: "no picture after foreground", trigger: .softAPLost)
        }
    }

    func rejoinSoftAPAfterInternetHop() async {
        guard let camera = connectedCamera else { return }
        do {
            try await backend.rejoinCameraNetwork()
        } catch {
            ControlLiveLog.line("session: rejoin after internet hop failed \(error.localizedDescription)")
            reconnect(to: camera.id)
        }
    }

    // MARK: - Session recovery (camera power cycle, Wi-Fi loss)

    func beginSessionRecovery(reason: String, trigger: SessionRecoveryTrigger = .bleDropped) {
        guard SessionRecoveryPolicy.shouldBegin(trigger) else { return }
        if case .pausedAfterRepeatedDrops = sessionRecovery { return }
        if case .waitingForOperator = sessionRecovery { return }
        if sessionRecoveryTask != nil { return }
        guard let cameraID = connectedCamera?.id ?? recoveryCameraID else { return }
        AppDiagnostics.incidents.noteUnexpectedDisconnect(now: ProcessInfo.processInfo.systemUptime)
        recordFeedRepair("session", phase: .requested, reason: String(describing: trigger))
        recoveryCameraID = cameraID
        if recoveryDeviceName.isEmpty { recoveryDeviceName = connectedCamera?.name ?? "" }
        holdsMonitor = true
        endGimbalStick(cancelMove: true)
        decoder.flushForRecovery()
        feedRecovering = false
        sessionRecoveryGeneration += 1
        let generation = sessionRecoveryGeneration
        if sessionDropStormGuard.noteDrop(now: ProcessInfo.processInfo.systemUptime) {
            sessionRecovery = .pausedAfterRepeatedDrops(drops: sessionDropStormGuard.dropsInWindow)
            sessionRecoveryCardGraceElapsed = true
            applyLinkPresentation()
            return
        }
        ControlLiveLog.line("session: drop (\(reason)) → bounded recovery")
        sessionRecovery = SessionRecoveryPolicy.monitor.state(afterFailedAttempts: 0)
        sessionRecoveryCardGraceElapsed = false
        recoveryCardGraceTask?.cancel()
        recoveryCardGraceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.recoveryCardGrace)
            guard let self, !Task.isCancelled, self.sessionRecoveryGeneration == generation else {
                return
            }
            self.sessionRecoveryCardGraceElapsed = true
        }
        sessionRecoveryTask = Task { [weak self] in
            await self?.runSessionRecovery()
            guard let self, self.sessionRecoveryGeneration == generation else { return }
            self.sessionRecoveryTask = nil
        }
        applyLinkPresentation()
    }

    func retrySessionRecovery() {
        sessionDropStormGuard.reset()
        cancelSessionRecovery(clearHoldsMonitor: false)
        beginSessionRecovery(reason: "operator retry", trigger: .operatorRetry)
    }

    func cancelSessionRecovery(clearHoldsMonitor: Bool = true) {
        sessionRecoveryGeneration += 1
        sessionRecoveryTask?.cancel()
        sessionRecoveryTask = nil
        recoveryCardGraceTask?.cancel()
        recoveryCardGraceTask = nil
        sessionRecoveryCardGraceElapsed = false
        sessionRecovery = .idle
        isReconnecting = false
        if clearHoldsMonitor {
            holdsMonitor = false
            recoveryCameraID = nil
            recoveryDeviceName = ""
        }
    }

    func runSessionRecovery(
        budget: Duration = .seconds(SessionRecoveryPolicy.automaticRecoveryBudgetSeconds)
    ) async {
        let generation = sessionRecoveryGeneration
        let timedOut = await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor [weak self] in
                await self?.runSessionRecoveryAttempts()
                return false
            }
            group.addTask {
                do { try await Task.sleep(for: budget) } catch { return false }
                return true
            }
            let timedOut = await group.next() ?? false
            group.cancelAll()
            return timedOut
        }
        guard timedOut, !Task.isCancelled, sessionRecoveryGeneration == generation else { return }
        let attempts: Int
        if case .retrying(let attempt, _) = sessionRecovery { attempts = attempt } else { attempts = 0 }
        runTask?.cancel()
        backend.stopScan()
        sessionRecovery = .waitingForOperator(attemptsMade: attempts)
        sessionRecoveryCardGraceElapsed = true
        applyLinkPresentation()
    }

    func runSessionRecoveryAttempts(connectAttempt: (@MainActor () async -> Bool)? = nil) async {
        let policy = SessionRecoveryPolicy.monitor
        var failures = 0
        while !Task.isCancelled {
            let state = policy.state(afterFailedAttempts: failures)
            sessionRecovery = state
            applyLinkPresentation()
            guard case .retrying = state else { return }
            let recovered: Bool
            if let connectAttempt {
                recovered = await connectAttempt()
            } else {
                recovered = await attemptRecoveryConnect()
            }
            if Task.isCancelled { return }
            if recovered {
                sessionRecovery = .idle
                holdsMonitor = false
                isReconnecting = false
                sessionRecoveryCardGraceElapsed = false
                ControlLiveLog.line("session: recovered after \(failures) failed attempt(s)")
                applyLinkPresentation()
                return
            }
            failures += 1
            runTask?.cancel()
            backend.stopScan()
            guard
                case .retry(let wait) = policy.decision(
                    afterFailedAttempts: failures, jitter: .random(in: 0...1))
            else {
                sessionRecovery = policy.state(afterFailedAttempts: failures)
                applyLinkPresentation()
                return
            }
            try? await Task.sleep(for: .seconds(wait))
        }
    }

    /// Saved Wi-Fi first (no BLE needed while the camera AP is up), BLE otherwise.
    private func attemptRecoveryConnect() async -> Bool {
        guard let id = recoveryCameraID else { return false }
        isReconnecting = true
        guard let camera = knownCamera(id) else { return false }
        let started = Date()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.recoveryAttemptDeadline)
        connect(camera, preserveMonitor: true)
        while !Task.isCancelled, clock.now < deadline {
            if hasFreshRecoveryPicture(since: started), phase == .live { return true }
            if runTask == nil, phase != .live { return false }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return false }
        }
        return false
    }

    func hasFreshRecoveryPicture(since started: Date, now: Date = Date()) -> Bool {
        SessionRecoveryPolicy.hasFreshPicture(
            attemptStartedAt: started.timeIntervalSinceReferenceDate,
            now: now.timeIntervalSinceReferenceDate,
            lastSourceFrameAt: decoder.lastSourceFrameAt?.timeIntervalSinceReferenceDate,
            lastPresentedAt: decoder.monitorPresentedAt?.timeIntervalSinceReferenceDate)
    }

    // MARK: - Feed incident journal (shared diagnostics)

    private func beginFeedIncidentSession() {
        incidentSessionActive = true
        let info = Bundle.main.infoDictionary ?? [:]
        AppDiagnostics.incidents.beginSession(
            FeedIncidentSessionContext(
                sessionID: UUID().uuidString,
                appVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
                appBuild: info["CFBundleVersion"] as? String ?? "unknown",
                sourceRevision: info["OPCSourceRevision"] as? String ?? "unknown",
                osName: "iOS", osVersion: UIDevice.current.systemVersion,
                hardwareClass: DiagnosticCenter.machineIdentifier,
                cameraFamily: "luna",
                testSource: AppDiagnostics.origin.currentTestSource(),
                buildIdentity: AppDiagnostics.origin.currentBuildIdentity()))
    }

    func recordFeedBreadcrumb(_ kind: FeedIncidentBreadcrumbKind, detail: String = "") {
        AppDiagnostics.incidents.recordBreadcrumb(
            FeedIncidentBreadcrumb(
                monotonicAt: ProcessInfo.processInfo.systemUptime, kind: kind, detail: detail))
    }

    private func recordFeedRepair(_ action: String, phase: FeedRepairPhase, reason: String? = nil) {
        AppDiagnostics.incidents.recordRepair(
            FeedRepairRecord(
                monotonicAt: ProcessInfo.processInfo.systemUptime, action: action, phase: phase,
                reason: reason))
    }

    private func publishFeedIncidentSnapshot() {}

    // MARK: - Face AF (Vision on the decoded feed; camera-agnostic)

    private func considerFaceAF(_ buffer: CVPixelBuffer) {
        guard wantsFaceDetect else {
            clearFaceAF()
            return
        }
        let moving = gimbalStick.isHeld
        tickFaceBoxes(sceneMoving: moving)
        faceDetector.consider(buffer, rectanglesOnly: moving) { [weak self] result in
            self?.applyDetectedFaces(result.faces)
        }
        tickFacePriority(from: buffer)
    }

    private func tickFaceBoxes(sceneMoving: Bool) {
        let now = Date()
        faceTracks.removeAll {
            FaceTrackHold.shouldDrop(
                secondsSinceHit: now.timeIntervalSince($0.lastHit), sceneMoving: sceneMoving)
        }
        let raw = lastFaceAt.map { now.timeIntervalSince($0) } ?? (1.0 / 25.0)
        lastFaceAt = now
        let dt = min(max(raw, 1.0 / 120.0), 0.08)
        for i in faceTracks.indices {
            faceTracks[i].box = FaceTrackHold.follow(
                from: faceTracks[i].box, toward: faceTracks[i].target, dt: dt,
                sceneMoving: sceneMoving)
        }
        setSceneFaces(faceTracks.map(\.box))
        if isTrackingActive {
            setFaceBox(nil)
            return
        }
        let sinceHit = FaceTrackHold.secondsSinceHit(lastHit: lastFaceHitAt, now: now)
        if FaceTrackHold.shouldDrop(secondsSinceHit: sinceHit, sceneMoving: sceneMoving) {
            setFaceBox(nil)
            faceTarget = nil
            lastFaceHitAt = nil
            return
        }
        guard let target = faceTarget else { return }
        setFaceBox(FaceTrackHold.follow(from: faceBox, toward: target, dt: dt, sceneMoving: sceneMoving))
    }

    private func setFaceBox(_ box: TrackingBox?) {
        if faceBox != box { faceBox = box }
    }

    private func setSceneFaces(_ boxes: [TrackingBox]) {
        if sceneFaces != boxes { sceneFaces = boxes }
    }

    private func applyDetectedFaces(_ hits: [FaceHit]) {
        guard wantsFaceDetect else {
            clearFaceAF()
            return
        }
        let now = Date()
        let moving = gimbalStick.isHeld
        let heads = HeadTrackPolicy.mergeHits(hits)
        let detections = heads.map(\.box)
        let assigned = SceneFacePolicy.assignments(
            detections: detections, previous: faceTracks.map(\.box),
            maxCenterDistance: HeadTrackPolicy.jumpDistance)
        var claimed = Set<Int>()
        var next: [FaceTrack] = []
        for (index, track) in faceTracks.enumerated() {
            if let det = assigned[index] {
                var updated = track
                updated.target = detections[det]
                updated.lastHit = now
                next.append(updated)
                claimed.insert(det)
            }
        }
        for (index, hit) in heads.enumerated() where !claimed.contains(index) {
            guard HeadTrackPolicy.shouldSpawn(detection: hit.box, existing: next.map(\.box))
            else { continue }
            next.append(FaceTrack(box: hit.box, target: hit.box, lastHit: now))
        }
        faceTracks = next
        setSceneFaces(next.map(\.box))
        if isTrackingActive || !wantsFaceAF {
            setFaceBox(nil)
            faceTarget = nil
            lastFaceHitAt = nil
            return
        }
        let sinceHit = FaceTrackHold.secondsSinceHit(lastHit: lastFaceHitAt, now: now)
        let chosen = FaceAFPick.primary(
            hits: heads, hold: nil, last: faceTarget ?? faceBox, secondsSinceHit: sinceHit,
            sceneMoving: moving)
        guard let chosen else {
            if FaceTrackHold.shouldDrop(secondsSinceHit: sinceHit, sceneMoving: moving) {
                setFaceBox(nil)
                faceTarget = nil
                lastFaceHitAt = nil
            }
            return
        }
        lastFaceHitAt = now
        faceTarget = chosen.box
        if faceBox == nil { faceBox = chosen.box }
    }

    private func tickFacePriority(from buffer: CVPixelBuffer) {
        guard wantsFacePriorityMeter, !isBrowsingMedia, case .live = phase else { return }
        let now = Date()
        let boxes: [TrackingBox]
        if !sceneFaces.isEmpty {
            boxes = sceneFaces
        } else if let faceBox {
            boxes = [faceBox]
        } else {
            facePriorityAcquireAt = nil
            return
        }
        if facePriorityAcquireAt == nil { facePriorityAcquireAt = now }
        let spacing = FacePriorityExposure.interval(sinceAcquire: facePriorityAcquireAt, now: now)
        guard now.timeIntervalSince(lastFacePriorityEVAt) >= spacing else { return }
        guard let packed = ScopeSampler.copyBGRA(buffer, maxWidth: ScopeSampler.maxWidth)
        else { return }
        lastFacePriorityEVAt = now
        let transfer = MonitorTransfer(decoder.incomingColorMode ?? .normal)
        guard
            let encoded = FacePriorityExposure.medianEncoded(
                bytes: packed.bytes, width: packed.width, height: packed.height,
                bytesPerRow: packed.bytesPerRow, boxes: boxes, transfer: transfer),
            let next = FacePriorityExposure.nextEV(
                current: status.evComp ?? .zero, encoded: encoded, transfer: transfer)
        else { return }
        setEv(next)
    }

    func clearFaceAF() {
        setFaceBox(nil)
        faceTarget = nil
        lastFaceAt = nil
        lastFaceHitAt = nil
        faceTracks = []
        setSceneFaces([])
        facePriorityAcquireAt = nil
    }

    private struct FaceTrack {
        var box: TrackingBox
        var target: TrackingBox
        var lastHit: Date
    }

    // MARK: - Status publication

    func publishStatusNow() {
        lastStatusMutation = CFAbsoluteTimeGetCurrent()
        statusFlushTask?.cancel()
        statusFlushTask = nil
        withMutation(keyPath: \.status) {}
        onChromePublished?()
    }

    private func scheduleStatusFlush() {
        guard statusFlushTask == nil else { return }
        statusFlushTask = Task { @MainActor in
            let remaining =
                LiveChromeThrottle.statusInterval - (CFAbsoluteTimeGetCurrent() - lastStatusMutation)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            guard !Task.isCancelled else { return }
            statusFlushTask = nil
            withMutation(keyPath: \.status) {}
            lastStatusMutation = CFAbsoluteTimeGetCurrent()
            onChromePublished?()
        }
    }
}

/// The shared connection flow's way into this session (SHELL-02): `LunaIntegration` runs pairing
/// and saved-camera connects through it, so the session prepares the monitor and keeps its phase,
/// recovery and feed exactly as for its own reconnects.
extension CameraSession: LunaConnectPort {
    var connectedSerial: String? { backend.connectedSerial }
    var joinedNetwork: String? { backend.joinedNetwork }

    func startScan() async throws { try await backend.startScan() }

    func stopScan() { backend.stopScan() }

    func connect(to camera: MonitorCamera) async throws {
        descriptors[camera.id] = camera
        let generation = prepareConnection(
            to: FoundCamera(id: camera.id, name: camera.name, model: LunaShellMapping.cameraModel, modelId: nil),
            preserveMonitor: false)
        do {
            expectedDisconnect = true
            backend.disconnect()
            expectedDisconnect = false
            try await backend.connect(to: camera)
        } catch {
            if generation == connectGeneration, !(error is CancellationError), phase != .idle {
                let why = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                ControlLiveLog.line("session: connect failed at \(phase.label): \(why)")
                phase = .failed(why)
                applyLinkPresentation()
            }
            throw error
        }
    }

    /// The attempt's common session; the shell binds it to the monitor once it connects.
    func openSession() -> LunaCameraSession {
        resetForConnection()
        let next = backend.openSession()
        next.configureLens(zoomDomain: 1...zoomCeiling)
        return next
    }

    func mediaService(for session: CameraSessionID) -> (any CameraMediaService)? {
        backend.mediaService(for: session)
    }

    func forget(cameraID: UUID) { backend.forget(cameraID: cameraID) }
}
