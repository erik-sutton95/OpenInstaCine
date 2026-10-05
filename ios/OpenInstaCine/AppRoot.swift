import MonitorUI
import OpenCineMedia
import OpenCineFrameIO
import CoreVideo
import Insta360Apple
import MonitorPresentation
import Observation
import OpenCineAppKit
import OpenCineCore
import OpenCineRelayApple
import OpenPocketViewCore
import SwiftUI
import UIKit

/// App-level session object (OpenZCine `NativeAppModel` analogue). Owns the existing
/// `CameraSession` connection spine; the shared shell (`ShellModel`) owns navigation, covers and
/// the monitor's camera over the shared cameras model. Does not rewrite DUML.
@MainActor
@Observable
final class AppModel {
    var session: CameraSession
    /// Saved cameras, nearby sightings, pairing and connect attempts (SHELL-02): the shared
    /// flow over the Luna integration, which connects through `session`.
    let cameras: CamerasModel
    @ObservationIgnored let integration: LunaIntegration
    /// Root navigation, covers and the monitor lifetime (SHELL-03): binds each connected camera's
    /// common session to the shared controls (`session.control`).
    let shell: ShellModel
    /// The shared common controls of the camera on the monitor.
    var control: MonitorControlModel { shell.control }
    /// Why Bluetooth discovery is not running (off or not allowed); the pair page's Luna slot
    /// shows it with Open Settings.
    var discoveryFailure: ConnectionFailure?

    init(session: CameraSession? = nil) {
        let mediaStorage = MonitorMediaCacheStorage()
        let session = session ?? CameraSession(backend: Self.makeBackend(), mediaStorage: mediaStorage)
        self.session = session
        var port: any LunaConnectPort = session
        var defaults = UserDefaults.standard
        #if targetEnvironment(simulator)
            if MonitorUIReview.isActive { (port, defaults) = MonitorUIReview.cameras() }
        #endif
        integration = LunaIntegration(port: port)
        cameras = CamerasModel(
            integrations: [AppIntegration(integration, slots: IntegrationSlots(pairing: { AnyView(LunaPairingTips()) }))],
            store: Self.camerasStore(defaults))
        shell = ShellModel(cameras: cameras, control: session.control)
        integration.onDiscoveryFailure = { [weak self] in self?.discoveryFailure = $0 }
        // One active/inactive per change, however many OS signals report it.
        shell.onSceneActivity = { [weak self] active in
            guard let self else { return }
            self.assist.inspectorSceneActive = active
            if active { self.session.noteSceneBecameActive() } else { self.session.noteSceneBecameInactive() }
        }
    }

    /// The saved cameras: the shared document `OpenInstaCine.Cameras`, merged on every launch with
    /// the records older builds read and write (`OpenInstaCine.SavedCameras`), which it keeps
    /// mirrored. Wi-Fi passwords and the camera approval stay in the Keychain, untouched.
    static func camerasStore(_ defaults: UserDefaults = .standard) -> SavedCamerasStore {
        SavedCamerasStore(
            document: .userDefaults(defaults, key: "OpenInstaCine.Cameras"),
            legacy: .init(
                data: .userDefaults(defaults, key: "OpenInstaCine.SavedCameras"),
                codec: BodyRecordsV0(integration: LunaCameraSession.integration, dates: .secondsSince2001),
                source: "OpenInstaCine.SavedCameras"))
    }

    /// Saved cameras, most recently connected first.
    var savedCameras: [OpenCineCore.SavedCamera] {
        cameras.saved.sorted { ($0.lastConnected ?? .distantPast) > ($1.lastConnected ?? .distantPast) }
    }

    /// The composition root's one backend per camera connection. Simulator has no Bluetooth
    /// or hotspot API but shares the Mac's network: with the Mac on the camera Wi-Fi, the
    /// simulator app talks to the real camera.
    static func makeBackend() -> LunaCameraBackend {
        #if targetEnvironment(simulator)
            LunaCameraBackend(useExistingNetwork: true, configuration: lunaConfiguration, mediaIO: LunaNativeMediaIO())
        #else
            LunaCameraBackend(configuration: lunaConfiguration, mediaIO: LunaNativeMediaIO())
        #endif
    }

