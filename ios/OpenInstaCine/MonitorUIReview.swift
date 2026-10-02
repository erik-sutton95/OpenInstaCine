#if targetEnvironment(simulator)
    import Foundation
    import Insta360Apple
    import Insta360Protocol
    import OpenCineCore
    import OpenPocketViewCore
    import UIKit

    /// Deterministic simulator-only presentation fixture. Opt-in environment values
    /// never run on a physical camera or in an App Store build, never persist camera
    /// identities, and never advance the actual connection state machine.
    @MainActor
    enum MonitorUIReview {
        static var screen: String? { ProcessInfo.processInfo.environment["OPV_UI_REVIEW_SCREEN"] }
        static var isActive: Bool { screen != nil }
        /// The connection state the cameras and pair pages show: `empty`, `saved-nearby`,
        /// `connecting`, `failure`, `pair-choose`, `pair-approve`, `pair-join`, `pair-video`,
        /// `pair-failure`, `pair-bluetooth`; none is the two saved cameras, idle.
        static var state: String {
            let environment = ProcessInfo.processInfo.environment
            return environment["OPV_UI_REVIEW_STATE"] ?? (environment["OPV_UI_REVIEW_CONNECTING"] == "1" ? "connecting" : "")
        }
        static let studioID = "00000000-0000-0000-0000-000000000001"

        /// The shared cameras model's inputs for a review: a scripted Luna backend and a private
        /// defaults domain holding the two saved cameras as the shipping app stored them.
        static func cameras() -> (any LunaConnectPort, UserDefaults) {
            // Installed-build reviews use the existing store without reseeding it.
            if ProcessInfo.processInfo.environment["OPV_UI_REVIEW_STORED_CAMERAS"] == "1" {
                return (ReviewLunaPort(state: state), .standard)
            }
            let name = "opc.monitor.presentation.review.cameras"
            let defaults = UserDefaults(suiteName: name)!
            defaults.removePersistentDomain(forName: name)
            if state != "empty" {
                let past = Date.distantPast.timeIntervalSinceReferenceDate
                let records: [[String: Any]] = [
                    [
                        "id": studioID, "advertisedName": "Studio camera", "modelName": "Luna Ultra",
                        "lastConnectedAt": past, "wifiSSID": "Studio-5G", "hotspotSSID": "Rig iPhone",
                    ],
                    [
                        "id": "00000000-0000-0000-0000-000000000002", "advertisedName": "Travel camera",
                        "modelName": "Luna Ultra", "lastConnectedAt": past,
                    ],
                ]
                defaults.set(try? JSONSerialization.data(withJSONObject: records), forKey: "OpenInstaCine.SavedCameras")
            }
            return (ReviewLunaPort(state: state), defaults)
        }

        #if DEBUG
            static var zoomControls: Bool {
                screen == "live"
                    && ProcessInfo.processInfo.environment["OPV_UI_REVIEW_ZOOM_CONTROLS"]
                        == "1"
            }
        #endif

        static func prepare(_ model: AppModel) {
            // Presentation reviews do not send reports or inherit first-run consent.
            // Keep the operator's real choice and explicit consent reviews separate.
            if ProcessInfo.processInfo.environment["OPV_CONSENT_REVIEW_ID"] == nil,
                let defaults = UserDefaults(suiteName: "opc.monitor.presentation.review")
            {
                ReliabilityReportingConsent.defaults = defaults
                ReliabilityReportingConsent.setOptedIn(false)
            }
            model.showsLaunchSplash = false
            // `OPV_UI_REVIEW_ORIENTATION=landscapeLeft|landscapeRight|portrait` turns the scene.
            if let raw = ProcessInfo.processInfo.environment["OPV_UI_REVIEW_ORIENTATION"] {
                let mask: UIInterfaceOrientationMask =
                    raw == "landscapeLeft" ? .landscapeLeft : raw == "landscapeRight" ? .landscapeRight : .portrait
                for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
                }
            }
            model.assist.lutEnabled = false
            model.assist.peaking = false
            model.assist.zebra = false
            model.assist.falseColor = false
            model.assist.falseColorReference = true
            model.assist.waveform = false
            model.assist.parade = false
            model.assist.histogram = false
            model.assist.vectorscope = false
            model.assist.trafficLights = false
            model.assist.ndMeter = false
            model.assist.evMeter = true
            model.assist.audioMeters = false
            model.assist.guides = false
            model.assist.grid = false
            model.assist.crosshair = false
            model.assist.mirror = false
            model.assist.configureTool = nil
            model.assist.clean = false
            WaveformAssist.store.options = .default
            ParadeAssist.store.options = .default
            HistogramAssist.store.options = .default
            VectorscopeAssist.store.options = .default
            AudioAssist.store.options = .init()
            FalseColorReferencePositionStore.shared.positions = FalseColorReferencePositions()
            WaveformAssist.store.sessionCenter = nil
            WaveformAssist.store.sessionCenterPortrait = nil
            ParadeAssist.store.sessionCenter = nil
            ParadeAssist.store.sessionCenterPortrait = nil
            HistogramAssist.store.sessionCenter = nil
            HistogramAssist.store.sessionCenterPortrait = nil
            VectorscopeAssist.store.sessionCenter = nil
            VectorscopeAssist.store.sessionCenterPortrait = nil
            model.recordConfirmationEnabled = true
            model.portraitFeedAspect =
                ProcessInfo.processInfo.environment["OPV_UI_REVIEW_FIT"] == "1" ? .fit16x9 : .fill
            var status = CameraStatus()
            status.iso = 1600
            status.isoIndex = .iso1600
            status.shutterDenom = 50
            status.expoMode = .manual
            status.whiteBalance = .custom(kelvin: 5600, tint: 0)
            status.whiteBalanceKelvin = 5600
            status.focusMode = .continuous
            status.audioChannel = .stereo
            status.timecode = "15:39:50:00"
            status.colorMode = .iLog
            if let raw = ProcessInfo.processInfo.environment["OPV_UI_REVIEW_METERED_EV"],
                let value = UInt8(raw)
            {
                status.meteredEv = EvComp(rawValue: value)
            }
            #if DEBUG
                if zoomControls {
                    let recordingDLog2 =
                        ProcessInfo.processInfo.environment["OPV_UI_REVIEW_ZOOM_DLOG2_RECORDING"]
                        == "1"
                    status.colorMode = recordingDLog2 ? .dLog2 : .normal
                    status.isRecording = recordingDLog2
                    status.zoomLens = CamFov.lens1x
                }
            #endif
            status.batteryPercent = 68
            status.storageFreeMb = 107 * 1024
            status.storageTotalMb = 128 * 1024
            status.shootingMode = 1
            status.videoResolution = VideoResolution(rawValue: 0x10)
            status.fps = 25
            // A real body lists several rates, so reviews show the frame-rate drum
            // with neighbours on both sides of the current 25p.
            status.availableVideoFormats = [
                .fps24, .fps25, .fps30, .fps48, .fps50, .fps60,
            ].map { VideoFormat(resolution: VideoResolution(rawValue: 0x10), frameRate: $0) }
            status.availableIsoIndices = [
                .iso100, .iso200, .iso400, .iso800, .iso1600, .iso3200, .iso6400,
            ]
            status.availableShutterDenoms = [25, 50, 100, 200, 500]
            model.session.status = status
            // SIMULATED reports go through the real common session and descriptors. Native
            // integration-only readouts keep the fixture status above.
            if ["live", "settings", "media"].contains(screen) {
                presentSimulatedMonitor(model)
                model.control.onChange = {}
            }
            if ProcessInfo.processInfo.environment["OPV_UI_REVIEW_MOTION"] == "1" {
                model.session.gimbalProgram = GimbalProgram(
                    a: .init(yawDeg: 0, pitchDeg: 0, zoom: 1, nativePitchDeg: 0),
                    b: .init(yawDeg: 30, pitchDeg: 0, zoom: 1, nativePitchDeg: 0),
                    c: .init(yawDeg: 30, pitchDeg: 20, zoom: 1, nativePitchDeg: -20),
                    durationAB: 3, durationBC: 2, smoothness: 0.5)
                if ProcessInfo.processInfo.environment["OPV_UI_REVIEW_MOTION_ZOOM"] == "1" {
                    model.session.gimbalProgram.b?.zoom = 3
                    model.session.gimbalProgram.c?.zoom = 2
                    model.session.status.zoomLens = CamFov.lens1x
                }
                if ProcessInfo.processInfo.environment["OPV_UI_REVIEW_MOTION_RUNNING"] == "1" {
                    model.session.gimbalMoveRunning = true
                    model.session.gimbalMoveCanPause = true
                    model.session.gimbalMovePaused =
                        ProcessInfo.processInfo.environment["OPV_UI_REVIEW_MOTION_PAUSED"] == "1"
                }
            }
            model.session.liveSignalBars = 4
            model.session.liveFPS = "25.00"
            let cameras = model.cameras
            switch state {
            case "connecting", "failure":
                if let studio = cameras.saved.first(where: { $0.id == studioID }) { cameras.connect(studio) }
            case "pair-approve", "pair-join", "pair-video", "pair-failure":
                Task {
                    // The scripted camera appears once discovery starts.
                    while cameras.nearby.isEmpty { try? await Task.sleep(for: .milliseconds(20)) }
                    cameras.selection = cameras.nearby[0].id
                    cameras.connect(cameras.nearby[0])
                }
            default: break
            }
            if screen == "pair" { model.shell.beginPairing() }
            if screen == "settings" { model.shell.open(.settings) }
            if screen == "media" { model.shell.open(.media) }
            if screen == "sequence" { runSequence(model, status: status) }
        }

        /// SIMULATED monitor, simulator only: isolated session with no network send path.
        static func presentSimulatedMonitor(_ model: AppModel) {
            let saved =
                model.cameras.saved.first
                ?? SavedCamera(
                    id: studioID, integration: LunaCameraSession.integration, advertisedName: "Studio camera",
                    model: "Luna Ultra")
            let session: LunaCameraSession
            if isActive {
                session = simulatedSession(status: model.session.status)
            } else {
                session = model.session.backend.openSession()
            }
            model.shell.present(ConnectedCamera(saved: saved, session: session))
        }

        /// Uses Luna's actual report decoding and capability projection. UI writes fail locally,
        /// so these fixtures can exercise confirmation/editing without a camera or ACK-as-report.
        static func simulatedSession(status: CameraStatus) -> LunaCameraSession {
            let session = LunaCameraSession(send: { _ in throw CancellationError() },
                functionMode: { LunaFunctionMode.normalVideo.rawValue }, readSettings: {}, readCapture: {})
            session.linkChanged(.streaming, serial: nil)
            guard ProcessInfo.processInfo.environment["OPV_UI_REVIEW_CORE_UNKNOWN"] != "1" else { return session }
            do {
                var device = try LunaDeviceStatus(response: Data())
                device.photoSubMode = 100; device.videoSubMode = 0
                session.ingest(device: device)
                let exposure = try ProtoMessage.integer(field: 1, value: LunaExposureProgram.manual.rawValue)
                    + ProtoMessage.integer(field: 2, value: UInt64(status.iso))
                    + ProtoMessage.double(field: 3, value: 1 / Double(status.shutterDenom))
                let options = try ProtoMessage.blob(field: 21, value: exposure)
                    + ProtoMessage.integer(field: 39, value: UInt64(status.whiteBalanceKelvin))
                session.ingest(settings: try LunaPhotographySettings(response: ProtoMessage.blob(field: 2, value: options)))
                let capture = try ProtoMessage.integer(field: 1, value: status.isRecording ? 1 : 0)
                session.ingest(capture: try LunaCaptureStatus(notification: capture))
                let clock = (status.timecode ?? "").split(separator: ":").compactMap { Int($0) }
                if clock.count == 4 {
                    session.ingest(timecode: CameraTimecode(hours: clock[0], minutes: clock[1], seconds: clock[2], frames: clock[3]))
                }
            } catch { assertionFailure("Invalid SIMULATED monitor fixture: \(error)") }
            return session
        }

        /// `OPV_UI_REVIEW_SCREEN=sequence`: cameras, live, settings, live, media, live, cameras in
        /// one launch, one step every `OPV_UI_REVIEW_STEP` seconds (default 4), logging the
        /// shell's monitor host count at each step (`SHELL03 step=...`).
        static func runSequence(_ model: AppModel, status: CameraStatus) {
            let step = Double(ProcessInfo.processInfo.environment["OPV_UI_REVIEW_STEP"] ?? "") ?? 4
            Task { @MainActor in
                @MainActor func note(_ name: String) async {
                    try? await Task.sleep(for: .seconds(0.5))
                    let shell = model.shell
                    NSLog(
                        "SHELL03 step=%@ route=%@ cover=%@ monitor=%@ mounted=%ld unmounted=%ld", name,
                        "\(shell.route)", shell.cover.map { "\($0)" } ?? "none",
                        shell.monitor?.id.uuidString ?? "none", shell.hostsMounted, shell.hostsUnmounted)
                }
                await note("1-cameras")
                let steps: [(String, @MainActor () -> Void)] = [
                    ("2-live", {
                        presentSimulatedMonitor(model)
                        model.control.onChange = {}
                        model.session.status = status
                    }),
                    ("3-settings", { model.shell.open(.settings) }),
                    ("4-live", { model.shell.dismissCover() }),
                    ("5-media", { model.shell.open(.media) }),
                    ("6-live", { model.shell.dismissCover() }),
                    ("7-cameras", { model.disconnect() }),
                ]
                for (name, action) in steps {
                    try? await Task.sleep(for: .seconds(step - 0.5))
                    action()
                    await note(name)
                }
            }
        }
    }

    /// Simulator review only: a scripted Luna backend, so the shared pages show each connection
    /// state without a camera. Never connects, never stores anything.
    @MainActor
    final class ReviewLunaPort: LunaConnectPort {
        var eventHandler: ((CameraBackendEvent) -> Void)?
        var connectedSerial: String? { nil }
        var joinedNetwork: String? { "LUNA-4D5E6F" }
        private let state: String
        private let backend = LunaCameraBackend(useExistingNetwork: true)

        init(state: String) { self.state = state }

        func startScan() async throws {
            if state == "pair-bluetooth" {
                throw ConnectionFailure(
                    reason: .permission(.bluetooth), title: "Couldn’t connect over Camera Wi-Fi",
                    message: "Bluetooth access is disabled for this app. Enable it in Settings → Privacy & Security → Bluetooth.",
                    actions: [.openSettings, .retry], code: "review.bluetooth.denied")
            }
            guard state == "saved-nearby" || state.hasPrefix("pair-") else { return }
            eventHandler?(
                .discovered(
                    MonitorCamera(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "4D5E6F",
                        model: LunaProtocol.model, capabilities: [])))
        }

        func stopScan() {}

        func connect(to camera: MonitorCamera) async throws {
            switch state {
            case "connecting", "pair-join": eventHandler?(.phase(.joiningWiFi))
            case "pair-approve": eventHandler?(.phase(.awaitingApproval))
            case "pair-video": eventHandler?(.phase(.openingVideo))
            case "failure", "pair-failure":
                throw ConnectionFailure(
                    reason: .notApproved, phase: .awaitingApproval, title: "Couldn’t connect over Camera Wi-Fi",
                    message: "Approval timed out. Connect again and tap Allow on the camera's screen.",
                    actions: [.retry], code: "review.approval.timeout")
            default: break
            }
            try await Task.sleep(for: .seconds(3600))
        }

        func disconnect() {}
        func openSession() -> LunaCameraSession { backend.openSession() }
        func forget(cameraID: UUID) {}
    }
#endif
