import CoreVideo
import Insta360Apple
import MonitorPresentation
import MonitorUI
import Observation
import OpenCineAppKit
import OpenCineAppKitApple
import OpenCineApple
import OpenCineCameraControls
import OpenCineCore
import OpenCineFrameIO
import OpenCineFrameIOApple
import OpenCineMedia
import OpenCineRelay
import OpenCineRelayApple
import OpenCineWatch
import OpenInstaViewCore
import SwiftUI
import UIKit

/// App-level session object (OpenZCine `NativeAppModel` analogue). Owns the existing
/// `CameraSession` connection spine; the shared shell (`ShellModel`) owns navigation, covers and
/// the monitor's camera over the shared cameras model. Does not rewrite DUML.
@MainActor
@Observable
final class AppModel {
    var session: CameraSession
    @ObservationIgnored let playbackAudioSession = MonitorPlaybackAudioSession()
    /// Saved cameras, nearby sightings, pairing and connect attempts (SHELL-02): the shared
    /// flow over the Luna integration, which connects through `session`.
    let cameras: CamerasModel
    @ObservationIgnored let integration: LunaIntegration
    /// Root navigation, covers and the monitor lifetime (SHELL-03): binds each connected camera's
    /// common session to the shared controls (`session.control`).
    let shell: ShellModel
    /// The shared common controls of the camera on the monitor.
    var control: MonitorControlModel { shell.control }
    /// Why Bluetooth discovery is not running (off or not allowed); the pair wizard shows it as
    /// its failure.
    var discoveryFailure: ConnectionFailure?