    /// The app's names for the Luna integration. The keychain service is the one OpenInstaCine
    /// has always used: changing it would orphan saved camera authorizations and Wi-Fi.
    static let lunaConfiguration = LunaIntegrationConfiguration(
        keychainService: "org.opencine.openinstacine.camera", appName: "OpenInstaCine",
        logPrefix: "OpenInstaCine")
    @ObservationIgnored let watchRelay = WatchRelay()
    @ObservationIgnored private var watchRelayActivated = false
    var multiviewExit: (() -> Void)?
    /// Live view-space X flip: TT180 extra-mirror XOR MIRROR assist.
    var livePictureViewFlip: Bool {
        GimbalStick.liveViewFlip(
            poseViewFlip: session.gimbalPoseViewFlip,
            assistMirror: assist.mirrorsHorizontally)
    }
    var showsLaunchSplash = true
    /// Long-press on the tap-focus box locks it: feed taps no longer move focus.
    var focusBoxLocked = false
    var assist = LiveAssistState()
    /// Decoded-frame scopes. Filled by `HevcDecoder.handleDecodedFrame` — not camera DUML.
    var frameSamples = LiveFrameSampleBus(profile: ScopeExposureCeiling.sourceProfile)
    @ObservationIgnored var inspectorPreview = AssistInspectorImageRenderer()
    @ObservationIgnored let liveBackdrop = MonitorVideoBackdropRenderer()
    @ObservationIgnored let playbackBackdrop = MonitorVideoBackdropRenderer()
    /// Monitor tools follow the displayed source; watcher scopes must never read the camera bus.
    var monitorSamples: LiveFrameSampleBus { isWatchingFeed ? relayClient.samples : frameSamples }
    var monitorColorMode: ColorMode? {
        if isWatchingFeed { return relayClient.colorMode }
        if assist.gradesClip { return assist.monitorColorMode }
        return LiveMonitorColorScience.colorMode(
            isPhoto: session.status.isPhoto, colorMode: session.status.colorMode)
    }
    var monitorTransfer: MonitorTransfer? {
        if isWatchingFeed { return relayClient.transfer }
        if assist.gradesClip { return assist.monitorColorMode.map(MonitorTransfer.init) }
        return LiveMonitorColorScience.transfer(
            isPhoto: session.status.isPhoto, colorMode: session.status.colorMode)
    }

    /// Refresh LUT / decoder transfer on color or shooting-mode change. Skips watcher, clip, camera playback.
    func syncLiveMonitorColor() {
        guard !isWatchingFeed, !assist.gradesClip, !session.status.inPlayback else { return }
        let raw = session.status.colorMode
        let photo = session.status.isPhoto
        assist.evMeterFromPicture = !session.reportsMeteredEV
        assist.cameraHasAudio = OsmoMonitorPresentation.capabilities(session).audio
        assist.syncLUT(
            to: raw,
            family: session.bodyFamily,
            cameraName: session.connectedCamera?.model.name,
            isPhoto: photo)
        session.decoder.incomingColorMode = LiveMonitorColorScience.colorMode(
            isPhoto: photo, colorMode: raw)
    }
    var captureSheet: CaptureSheet?
    var captureDrum: CaptureDrumPresentation?
    var keepScreenAwake: Bool = OperatorPrefs.keepScreenAwake {
        didSet { OperatorPrefs.keepScreenAwake = keepScreenAwake }
    }
    var hdrDisplay: Bool = OperatorPrefs.hdrDisplay {
        didSet {
            OperatorPrefs.hdrDisplay = hdrDisplay
            LiveHDRDisplay.setEnabled(hdrDisplay)
            LiveHDRDisplay.setScreenCaptured(screenCaptured)
        }
    }
    /// Screen recording / AirPlay. HDR present drops to SDR so the file is not boosted.
    var screenCaptured = false {
        didSet { LiveHDRDisplay.setScreenCaptured(screenCaptured) }
    }
    var hdrDisplayActive: Bool { hdrDisplay && !screenCaptured }
    var cacheFullResolution: Bool = OperatorPrefs.cacheFullResolution {
        didSet { OperatorPrefs.cacheFullResolution = cacheFullResolution }
    }
    var recordConfirmationEnabled: Bool = OperatorPrefs.recordConfirmationEnabled {
        didSet { OperatorPrefs.recordConfirmationEnabled = recordConfirmationEnabled }
    }
    var hapticsEnabled: Bool = OperatorPrefs.hapticsEnabled {
        didSet { OperatorPrefs.hapticsEnabled = hapticsEnabled }
    }
    var assistToolUsage: MonitorToolUsage = OperatorPrefs.assistToolUsage {
        didSet { OperatorPrefs.assistToolUsage = assistToolUsage }
    }
    var headTrackingEnabled: Bool = OperatorPrefs.headTrackingEnabled {
        didSet { OperatorPrefs.headTrackingEnabled = headTrackingEnabled }
    }
    /// A manual mode selection takes control back from the AirPods stream.
    func setGimbalMode(_ mode: GimbalMode) {
        guard session.canSetGimbalConfiguration else { return }
        headTrackingEnabled = false
        session.setGimbalMode(mode)
    }

    /// Live SET / STOP chip. SET starts tracking and locks forward; STOP ends it.
    var headTrackControlTitle = LiveHeadTrackCalibrateButton.calibrateTitle
    /// Raw AirPods attitude / gyro / SET-relative look. Empty when Head Tracking is off.
    var headTrackImuReadout = ""
    /// SET-relative (or first-sample) yaw/pitch for the live axis rings. `nil` without IMU.
    var headTrackAxisPose: HeadTrackAxisPose?
    /// On-screen gimbal stick is thrown. Head tracking yields.
    var gimbalScreenHeld = false
    /// Gamepad left stick is thrown. Head tracking yields.
    var gimbalPadHeld = false
    var gimbalAnalogHeld: Bool { gimbalScreenHeld || gimbalPadHeld }
    /// Extended gamepad is bound. Toast on rising/falling edge.
    var gamepadConnected = false
    var liveGimbalPanel: LiveGimbalPanel = .none
    /// Canvas-space centre of the programmed-move editor / Run pill. Nil until the operator drags it.
    var gimbalFloatCenter: CGPoint?
    /// Canvas-space centre of the programmed-move debug plate.
    var gimbalDoubleTap: GimbalDoubleTap = OperatorPrefs.gimbalDoubleTap {
        didSet {
            OperatorPrefs.gimbalDoubleTap = gimbalDoubleTap
            session.gimbalDoubleTap = gimbalDoubleTap
        }
    }
    var gimbalRamp: GimbalRamp = OperatorPrefs.gimbalRamp {
        didSet {
            OperatorPrefs.gimbalRamp = gimbalRamp
            session.gimbalRamp = gimbalRamp
        }
    }
    var gimbalStickSensitivity: Int = OperatorPrefs.gimbalStickSensitivity {
        didSet {
            let clamped = GimbalStick.clampedSensitivity(gimbalStickSensitivity)
            if clamped != gimbalStickSensitivity {
                gimbalStickSensitivity = clamped
                return
            }
            OperatorPrefs.gimbalStickSensitivity = clamped
        }
    }
    var virtualJoystickInvertPan: Bool = OperatorPrefs.virtualJoystickInvertPan {
        didSet { OperatorPrefs.virtualJoystickInvertPan = virtualJoystickInvertPan }
    }
    var virtualJoystickInvertTilt: Bool = OperatorPrefs.virtualJoystickInvertTilt {
        didSet { OperatorPrefs.virtualJoystickInvertTilt = virtualJoystickInvertTilt }
    }
    var virtualJoystickDeadzonePercent: Int = OperatorPrefs.virtualJoystickDeadzonePercent {
        didSet {
            let clamped = GimbalStick.clampedDeadzonePercent(virtualJoystickDeadzonePercent)
            if clamped != virtualJoystickDeadzonePercent {
                virtualJoystickDeadzonePercent = clamped
                return
            }
            OperatorPrefs.virtualJoystickDeadzonePercent = clamped
        }
    }
    var virtualJoystickResponseCurve: GimbalStick.ResponseCurve =
        OperatorPrefs.virtualJoystickResponseCurve
    {
        didSet { OperatorPrefs.virtualJoystickResponseCurve = virtualJoystickResponseCurve }
    }
    var virtualJoystickSize: MonitorJoystickSize = OperatorPrefs.virtualJoystickSize {
        didSet { OperatorPrefs.virtualJoystickSize = virtualJoystickSize }
    }
    var virtualJoystickMapping: GimbalStick.Mapping {
        GimbalStick.Mapping(
            invertPan: virtualJoystickInvertPan,
            invertTilt: virtualJoystickInvertTilt,
            deadzone: GimbalStick.deadzoneFromPercent(virtualJoystickDeadzonePercent),
            curve: virtualJoystickResponseCurve)
    }
    var dispLive = OperatorPrefs.dispLive {
        didSet { OperatorPrefs.dispLive = dispLive }
    }
    var dispClean = OperatorPrefs.dispClean {
        didSet { OperatorPrefs.dispClean = dispClean }
    }
    var operatorSettingsTab: OperatorSettingsTab = .link
    /// DISP mode whose chrome the operator is editing on the monitor, or `nil` when live.
    var chromeEditorMode: PocketDispMode?
    /// Section Display settings should reopen on after Done.
    var chromeEditorReturnMode: PocketDispMode?
    /// False for a beat after live mounts so the connect tap cannot hit Settings / Media.
    var liveChromeInteractive = true
    var portraitFeedAspect: PortraitFeedAspect = OperatorPrefs.portraitFeedAspect {
        didSet { OperatorPrefs.portraitFeedAspect = portraitFeedAspect }
    }
    var nativeISOHopEnabled: Bool = OperatorPrefs.nativeISOHopEnabled {
        didSet { OperatorPrefs.nativeISOHopEnabled = nativeISOHopEnabled }
    }
    var facePriorityExposureEnabled: Bool = OperatorPrefs.facePriorityExposureEnabled {
        didSet {
            OperatorPrefs.facePriorityExposureEnabled = facePriorityExposureEnabled
            session.setFacePriorityEnabled(facePriorityExposureEnabled)
        }
    }
    var portraitRailExpanded = false
    var frameioConnecting = false
    var frameioUser: FrameioUser?
    var delivery = MediaDeliveryCoordinator()
    var relayHost = WatcherRelayHost(
        versionMismatchReason: WatcherRelayJoin.versionMismatchReason,
        logSubsystem: "com.opencapture.openinstacine", journal: { ControlLiveLog.line($0) })
    private var relayStateTask: Task<Void, Never>?
    var relayBrowser = WatcherRelayBrowser()
    var relayClient = WatcherRelayClient()
    var isWatchingFeed = false
    /// Once accepted, transport failure belongs on the watcher screen until explicit Leave.
    var showsWatcherMonitor: Bool { isWatchingFeed }