    init(session: CameraSession? = nil) {
        #if targetEnvironment(simulator)
            if session == nil, MonitorUIReview.isActive { MonitorUIReview.resetMediaFavorites() }
        #endif
        let mediaStorage = MonitorMediaCacheStorage()
        var cameraMedia: CameraMedia?
        #if DEBUG && targetEnvironment(simulator)
            if MonitorUIReview.isActive { cameraMedia = MonitorUIReview.cameraMedia(storage: mediaStorage) }
        #endif
        let session = session ?? CameraSession(backend: Self.makeBackend(), cameraMedia: cameraMedia, mediaStorage: mediaStorage)
        self.session = session
        var port: any LunaConnectPort = session
        var defaults = UserDefaults.standard
        #if targetEnvironment(simulator)
            if MonitorUIReview.isActive { (port, defaults) = MonitorUIReview.cameras() }
        #endif
        integration = LunaIntegration(port: port)
        cameras = CamerasModel(
            integrations: [AppIntegration(integration, slots: IntegrationSlots(nearbyCard: Self.nearbyCard))],
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

    /// A nearby Luna as the cameras page and pair page have always shown it.
    static func nearbyCard(_ camera: NearbyCamera) -> NearbyCardCopy {
        NearbyCardCopy(name: camera.name, subtitle: "Insta360 · nearby", status: "Needs approval on the camera")
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
    @ObservationIgnored private(set) var watchCommandSource: LunaCommandAdmission?
    @ObservationIgnored private(set) var watchSourceSession: LunaCameraSession?
    @ObservationIgnored private(set) var watchSourceEpoch: ControlEpoch?
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
    @ObservationIgnored var inspectorPreview = MonitorInspectorImageRenderer()
    @ObservationIgnored let liveBackdrop = MonitorVideoBackdropRenderer()
    @ObservationIgnored let playbackBackdrop = MonitorVideoBackdropRenderer()
    /// Monitor tools follow the displayed source; watcher scopes must never read the camera bus.
    var monitorSamples: LiveFrameSampleBus { isWatchingFeed ? relayClient.samples : frameSamples }

    /// EV estimated from the live picture, for a camera that meters none: the picture's median
    /// against 18% grey, less where this source's auto exposure places it (`PictureEVMeter`).
    var pictureEV: EvComp? {
        guard assist.evMeterFromPicture else { return nil }
        let bundle = monitorSamples.bundle
        guard let picture = MonitorNDFilterRecommendation.pictureStops(
            lumaHistogram: bundle.samples.histogramLuma, transfer: bundle.transfer)
        else { return nil }
        let status = session.status
        let stops = session.pictureEV.stops(
            picture: picture, context: session.pictureEVContext(transfer: bundle.transfer),
            evComp: status.expoMode == .auto ? status.evComp.map { Double($0.thirds) / 3 } : nil,
            now: ProcessInfo.processInfo.systemUptime)
        return stops.value.map { EvComp(thirds: Int(($0 * 3).rounded())) }
    }
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
            lookProfile: session.connectedCamera?.model.captureProfile?.looks ?? LunaShellMapping.lookProfile,
            isPhoto: photo)
        session.decoder.incomingColorMode = LiveMonitorColorScience.colorMode(
            isPhoto: photo, colorMode: raw)
    }
    /// The problem report sheet, owned by the app root (A2-24): the cameras page and Settings
    /// both open it here, so a draft outlives the camera session and the Settings cover.
    var isProblemReportPresented = false
    var captureSheet: CaptureSheet?
    var captureDrum: CaptureDrumPresentation?
    var keepScreenAwake: Bool = OperatorPrefs.keepScreenAwake {
        didSet { OperatorPrefs.keepScreenAwake = keepScreenAwake }
    }
    var hdrDisplay: Bool = OperatorPrefs.hdrDisplay {
        didSet {
            OperatorPrefs.hdrDisplay = hdrDisplay
            LiveHDRDisplay.app.setEnabled(hdrDisplay)
            LiveHDRDisplay.app.setScreenCaptured(screenCaptured)
        }
    }
    /// Screen recording / AirPlay. HDR present drops to SDR so the file is not boosted.
    var screenCaptured = false {
        didSet { LiveHDRDisplay.app.setScreenCaptured(screenCaptured) }
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
    var headTrackControlTitle = HeadphoneMotionBridge.calibrateTitle
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
    @ObservationIgnored lazy var operatorSession = MonitorOperatorSessionModel(
        shell: shell, assist: assist, display: OperatorPrefs.display)
    var dispLive: MonitorDisplayChrome {
        get { operatorSession.live }
        set { operatorSession.live = newValue }
    }
    var dispClean: MonitorDisplayChrome {
        get { operatorSession.clean }
        set { operatorSession.clean = newValue }
    }
    var operatorSettingsTab: MonitorSettingsTab {
        get { operatorSession.settingsTab }
        set { operatorSession.settingsTab = newValue }
    }
    var chromeEditorMode: MonitorDisplayMode? {
        get { operatorSession.editingMode }
        set { operatorSession.editingMode = newValue }
    }
    var chromeEditorReturnMode: MonitorDisplayMode? {
        get { operatorSession.returnedMode }
        set { operatorSession.returnedMode = newValue }
    }
    var liveChromeInteractive: Bool { operatorSession.interactive }
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
    /// The app-scoped delivery owner: runs survive leaving the gallery or the player.
    let delivery = MonitorDeliveryCoordinator()
    let frameio = FrameioAccountModel(namespace: .openInstaCine)
    /// The Settings account operation, owned here so a settings rehost keeps an accepted sign-in.
    @ObservationIgnored let settingsAccount = MonitorSettingsAccountModel()
    /// The Settings support operations (reports and browser links), kept across a settings rehost.
    @ObservationIgnored let settingsSupport = MonitorSettingsSupportModel()
    /// Settings browser links through the one internet hop; the root reports background and return.
    @ObservationIgnored lazy var browserHandoff = MonitorBrowserInternetHandoff(hop: internetHop)
    var relayHost = WatcherRelayHost(
        versionMismatchReason: WatcherRelayJoin.versionMismatchReason,
        logSubsystem: "com.opencapture.openinstacine", journal: { ControlLiveLog.line($0) })
    @ObservationIgnored private var relaySource: UUID?
    @ObservationIgnored private var relaySessionID: CameraSessionID?
    private var admitsRelaySource: Bool {
        shareThisFeed && relaySource != nil && relaySource == shell.monitor?.id
            && relaySessionID != nil && relaySessionID == shell.monitor?.session.id
            && relaySessionID == shell.control.session?.id
    }
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
    var sharePasscode: String = WatcherRelayKeychain.app.hostPasscode
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
    var watcherRecordDelivery: WatcherRelayCommandDelivery?
    @ObservationIgnored var watcherRecordAdmission: LunaCommandAdmission?
    @ObservationIgnored var watcherRecordEditor: MonitorControlModel.RecordEditor?
    var admitsWatcherRecordDelivery: Bool {
        guard let delivery = watcherRecordDelivery, admitsRelaySource,
            let target = session.lunaSession,
            watcherRecordAdmission?.admits(target.commandOwner) == true
        else { return false }
        return relayHost.admits(delivery)
    }
    var watcherRecordContext: RecordConfirmationContext {
        RecordConfirmationContext(
            mode: session.status.shootingMode, recording: session.control.isRecording,
            locked: session.isLocked, busy: session.controlBusy, phase: session.phase)
    }
    /// The one internet hop off the Luna's Wi-Fi (A2-16): the Wi-Fi joiner leaves and rejoins,
    /// and only the session and camera that left are ever rejoined.
    @ObservationIgnored lazy var internetHop = MonitorInternetHop<InstaHopRoute>(
        port: .init(
            onCameraNetwork: { [weak self] in self?.session.backend.isOnCameraNetwork ?? false },
            leave: { route, _ in
                if let ssid = route.ssid { WiFiJoiner.leave(ssid: ssid) }
                return route
            },
            admitsReturn: { [weak self] route in
                guard let self else { return false }
                return self.session === route.session && route.session.connectedCamera?.id == route.cameraID
            },
            rejoin: { route, _ in await route.session.rejoinSoftAPAfterInternetHop() }))

    /// On the Luna's own network (192.168.42.x), from the integration (SHELL-02 D10).
    var isOnCameraAccessPoint: Bool { internetHop.onCameraNetwork }

    /// Settings reports and browser links (A2-22): the report is this app's diagnostic file, and a
    /// page opened on the camera's Wi-Fi asks, then leaves through the one internet hop.
    var settingsSupportActions: MonitorSettingsSupportActions {
        .init(
            identity: ObjectIdentifier(self), isCurrent: { [weak self] in self != nil },
            requiresInternetConsent: isOnCameraAccessPoint,
            makeReport: { [weak self] in
                guard let self, let url = DiagnosticCenter.shared.writeReport(session: self.session) else {
                    throw MonitorSettingsReportUnavailable(supportEmail: "support@opencapture.org")
                }
                return url
            },
            prepareBrowser: { [weak self] admission in
                guard let self else { return nil }
                return await self.browserHandoff.prepare(route: self.hopRoute, admission: admission)
            },
            open: { await UIApplication.shared.open($0) },
            internetFailure: MonitorSettingsCopy.browserInternetFailure(app: "OpenInstaCine"))
    }

    /// Frame.io sign-in from Settings: on the camera's Wi-Fi it asks, then leaves through the one
    /// internet hop and comes back (A2-23).
    var settingsAccountActions: MonitorSettingsAccountActions {
        frameio.settingsActions(
            hop: internetHop, route: { [weak self] in self?.hopRoute },
            internetFailure: MonitorSettingsCopy.accountInternetFailure)
    }

    /// Where a hop leaves from: the current session, its camera and the network it joined.
    var hopRoute: InstaHopRoute {
        InstaHopRoute(
            session: session, cameraID: session.connectedCamera?.id,
            ssid: session.joinedSSID ?? session.cachedSSID)
    }

    var currentDispMode: MonitorDisplayMode { operatorSession.mode }
    var dispChrome: MonitorDisplayChrome { operatorSession.chrome }
    var isEditingChrome: Bool { operatorSession.isEditing }

    func chrome(for mode: MonitorDisplayMode) -> MonitorDisplayChrome { operatorSession.chrome(for: mode) }

    func chromeSectionMounts(_ section: MonitorDisplayChrome.Section) -> Bool {
        if section == .timecode, !OsmoMonitorPresentation.capabilities(session).timecode { return false }
        return operatorSession.mounts(section)
    }

    func toggleChrome(_ section: MonitorDisplayChrome.Section, for mode: MonitorDisplayMode) {
        operatorSession.toggle(section, in: mode)
    }

    func beginChromeEditing(_ mode: MonitorDisplayMode) {
        liveGimbalPanel = .none
        operatorSession.beginEditing(mode)
    }

    func endChromeEditing() { operatorSession.finishEditing() }

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
        LiveHDRDisplay.app.setEnabled(hdrDisplay)
    }

    /// Connects a saved camera over its preferred setup (debug and stress drivers).
    func reconnect(_ camera: OpenCineCore.SavedCamera) { cameras.connect(camera) }

    /// Connect shows the monitor — never leftover Operator Setup, Media, or Edit view.
    func setShareThisFeed(_ on: Bool) {
        shareThisFeed = on
        OperatorPrefs.shareThisFeed = on
        if on {
            startRelayHost()
        } else {
            relaySource = nil
            relaySessionID = nil
            watcherRecordDelivery = nil
            watcherRecordAdmission = nil
            watcherRecordEditor = nil
            watcherRecordConfirm = false
            relayHost.stop()
            session.decoder.onIdentityFrame = nil
            session.decoder.onIdentityOrientation = nil
        }
    }

    func startRelayHost() {
        guard isLive, shareThisFeed else { return }
        WatcherRelayKeychain.app.hostPasscode = sharePasscode
        let name = UIDevice.current.name
        let camera = session.connectedCamera?.name ?? ""
        relaySource = shell.monitor?.id
        relaySessionID = shell.monitor?.session.id
        relayHost.onCommand = { [weak self] delivery in self?.handleWatcherRelayCommand(delivery) }
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
        relayHost.pollState({ [weak self] in self?.relayState() }, onFailure: { [weak self] in
            self?.setShareThisFeed(false)
            self?.session.controlNote = "Sharing could not start"
        })
    }

    private func relayState() -> WatcherRelayState? {
        guard admitsRelaySource else { return nil }
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
        return state
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
        let code = WatcherRelayKeychain.app.rememberedPasscode(forHost: host.name)
        relayClient.join(
            endpoint: host.endpoint,
            hostName: host.name,
            passcode: code,
            watcherID: WatcherRelayKeychain.app.installID,
            deviceName: UIDevice.current.name)
    }

    func retryWatcherPasscode(_ code: String) {
        WatcherRelayKeychain.app.rememberPasscode(code, forHost: relayClient.hostTitle)
        relayClient.retryPasscode(code)
    }

    func stopWatching() {
        relayClient.leave()
        isWatchingFeed = false
        showsWatcherBrowse = false
        relayBrowser.stop()
    }

    func handleWatcherRelayCommand(_ delivery: WatcherRelayCommandDelivery) {
        guard admitsRelaySource, relayHost.admits(delivery) else { return }
        guard let target = session.lunaSession, target.id == relaySessionID else { return }
        let admission = LunaCommandAdmission(
            owner: target.commandOwner, isCurrent: relayHost.capturedCommandAdmission(for: delivery))
        guard admission.isCurrent else { return }
        let allowed = delivery.command
        switch allowed {
        case .toggleRecording:
            guard !session.isLocked, !session.controlBusy else { return }
            if recordConfirmationEnabled, !session.status.isPhoto {
                guard let editor = session.control.recordEditor() else { return }
                watcherRecordRequest = watcherRecordContext
                watcherRecordDelivery = delivery
                watcherRecordAdmission = admission
                watcherRecordEditor = editor
                watcherRecordConfirm = true
            } else {
                session.pressShutter(admission: admission)
            }
        case .tapFocus(let x, let y, let w, let h):
            let nx = w > 0 ? Double(x) / Double(w) : 0.5
            let ny = h > 0 ? Double(y) / Double(h) : 0.5
            session.markFocus(at: CGPoint(x: nx, y: ny), admission: admission)
        case .setISO(let raw):
            if let idx = IsoIndex(rawValue: UInt8(clamping: raw)) {
                session.setISO(idx, admission: admission)
            }
        case .setShutterDenom(let denom):
            session.setShutterDenom(denom, admission: admission)
        case .setWhiteBalance(let mode, let kelvin, let tint):
            if mode == 0 {
                session.setWhiteBalanceAuto(tint: tint, admission: admission)
            } else {
                session.setWhiteBalanceCustom(kelvin: kelvin, tint: tint, admission: admission)
            }
        case .setColor(let raw):
            if let mode = ColorMode(rawValue: UInt8(clamping: raw)) {
                session.setColorMode(mode, admission: admission)
            }
        case .setZoom(let hundredths):
            session.setZoom(Double(hundredths) / 100.0, admission: admission)
        }
    }

    func confirmWatcherRecording() {
        guard let request = watcherRecordRequest,
            request == watcherRecordContext, admitsWatcherRecordDelivery, request.canConfirm,
            request.recording != nil, let editor = watcherRecordEditor,
            let admission = watcherRecordAdmission
        else { return }
        watcherRecordRequest = nil
        watcherRecordDelivery = nil
        watcherRecordEditor = nil
        watcherRecordAdmission = nil
        session.commitRecording(from: editor, admission: admission)
    }

    /// The monitor's camera changed (shown, replaced or gone): the app's own chrome and relay
    /// follow. The shell already dropped covers and retired the old camera's controls.
    func noteMonitorChanged() {
        session.configureMediaLibrary(service: shell.monitor?.camera.services[(any CameraMediaService).self])
        if isLive { noteBecameLive() } else { noteLeftLive() }
    }

    func noteBecameLive() {
        operatorSession.synchronize(source: shell.monitor?.id)
        captureSheet = nil
        if shareThisFeed { startRelayHost() }
        relayBrowser.stop()
    }

    /// A dropped link must not keep Operator Setup or Edit view around for the next connect.
    func noteLeftLive() {
        operatorSession.close()
        captureSheet = nil
        watchRelay.retireSource()
        watchCommandSource = nil
        watchSourceSession = nil
        watchSourceEpoch = nil
        relaySource = nil
        relaySessionID = nil
        watcherRecordDelivery = nil
        watcherRecordAdmission = nil
        watcherRecordEditor = nil
        relayHost.stop()
        session.decoder.onIdentityFrame = nil
        session.decoder.onIdentityOrientation = nil
        watcherRecordConfirm = false
    }

    /// The app's own link gave up while the monitor showed it, outside recovery (a reconnect
    /// that failed, Bluetooth off): the monitor closes as it always did.
    func noteLinkPhase() {
        if case .live = session.phase, let monitor = shell.monitor {
            session.configureMediaLibrary(service: monitor.camera.services[(any CameraMediaService).self])
        }
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

    /// A feed swipe jumps to a mode through the display owner (refused while locked); it does not cycle.
    func setDisplayMode(clean: Bool) {
        operatorSession.select(clean ? .clean : .live)
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
        watchRelay.onAdmittedToggleRecord = { [weak self] admission in
            self?.watchShutter(photo: false, watchAdmission: admission)
                ?? WatchCommandResult(
                    accepted: false, isRecording: false, error: WatchRelayCopy.connectFirst)
        }
        watchRelay.onAdmittedCapture = { [weak self] admission in
            self?.watchShutter(photo: true, watchAdmission: admission)
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
        let target = session.lunaSession
        let commandSource = target.map {
            LunaCommandAdmission(owner: $0.commandOwner, isCurrent: { true })
        }
        let epoch = target?.current.epoch
        if watchSourceSession !== target || watchSourceEpoch != epoch
            || watchCommandSource?.source != commandSource?.source
        {
            watchRelay.retireSource()
        }
        watchSourceSession = target
        watchSourceEpoch = epoch
        watchCommandSource = commandSource
        watchRelay.ingestState(
            WatchRelayState.snapshot(
                status: session.status,
                phase: session.phase,
                cameraName: session.connectedCamera?.name ?? "",
                feedLive: session.decoder.lastPresentedAt != nil,
                storage: shell.control.snapshot?.storage ?? .unknown))
    }

    func watchToggleRecord() -> WatchCommandResult {
        watchShutter(photo: false)
    }

    func watchCapture() -> WatchCommandResult {
        watchShutter(photo: true)
    }

    private func watchShutter(photo: Bool) -> WatchCommandResult {
        watchShutter(photo: photo, watchAdmission: nil)
    }

    private func watchShutter(photo: Bool, watchAdmission: RelayWatchCommandAdmission?)
        -> WatchCommandResult
    {
        let result = WatchCommandPolicy.answer(
            photo ? .capture : .toggleRecord, facts: {
                WatchCommandFacts(
                    isRecording: session.status.isRecording,
                    isBusy: session.controlBusy || session.isBrowsingMedia,
                    isLive: session.phase == .live, isPhotography: session.status.isPhoto)
            }, shutter: {
                let admission: LunaCommandAdmission?
                if let watchAdmission {
                    guard watchAdmission.isCurrent, let shown = watchCommandSource,
                        let target = watchSourceSession, target === session.lunaSession,
                        watchSourceEpoch == target.current.epoch, shown.admits(target.commandOwner)
                    else { return .targetChanged }
                    admission = LunaCommandAdmission(
                        owner: shown.owner,
                        isCurrent: { shown.isCurrent && watchAdmission.isCurrent })
                } else { admission = nil }
                return session.shutterPress(admission: admission) == nil ? .notSent : .sent
            })
        publishWatchState()
        return result
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
            primaryExperience

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
            if MonitorUIReview.playbackFacts { MonitorPlaybackReviewFacts(model: model) }
        }
        #endif
        .environment(\.font, MonitorTheme.font(16))
        .monitorHDRDisplay(.app, active: model.hdrDisplayActive, screenCaptured: Bindable(model).screenCaptured)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showReliabilityPrompt) {
            ReliabilityConsentPrompt { enabled in
                AppDiagnostics.reporting.setConsent(enabled)
                showReliabilityPrompt = false
            }.environment(model)
        }
        .task {
            while !Task.isCancelled {
                AppDiagnostics.problemReporting.tick()
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
                    AppDiagnostics.consent.defaults = UserDefaults(
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
        }
        .onChange(of: model.relayClient.status) { _, status in
            model.noteWatcherStatusChanged(status)
        }
        .monitorScreenWake(enabled: model.keepScreenAwake)
        .task {
            try? await Task.sleep(for: LaunchSplashTiming.visibleDuration)
            withAnimation(.easeOut(duration: LaunchSplashTiming.fadeOutDuration)) {
                model.showsLaunchSplash = false
            }
            if AppDiagnostics.reporting.isAvailable && !AppDiagnostics.consent.hasDecision {
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
        .onAppear { model.assist.inspectorSceneActive = scenePhase == .active }
        // The shell reports each change once (`AppModel.shell.onSceneActivity`).
        .onChange(of: scenePhase) { _, phase in
            AppDiagnostics.problemReporting.tick()
        }
        .monitorShellSceneActivity(model.shell)
        .monitorBrowserHandoffReturn(model.browserHandoff)
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
                    model.confirmWatcherRecording()
                }
                Button("Cancel", role: .cancel) {
                    model.watcherRecordRequest = nil
                    model.watcherRecordDelivery = nil
                    model.watcherRecordEditor = nil
                    model.watcherRecordAdmission = nil
                }
            }
            .onChange(of: model.watcherRecordContext) { _, _ in
                model.watcherRecordConfirm = false
                model.watcherRecordRequest = nil
                model.watcherRecordDelivery = nil
                model.watcherRecordEditor = nil
                model.watcherRecordAdmission = nil
            }
    }
}

extension LiveHDRDisplay {
    /// This app's HDR display state, read by the feed, scopes and chrome.
    static let app = LiveHDRDisplay()
}