    func noteWatcherStatusChanged(_ status: WatcherRelayClientStatus) {
        if status == .needsPasscode, isWatchingFeed {
            isWatchingFeed = false
            showsWatcherBrowse = true
            startWatcherBrowse()
        }
        if status == .live, showsWatcherBrowse {
            isWatchingFeed = true
            showsWatcherBrowse = false
            shell.dismissCover()
        }
    }

    var showsWatcherBrowse = false
    var shareThisFeed: Bool = OperatorPrefs.shareThisFeed
    var sharePasscode: String = WatcherRelayKeychain.hostPasscode
    var controlRequestsAllowed: Bool = OperatorPrefs.controlRequests {
        didSet { OperatorPrefs.controlRequests = controlRequestsAllowed }
    }
    var broadcastPriority: Int = OperatorPrefs.broadcastPriority {
        didSet {
            OperatorPrefs.broadcastPriority = broadcastPriority
            relayHost.setCeiling(broadcastPriority)
        }
    }
    var watcherRecordConfirm = false
    var watcherRecordRequest: RecordConfirmationContext?
    var watcherRecordContext: RecordConfirmationContext {
        RecordConfirmationContext(
            mode: session.status.shootingMode, recording: session.control.isRecording,
            locked: session.isLocked, busy: session.controlBusy, phase: session.phase)
    }
    var internetHop = FrameioInternetHop()
    var internetHopActive: Bool { internetHop.token != nil }
    @ObservationIgnored private var internetHopSession: CameraSession?
    @ObservationIgnored private var liveChromeArmTask: Task<Void, Never>?

    /// On the Luna's own network (192.168.42.x), from the integration (SHELL-02 D10).
    var isOnCameraAccessPoint: Bool { session.backend.isOnCameraNetwork }

    @discardableResult func beginInternetHop() -> FrameioInternetHop.Token {
        let token = internetHop.begin()
        internetHopSession = session
        if let ssid = session.joinedSSID ?? session.cachedSSID { WiFiJoiner.leave(ssid: ssid) }
        return token
    }

    func transferInternetHop(_ token: FrameioInternetHop.Token) -> FrameioInternetHop.Token? {
        internetHop.transfer(token)
    }

    func endInternetHop(_ token: FrameioInternetHop.Token) {
        guard internetHop.end(token) else { return }
        let returningSession = internetHopSession
        internetHopSession = nil
        Task { await returningSession?.rejoinSoftAPAfterInternetHop() }
    }

    func waitForInternetPath(timeoutSeconds: Double, token: FrameioInternetHop.Token) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if Task.isCancelled || !internetHop.owns(token) { return false }
            if !isOnCameraAccessPoint, await Self.canReachInternet() {
                return !Task.isCancelled && internetHop.owns(token)
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        return false
    }

    private static func canReachInternet() async -> Bool {
        guard let url = URL(string: "https://ims-na1.adobelogin.com") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3
        return (try? await URLSession.shared.data(for: request)) != nil
    }

    var currentDispMode: PocketDispMode { assist.clean ? .clean : .live }

    var dispChrome: PocketDispChrome {
        chrome(for: currentDispMode)
    }

    var isEditingChrome: Bool { chromeEditorMode != nil }

    func chrome(for mode: PocketDispMode) -> PocketDispChrome {
        switch mode {
        case .live: dispLive
        case .clean: dispClean
        }
    }

    /// Whether `section` mounts right now: switched on, or force-mounted while that
    /// mode's chrome is being edited. Settings stays reachable if both modes hid it.
    func chromeSectionMounts(_ section: PocketDispChrome.Section) -> Bool {
        if section == .timecode, !OsmoMonitorPresentation.capabilities(session).timecode { return false }
        if let mode = chromeEditorMode, mode == currentDispMode,
            PocketDispChrome.isConfigurable(section, in: mode)
        {
            return true
        }
        if section == .railSettings, !dispLive.railSettings, !dispClean.railSettings {
            return true
        }
        return dispChrome.isVisible(section)
    }

    func toggleChrome(_ section: PocketDispChrome.Section, for mode: PocketDispMode) {
        switch mode {
        case .live: dispLive.toggle(section)
        case .clean: dispClean.toggle(section)
        }
    }

    /// Leaves Settings and switches the monitor to `mode` so badges land on the real thing.
    func beginChromeEditing(_ mode: PocketDispMode) {
        shell.dismissCover()
        liveGimbalPanel = .none
        setDisplayMode(clean: mode == .clean)
        chromeEditorMode = mode
    }

    /// Done returns to Display settings on the section that was being edited.
    func endChromeEditing() {
        chromeEditorReturnMode = chromeEditorMode
        chromeEditorMode = nil
        operatorSettingsTab = .display
        shell.open(.settings)
    }

    /// The monitor shows a camera (the shell's monitor lifetime, recovery included).
    var isLive: Bool { shell.monitor != nil }

    var isBusy: Bool {
        switch session.phase {
        case .idle, .scanning, .failed, .live: false
        default: true
        }
    }

    func prepareStartup() {
        #if targetEnvironment(simulator)
            if MonitorUIReview.isActive {
                MonitorUIReview.prepare(self)
                return
            }
            // No camera in Simulator: the monitor plays the D-Log2 clip when one is configured.
            // Without it the real camera (Mac on its Wi-Fi) connects through the cameras page.
            if SimulatorLiveFeed.isConfigured { MonitorUIReview.presentSimulatedMonitor(self) }
        #endif
        LiveHDRDisplay.setEnabled(hdrDisplay)
    }

    /// Connects a saved camera over its preferred setup (debug and stress drivers).
    func reconnect(_ camera: OpenCineCore.SavedCamera) { cameras.connect(camera) }

    /// Connect shows the monitor — never leftover Operator Setup, Media, or Edit view.
    func setShareThisFeed(_ on: Bool) {
        guard !session.isMultiviewBorrowed else { return }
        shareThisFeed = on
        OperatorPrefs.shareThisFeed = on
        if on {
            startRelayHost()
        } else {
            relayStateTask?.cancel()
            relayStateTask = nil
            relayHost.stop()
            session.decoder.onIdentityFrame = nil
            session.decoder.onIdentityOrientation = nil
        }
    }

    func startRelayHost() {
        guard isLive, shareThisFeed, !session.isMultiviewBorrowed else { return }
        WatcherRelayKeychain.hostPasscode = sharePasscode
        let name = UIDevice.current.name
        let camera = session.connectedCamera?.name ?? ""
        relayHost.start(
            hostName: name,
            cameraName: camera,
            passcode: sharePasscode,
            ceilingIndex: broadcastPriority,
            allowsControl: controlRequestsAllowed)
        if relayHost.encoderFailed {
            shareThisFeed = false
            OperatorPrefs.shareThisFeed = false
            session.controlNote = "Sharing could not start"
            return
        }
        session.decoder.onIdentityOrientation = relayHost.orientationSink()
        session.decoder.onIdentityOrientation?(session.decoder.presentedPictureFlip ?? false)
        session.decoder.onIdentityFrame = relayHost.frameSink()
        relayStateTask?.cancel()
        updateRelayState()
        relayStateTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self, self.shareThisFeed, self.isLive else { return }
                if self.relayHost.encoderFailed {
                    self.setShareThisFeed(false)
                    self.session.controlNote = "Sharing could not start"
                    return
                }
                self.updateRelayState()
            }
        }
    }

    private func updateRelayState() {
        guard shareThisFeed, isLive else { return }
        let s = session.status
        let state = WatcherRelayState(
            isRecording: s.isRecording,
            format: s.videoResolution?.label ?? "",
            color: (s.isPhoto ? ColorMode.normal : s.colorMode)?.label(in: session.profile) ?? "",
            zoom: CamFov.displayLabel(factor: session.zoomReadout, ceiling: session.zoomCeiling),
            liveFPS: session.liveFPS,
            batteryPercent: s.batteryPercent,
            cameraName: session.connectedCamera?.name ?? "",
            iso: s.isoIndex?.label ?? "\(s.iso)",
            shutter: s.shutterDenom > 0 ? "1/\(s.shutterDenom)" : "",
            allowsControlRequests: controlRequestsAllowed,
            controlOptions: .init(
                isoIndices: s.availableIsoIndices.map { Int($0.rawValue) },
                shutterDenominators: CamCapShutter.wheelDenoms(
                    available: s.availableShutterDenoms, current: s.shutterDenom),
                zoomHundredths: session.zoomStops.map { Int(($0 * 100).rounded()) }),
            cameraModel: session.connectedCamera?.model.name,
            isNano: session.bodyFamily == .nano)
        relayHost.update(state: state)
    }

    func openWatcherBrowse() {
        showsWatcherBrowse = true
        relayClient.resolveEndpoint = { [weak self] name in
            self?.relayBrowser.hosts.first { $0.name == name }?.endpoint
        }
        relayClient.onReconnect = { [weak self] in self?.startWatcherBrowse() }
        startWatcherBrowse()
    }

    func startWatcherBrowse() {
        guard !isLive else { return }
        relayBrowser.start()
    }

    func joinWatcher(_ host: WatcherRelayDiscovery) {
        let code = WatcherRelayKeychain.rememberedPasscode(forHost: host.name)
        relayClient.join(
            endpoint: host.endpoint,
            hostName: host.name,
            passcode: code,
            watcherID: WatcherRelayKeychain.installID,
            deviceName: UIDevice.current.name)
    }

    func retryWatcherPasscode(_ code: String) {
        WatcherRelayKeychain.rememberPasscode(code, forHost: relayClient.hostTitle)
        relayClient.retryPasscode(code)
    }

    func stopWatching() {
        relayClient.leave()
        isWatchingFeed = false
        showsWatcherBrowse = false
        relayBrowser.stop()
    }

    func handleWatcherRelayCommand(_ command: WatcherRelayCommand, from watcherID: String?) {
        guard let allowed = relayHost.applyCommand(command, from: watcherID) else { return }
        switch allowed {
        case .toggleRecording:
            guard !session.isLocked, !session.controlBusy else { return }
            if recordConfirmationEnabled, !session.status.isPhoto {
                watcherRecordRequest = watcherRecordContext
                watcherRecordConfirm = true
            } else {
                session.pressShutter()
            }
        case .tapFocus(let x, let y, let w, let h):
            let nx = w > 0 ? Double(x) / Double(w) : 0.5
            let ny = h > 0 ? Double(y) / Double(h) : 0.5
            session.markFocus(at: CGPoint(x: nx, y: ny))
        case .setISO(let raw):
            if let idx = IsoIndex(rawValue: UInt8(clamping: raw)) {
                session.setISO(idx)
            }
        case .setShutterDenom(let denom):
            session.setShutterDenom(denom)
        case .setWhiteBalance(let mode, let kelvin, let tint):
            if mode == 0 {
                session.setWhiteBalanceAuto(tint: tint)
            } else {
                session.setWhiteBalanceCustom(kelvin: kelvin, tint: tint)
            }
        case .setColor(let raw):
            if let mode = ColorMode(rawValue: UInt8(clamping: raw)) {
                session.setColorMode(mode)
            }
        case .setZoom(let hundredths):
            session.setZoom(Double(hundredths) / 100.0)
        }
    }

    /// The monitor's camera changed (shown, replaced or gone): the app's own chrome and relay
    /// follow. The shell already dropped covers and retired the old camera's controls.
    func noteMonitorChanged() {
        session.configureMediaLibrary(service: shell.monitor?.camera.services[(any CameraMediaService).self])
        if isLive { noteBecameLive() } else { noteLeftLive() }
    }

    func noteBecameLive() {
        chromeEditorMode = nil
        chromeEditorReturnMode = nil
        captureSheet = nil
        liveChromeInteractive = false
        liveChromeArmTask?.cancel()
        liveChromeArmTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            self?.liveChromeInteractive = true
        }
        if shareThisFeed { startRelayHost() }
        relayBrowser.stop()
    }

    /// A dropped link must not keep Operator Setup or Edit view around for the next connect.
    func noteLeftLive() {
        liveChromeArmTask?.cancel()
        liveChromeArmTask = nil
        liveChromeInteractive = true
        chromeEditorMode = nil
        chromeEditorReturnMode = nil
        captureSheet = nil
        relayStateTask?.cancel()
        relayStateTask = nil
        relayHost.stop()
        session.decoder.onIdentityFrame = nil
        session.decoder.onIdentityOrientation = nil
        watcherRecordConfirm = false
    }

    /// The app's own link gave up while the monitor showed it, outside recovery (a reconnect
    /// that failed, Bluetooth off): the monitor closes as it always did.
    func noteLinkPhase() {
        guard isLive, !session.holdsMonitor else { return }
        switch session.phase {
        case .idle, .failed: shell.close()
        default: break
        }
    }

    func beginMediaBrowse() { session.beginMediaBrowse() }
    func endMediaBrowse() { session.endMediaBrowse() }
    func noteMediaCoverChanged(from old: ShellModel.Cover?, to new: ShellModel.Cover?) {
        if old == .media, new != .media { session.endMediaBrowse() }
    }
    func refreshMedia() { session.refreshMedia() }

    /// Closes the monitor's camera (never a camera command), then the app's link.
    func disconnect() {
        focusBoxLocked = false
        shell.close()
        session.disconnect()
    }

    /// Recovery card: leave the held frame for the saved-camera list.
    func exitMonitorToOperatorMenu() {
        session.cancelSessionRecovery()
        disconnect()
    }

    /// OpenZCine `NativeAppModel.setDisplayMode` — feed swipe jumps, it does not cycle.
    func setDisplayMode(clean: Bool) {
        guard assist.clean != clean else { return }
        assist.clean = clean
    }

    func activateWatchRelay() {
        guard !watchRelayActivated else { return }
        watchRelayActivated = true
        watchRelay.onToggleRecord = { [weak self] in
            self?.watchToggleRecord()
                ?? WatchCommandResult(
                    accepted: false, isRecording: false, error: WatchRelayCopy.connectFirst)
        }
        watchRelay.onCapture = { [weak self] in
            self?.watchCapture()
                ?? WatchCommandResult(
                    accepted: false, isRecording: false, error: WatchRelayCopy.connectFirst)
        }
        watchRelay.onReachabilityChanged = { [weak self] in
            guard let self else { return }
            self.session.decoder.needsWatchPreview = self.watchRelay.hasCompanion
            self.publishWatchState()
        }
        session.decoder.needsWatchPreview = watchRelay.hasCompanion
        session.decoder.onWatchPreview = { [weak self] image, source, unmanaged in
            guard let self else { return }
            self.watchRelay.ingestPreview(
                image, source: source, unmanaged: unmanaged,
                mirrored: self.session.decoder.presentedPictureFlip ?? false,
                flippedVertically: self.assist.flipsVertically,
                timecode: self.session.status.timecodeClock,
                isRecording: self.session.status.isRecording)
        }
        session.onChromePublished = { [weak self] in
            self?.publishWatchState()
        }
        watchRelay.activate()
        publishWatchState()
    }

    func publishWatchState() {
        watchRelay.ingestState(
            WatchRelayState.snapshot(
                status: session.status,
                phase: session.phase,
                cameraName: session.connectedCamera?.name ?? "",
                feedLive: session.decoder.lastPresentedAt != nil))
    }

    func watchToggleRecord() -> WatchCommandResult {
        watchShutter(photo: false)
    }

    func watchCapture() -> WatchCommandResult {
        watchShutter(photo: true)
    }

    private func watchShutter(photo: Bool) -> WatchCommandResult {
        let recording = session.status.isRecording
        if session.controlBusy || session.isBrowsingMedia {
            return WatchCommandResult(
                accepted: false, isRecording: recording, error: WatchRelayCopy.busy)
        }
        guard case .live = session.phase else {
            return WatchCommandResult(
                accepted: false, isRecording: false, error: WatchRelayCopy.connectFirst)
        }
        let isPhoto = session.status.isPhoto
        if photo, !isPhoto {
            return WatchCommandResult(
                accepted: false, isRecording: recording, error: WatchRelayCopy.switchToPhoto)
        }
        if !photo, isPhoto {
            return WatchCommandResult(
                accepted: false, isRecording: recording, error: WatchRelayCopy.switchToVideo)
        }
        session.pressShutter()
        publishWatchState()
        return WatchCommandResult(accepted: true, isRecording: recording, error: nil)
    }
}

struct AppRoot: View {
    @State private var model = AppModel()
    @State private var showReliabilityPrompt = false
    @Environment(\.scenePhase) private var scenePhase

    @ViewBuilder private var primaryExperience: some View {
        if model.showsWatcherMonitor {
            WatcherLiveView()
                .environment(model)
                .transition(.opacity)
        } else {
            LinkExperience()
                .environment(model)
        }
    }

    var body: some View {
        ZStack {
            MonitorTheme.background.ignoresSafeArea()
            #if targetEnvironment(simulator)
                if MonitorMediaReview.isActive && !MonitorMediaReview.usesProductionShell {
                    MonitorMediaReviewView()
                } else {
                    primaryExperience
                }
            #else
                primaryExperience
            #endif

            if model.showsLaunchSplash {
                LaunchSplashOverlay(isVisible: Bindable(model).showsLaunchSplash)
                    .transition(.opacity)
                    .zIndex(100)
            }

            if model.showsWatcherBrowse, !model.isLive {
                MonitorTheme.background
                    .ignoresSafeArea()
                    .overlay {
                        WatcherBrowseView()
                            .environment(model)
                    }
                    .zIndex(90)
            }
        }
        .environment(model)
        #if DEBUG && targetEnvironment(simulator)
        .overlay(alignment: .topLeading) {
            if MonitorMediaReview.usesProductionShell { MonitorPlaybackReviewFacts(model: model) }
        }
        #endif
        .environment(\.font, LiveType.text(16))
        .environment(
            \.monitorHDRChromeGain,
            model.hdrDisplayActive ? CGFloat(LiveHDRDisplay.presentGain) : 1
        )
        .background {
            HDRChromeHost(enabled: model.hdrDisplayActive).allowsHitTesting(false)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)
        ) { _ in
            model.screenCaptured = UIScreen.main.isCaptured
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showReliabilityPrompt) {
            ReliabilityConsentPrompt { enabled in
                ReliabilityReporting.setConsent(enabled)
                showReliabilityPrompt = false
            }.environment(model)
        }
        .task {
            while !Task.isCancelled {
                ProblemReporting.shared.tick()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .onAppear {
            #if DEBUG
                // Physical consent review uses an isolated preference domain;
                // the operator's saved choice is never overwritten.
                if let reviewID = ProcessInfo.processInfo.environment["OPV_CONSENT_REVIEW_ID"],
                    UUID(uuidString: reviewID) != nil
                {
                    ReliabilityReportingConsent.defaults = UserDefaults(
                        suiteName: "opc.consent.review.\(reviewID)")!
                }
            #endif
            DiagnosticCenter.shared.install()
            AppModelDiagnosticsAnchor.model = model
            DiagnosticCenter.shared.onCopiedForTestFlight = { [weak model] in
                model?.session.controlNote =
                    "Diagnostics copied — paste into TestFlight feedback"
            }
            model.prepareStartup()
            model.activateWatchRelay()
            model.screenCaptured = UIScreen.main.isCaptured
            UIApplication.shared.isIdleTimerDisabled = model.keepScreenAwake
        }
        .onChange(of: model.relayClient.status) { _, status in
            model.noteWatcherStatusChanged(status)
        }
        .onChange(of: model.keepScreenAwake) { _, awake in
            UIApplication.shared.isIdleTimerDisabled = awake
        }
        .task {
            try? await Task.sleep(for: LaunchSplashTiming.visibleDuration)
            withAnimation(.easeOut(duration: LaunchSplashTiming.fadeOutDuration)) {
                model.showsLaunchSplash = false
            }
            if ReliabilityReporting.isAvailable && !ReliabilityReportingConsent.hasDecision {
                showReliabilityPrompt = true
            }
        }
        .onChange(of: model.gimbalAnalogHeld) { _, held in
            if held { model.relayHost.reclaimControl() }
        }
        .onChange(of: model.shell.cover) { old, new in
            model.noteMediaCoverChanged(from: old, to: new)
        }
        .onChange(of: model.shell.monitor?.id) { _, _ in model.noteMonitorChanged() }
        .onChange(of: model.session.phase) { _, _ in model.noteLinkPhase() }
        .onReceive(NotificationCenter.default.publisher(for: .opcWatcherRelayCommand)) { note in
            let command = note.userInfo?["command"] as? WatcherRelayCommand
            let id = note.userInfo?["watcherID"] as? String
            if let command {
                model.handleWatcherRelayCommand(command, from: id)
            }
        }
        .modifier(WatcherRecordConfirmation(model: model))
        .confirmationDialog(
            "Allow \(model.relayHost.pendingControlRequest?.name ?? "a watcher") to control the camera?",
            isPresented: Binding(
                get: { model.relayHost.pendingControlRequest != nil },
                set: { if !$0 { model.relayHost.denyControl() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Grant") { model.relayHost.grantControl() }
            Button("Deny", role: .cancel) { model.relayHost.denyControl() }
        }
        .onAppear {
            model.shell.setSceneActive(scenePhase == .active)
            model.assist.inspectorSceneActive = model.shell.sceneActive
        }
        // The shell reports each change once (`AppModel.shell.onSceneActivity`).
        .onChange(of: scenePhase) { _, phase in
            ProblemReporting.shared.tick()
            model.shell.setSceneActive(phase == .active)
        }
        // scenePhase can miss a Control Center / app-switcher bounce.
        // UIKit notifications are the same signals OpenZCine uses.
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
        ) { _ in model.shell.setSceneActive(false) }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        ) { _ in model.shell.setSceneActive(true) }
    }
}

/// Watcher record confirmation reads `CameraStatus` in its own scope. On the
/// app root, every 5 Hz status publish re-evaluated the whole root body.
private struct WatcherRecordConfirmation: ViewModifier {
    @Bindable var model: AppModel

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                model.session.status.isRecording ? "Stop recording?" : "Start recording?",
                isPresented: $model.watcherRecordConfirm,
                titleVisibility: .visible
            ) {
                Button(
                    model.session.status.isRecording ? "Stop" : "Start",
                    role: model.session.status.isRecording ? .destructive : nil
                ) {
                    guard let request = model.watcherRecordRequest,
                        request == model.watcherRecordContext, request.canConfirm,
                        let recording = request.recording
                    else { return }
                    model.watcherRecordRequest = nil
                    model.session.setRecording(start: !recording)
                }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: model.watcherRecordContext) { _, _ in
                model.watcherRecordConfirm = false
                model.watcherRecordRequest = nil
            }
    }
}
