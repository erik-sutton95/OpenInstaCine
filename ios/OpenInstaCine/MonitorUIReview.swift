#if targetEnvironment(simulator) || DEBUG
    import CryptoKit
    import Foundation
    import MonitorPresentation
    import Insta360Apple
    import Insta360Protocol
    import OpenCineAppKit
    import OpenCineApple
    import OpenCineCameraControls
    import OpenCineCore
    import OpenCineMedia
    import OpenInstaViewCore
    import UIKit

    /// Deterministic opt-in presentation fixture. DEBUG keeps the shared SIMULATED
    /// session fixture available to device test hosts (which have no simulator-only
    /// build); the App Store Release build still excludes it. Opt-in environment
    /// values never run on a physical camera, never persist camera identities, and
    /// never advance the actual connection state machine.
    @MainActor
    enum MonitorUIReview {
        /// The shared typed review every app decodes (`ReviewLaunch`). Other switches (fit,
        /// orientation, motion, unknown core reports, photos) stay raw keys read below.
        static var launch: ReviewLaunch? { .current }
        static var screen: ReviewLaunch.Screen? { launch?.screen }
        /// `OPV_UI_REVIEW_SCREEN=sequence`, this app's own shell walk (`runSequence`).
        static var isSequence: Bool { ProcessInfo.processInfo.environment[ReviewLaunch.Key.screen] == "sequence" }
        static var isActive: Bool { launch != nil || isSequence }
        /// The connection state the cameras and pair pages show: `empty`, `saved-nearby`,
        /// `connecting`, `failure`, `pair-choose`, `pair-approve`, `pair-join`, `pair-video`,
        /// `pair-failure`, `pair-bluetooth`; none is the two saved cameras, idle.
        static var state: String { launch?.state ?? "" }
        static let studioID = "00000000-0000-0000-0000-000000000001"

        /// The shared cameras model's inputs for a review: a scripted Luna backend and a private
        /// defaults domain holding the two saved cameras as the shipping app stored them.
        /// Media favorites persist per camera. Every review starts with none, so a review that
        /// favorites a clip cannot take "Add favorite" away from the next one. Runs before the
        /// session builds its library, which reads them once.
        static func resetMediaFavorites() {
            for key in UserDefaults.standard.dictionaryRepresentation().keys
            where key.hasPrefix("opc.media.fav.") {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

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
                screen == .live
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
                AppDiagnostics.consent.defaults = defaults
                AppDiagnostics.consent.setOptedIn(false)
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
            // The palette ranks tools by persisted use: start every review from the first-run order.
            model.assistToolUsage = MonitorToolUsage()
            WaveformAssist.store.options = .default
            ParadeAssist.store.options = .default
            HistogramAssist.store.options = .default
            VectorscopeAssist.store.options = .default
            AudioAssist.store.options = .init()
            AssistPanelStores.app.reference.positions = FalseColorReferencePositions()
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
            // The one SIMULATED live fixture every app stages (Fixtures/review-live-values.tsv).
            let live = ReviewLiveValues.simulated
            var status = CameraStatus()
            status.iso = live.iso
            status.isoIndex = .iso1600
            status.shutterDenom = live.shutterDenominator
            status.expoMode = .manual
            status.whiteBalance = .custom(kelvin: live.whiteBalanceKelvin, tint: 0)
            status.whiteBalanceKelvin = live.whiteBalanceKelvin
            status.focusMode = .continuous
            status.audioChannel = .stereo
            // Luna's clock is the phone's time of day in whole seconds (D2): no frame field.
            status.timecodeReading = CameraTimecodeReading(
                hours: live.timecodeHours, minutes: live.timecodeMinutes, seconds: live.timecodeSeconds)
            status.colorMode = .iLog
            if let ev = launch?.meteredEV {
                // The camera meters in thirds of a stop: the nearest one it could report.
                status.meteredEv = EvComp(
                    thirds: min(max(Int((ev * 3).rounded()), EvComp.minThirds), EvComp.maxThirds))
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
            status.batteryPercent = live.batteryPercent
            status.storageFreeMb = Int(live.storageFreeMebibytes)
            status.storageTotalMb = Int(live.storageTotalMebibytes)
            status.shootingMode = 1
            status.videoResolution = VideoResolution(rawValue: 0x10)
            status.fps = live.framesPerSecond
            // 4K 25p in the camera's own format codes (live.recordWidth x live.recordHeight).
            status.videoFormat = VideoFormat(resolution: .p4K, frameRate: .fps25)
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
            // The native format and colour drums read these app-session values: stage what the
            // header reports so each drum opens on it.
            let native = nativeRecording(status: status)
            model.session.nativeRecordingFormat = native.format
            model.session.nativeRecordingColor = native.color
            // SIMULATED reports go through the real common session and descriptors. Native
            // integration-only readouts keep the fixture status above.
            if let launch, ![.cameras, .pair].contains(launch.screen) {
                #if DEBUG
                    if launch.connected { presentConnectedCamera(model) } else { presentSimulatedMonitor(model) }
                #else
                    presentSimulatedMonitor(model)
                #endif
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
                    let paused = ProcessInfo.processInfo.environment["OPV_UI_REVIEW_MOTION_PAUSED"] == "1"
                    let session = model.session
                    ShellModel.applyThroughLaunch {
                        session.programmedMoveState = .init(progress: .init(running: true, paused: paused))
                    }
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
            if isSequence { runSequence(model, status: status) }
            switch screen {
            case .pair: model.shell.beginPairing()
            case .settings:
                if let tab = launch?.settingsTab { model.operatorSettingsTab = tab }
                model.shell.open(.settings)
            case .chromeEdit: model.beginChromeEditing(model.currentDispMode)
            case .media, .playback:
                #if DEBUG
                    guard let launch else { return }
                    opensFirstClip = launch.screen == .playback
                    Task {
                        do { try await stageMedia(launch, in: model.session) } catch {
                            assertionFailure("Could not stage the review media: \(error)")
                        }
                        model.session.configureMediaLibrary(
                            service: model.shell.monitor?.camera.services[(any CameraMediaService).self])
                        model.session.mediaLibrary.layout = launch.layout
                        model.shell.open(.media)
                    }
                #endif
            case .cameras, .live, nil: break
            }
        }

        /// SIMULATED monitor, simulator only: isolated session with no network send path.
        static func presentSimulatedMonitor(_ model: AppModel) {
            let session: LunaCameraSession
            if isActive {
                session = simulatedSession(status: model.session.status)
                // The lens range `CameraSession.openSession` gives a connected camera, so the
                // review lays out the zoom chip as main's did.
                session.configureLens(zoomDomain: 1...model.session.zoomCeiling)
            } else {
                session = model.session.backend.openSession()
            }
            model.shell.present(ConnectedCamera(saved: savedCamera(model), session: session))
        }

        private static func savedCamera(_ model: AppModel) -> SavedCamera {
            model.cameras.saved.first
                ?? SavedCamera(
                    id: studioID, integration: LunaCameraSession.integration, advertisedName: "Studio camera",
                    model: "Luna Ultra")
        }

        /// The staged recording format and colour as Luna reports them (options 31 and 35).
        static func nativeRecording(status: CameraStatus) -> (format: LunaVideoResolution?, color: LunaColorMode?) {
            let format = status.videoFormat
                .flatMap { LunaShellMapping.formatTable(values: LunaShellMapping.videoFormatValues)[$0] }
                .flatMap(LunaVideoResolution.init(rawValue:))
            return (format, status.colorMode.map(LunaShellMapping.lunaColorMode))
        }

        /// Uses Luna's actual report decoding and capability projection. UI writes fail locally,
        /// so these fixtures can exercise confirmation/editing without a camera or ACK-as-report.
        static func simulatedSession(status: CameraStatus) -> LunaCameraSession {
            let session = LunaCameraSession(send: { _ in throw CancellationError() },
                functionMode: { LunaFunctionMode.normalVideo.rawValue }, readSettings: {}, readCapture: {})
            session.linkChanged(.streaming, serial: nil)
            report(status, to: session)
            return session
        }

        /// The fixture's reports, through the session's own decoding.
        static func report(_ status: CameraStatus, to session: LunaCameraSession) {
            guard ProcessInfo.processInfo.environment["OPV_UI_REVIEW_CORE_UNKNOWN"] != "1" else { return }
            do {
                var device = try LunaDeviceStatus(response: Data())
                device.photoSubMode = 100; device.videoSubMode = 0
                session.ingest(device: device)
                if (0...100).contains(status.batteryPercent) {
                    let battery = try ProtoMessage.integer(field: 2, value: UInt64(status.batteryPercent))
                        + ProtoMessage.integer(field: 1, value: status.charging ? 1 : 0)
                    let options = try ProtoMessage.blob(field: 11, value: battery)
                    session.ingest(device: try LunaDeviceStatus(response: ProtoMessage.blob(field: 2, value: options)))
                }
                if status.storageTotalMb > 0, status.storageFreeMb >= 0 {
                    // The legacy review input is MiB; publish its exact bytes through the
                    // same device-report decoder as a connected source, including zero free.
                    let free = UInt64(status.storageFreeMb).multipliedReportingOverflow(by: 1_048_576)
                    let total = UInt64(status.storageTotalMb).multipliedReportingOverflow(by: 1_048_576)
                    if !free.overflow, !total.overflow {
                        let volume = try ProtoMessage.integer(field: 2, value: free.partialValue)
                            + ProtoMessage.integer(field: 3, value: total.partialValue)
                            + ProtoMessage.integer(field: 4, value: 2)
                        session.ingest(device: try LunaDeviceStatus(response:
                            ProtoMessage.blob(field: 2, value: ProtoMessage.blob(field: 176, value: volume))))
                    }
                }
                let exposure = try ProtoMessage.integer(field: 1, value: LunaExposureProgram.manual.rawValue)
                    + ProtoMessage.integer(field: 2, value: UInt64(status.iso))
                    + ProtoMessage.double(field: 3, value: 1 / Double(status.shutterDenom))
                let options = try ProtoMessage.blob(field: 21, value: exposure)
                    + ProtoMessage.integer(field: 39, value: UInt64(status.whiteBalanceKelvin))
                session.ingest(settings: try LunaPhotographySettings(response: ProtoMessage.blob(field: 2, value: options)))
                // The staged recording format and colour, as the camera reports them (options 31
                // and 35), so the review header shows the format like the other apps.
                var recording = Data()
                let native = nativeRecording(status: status)
                if let format = native.format {
                    recording += try ProtoMessage.integer(field: 31, value: format.rawValue)
                }
                if let color = native.color {
                    recording += try ProtoMessage.integer(field: 35, value: color.rawValue)
                }
                if !recording.isEmpty {
                    session.ingest(settings: try LunaPhotographySettings(
                        response: ProtoMessage.blob(field: 2, value: recording)))
                }
                let capture = try ProtoMessage.integer(field: 1, value: status.isRecording ? 1 : 0)
                session.ingest(capture: try LunaCaptureStatus(notification: capture))
                if let timecode = status.timecodeReading { session.ingest(timecode: timecode) }
            } catch { assertionFailure("Invalid SIMULATED monitor fixture: \(error)") }
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
                    message:
                        "OpenInstaCine needs Bluetooth access to find the camera. Open Settings, turn on Bluetooth for OpenInstaCine, then try again.",
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

        /// Only the scripted camera advertises, and only in the states that announce it.
        func hasSeen(_ cameraID: UUID) -> Bool {
            cameraID == UUID(uuidString: "00000000-0000-0000-0000-000000000003")
                && (state == "saved-nearby" || state.hasPrefix("pair-"))
        }

        /// Stores nothing, so a saved connect never waits for a sighting.
        func hasSavedWiFi(cameraID: UUID) -> Bool { false }

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

    #if DEBUG
        extension MonitorUIReview {
            /// `ReviewLaunch(screen: .playback)`: the Media page opens its first clip once, as a tap would.
            static var opensFirstClip = false
            /// `OPV_UI_REVIEW_PLAYBACK_FACTS=<path>` mounts the native player facts (`MonitorPlaybackReviewFacts`).
            static let playbackFacts = ProcessInfo.processInfo.environment["OPV_UI_REVIEW_PLAYBACK_FACTS"] != nil
            /// The SIMULATED camera of a `connected` review; `stageMedia` puts the staged media on its card.
            static let camera = LunaReviewCamera(clips: [])
            /// The review session's camera media with `ReviewCameraHTTP` as its HTTP side, so no file
            /// request leaves the simulator.
            static func cameraMedia(storage: MonitorMediaCacheStorage) -> CameraMedia {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [ReviewCameraHTTP.self]
                return CameraMedia(httpConfiguration: configuration, storage: storage)
            }

            /// `connected`: the app's own backend with the SIMULATED camera behind its control link,
            /// so the real Luna session, media service and catalog run. Live clips carry the camera's
            /// deletable fact and the camera operations are offered, as on a connected Luna. No network.
            static func presentConnectedCamera(_ model: AppModel) {
                let backend = model.session.backend
                backend.connect(review: camera)
                let session = backend.openSession()
                report(model.session.status, to: session)
                session.configureLens(zoomDomain: 1...model.session.zoomCeiling)
                var services = CameraServices()
                if let media = backend.mediaService(for: session.id) {
                    services.register(media, as: (any CameraMediaService).self)
                }
                model.session.phase = .live
                model.shell.present(ConnectedCamera(saved: savedCamera(model), session: session, services: services))
            }

            /// Media written through the library's own cache and catalog, as finished downloads leave
            /// it: `mediaCount` generated clips (`ReviewClip`), or the two decoded-video inputs of
            /// `OPV_SIM_FEED_MANIFEST`, or two generated stills with `OPV_UI_REVIEW_MEDIA_PHOTOS=1`.
            static func stageMedia(_ launch: ReviewLaunch, in session: CameraSession) async throws {
                let cache = session.mediaLibrary.cache
                try await cache.directory.clear(preserving: [])
                let environment = ProcessInfo.processInfo.environment
                let media: [StagedMedia] =
                    if environment["OPV_SIM_FEED_MANIFEST"] != nil { try decodedInputs() }
                    else if environment["OPV_UI_REVIEW_MEDIA_PHOTOS"] == "1" { try stills() }
                    else { try await clips(launch.mediaCount) }
                let records = try cache.codec.decode(JSONEncoder().encode(media.map(\.file)))
                for (record, item) in zip(records, media) {
                    for address in record.address.representations.values {
                        try cache.directory.write(item.bytes, at: address)
                    }
                    if let thumbnail = item.thumbnail, let address = record.address.thumbnail {
                        try cache.directory.write(thumbnail, at: address)
                    }
                }
                try cache.save(records)
                // A connected camera lists the same clips, as the camera that recorded them would.
                if launch.connected { camera.clips = media.map { reviewClip($0.file) } }
                // The library loads its catalog once: closed and unkeyed, the next configuration
                // builds one over these.
                session.mediaLibrary.close()
                session.mediaLibraryKey = nil
            }

            private static func reviewClip(_ file: MediaFile) -> LunaReviewCamera.Clip {
                let size = (file.resolution ?? "").split(separator: "x").compactMap { Int($0) }
                return .init(uri: file.path, byteCount: file.sizeBytes, milliseconds: UInt64(file.durationSeconds) * 1000,
                    width: size.first ?? 0, height: size.last ?? 0, fps: UInt64(file.fps ?? 0),
                    stamp: file.filenameTimestamp.flatMap { UInt64($0) })
            }

            private struct StagedMedia {
                let file: MediaFile
                let bytes: Data
                var thumbnail: Data? = nil
            }

            /// One clip a minute from 2026-09-12 12:00 UTC, named as the camera names them.
            private static func clips(_ count: Int) async throws -> [StagedMedia] {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("ReviewClip.mp4")
                try await ReviewClip.write(to: url)
                let bytes = try Data(contentsOf: url)
                let names = DateFormatter()
                names.locale = Locale(identifier: "en_US_POSIX")
                names.timeZone = TimeZone(identifier: "UTC")
                names.dateFormat = "yyyyMMdd'_'HHmmss"
                return (0..<count).map { index in
                    let stamp = names.string(from: Date(timeIntervalSince1970: 1_789_214_400 + Double(index) * 60))
                    let suffix = String(format: "_00_%03d", index + 1)
                    return StagedMedia(file: MediaFile(
                        path: "DCIM/Camera01/VID_\(stamp)\(suffix).MP4", thumbPath: "DCIM/Camera01/IMG_\(stamp)\(suffix).JPG",
                        handle: UInt32(index + 1), sizeBytes: UInt64(bytes.count),
                        durationSeconds: ReviewClip.seconds, resolution: "640x360", fps: 24), bytes: bytes)
                }
            }

            private static func stills() throws -> [StagedMedia] {
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
                let image = renderer.image { context in
                    UIColor.systemGreen.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
                }
                guard let bytes = image.jpegData(compressionQuality: 0.8) else { throw CocoaError(.fileWriteUnknown) }
                return (1...2).map { value in
                    StagedMedia(file: MediaFile(
                        path: "UI-REVIEW/IMG_20261003_14000\(value)_00_00\(value).JPG",
                        thumbPath: "UI-REVIEW/IMG_20261003_14000\(value)_00_00\(value).JPG",
                        sizeBytes: UInt64(bytes.count), resolution: "32x32"), bytes: bytes)
                }
            }

            private struct PlaybackInput: Decodable {
                let name: String
                let path: String
                let reference: String
                let sha256: String
                let reference_sha256: String
                let size: Int
                let duration: Int
                let width: Int
                let height: Int
                let fps: Int
            }
            private struct PlaybackManifest: Decodable { let files: [PlaybackInput] }
            private enum InputError: Error { case invalid }

            /// The two decoded-video inputs a native playback review supplies, checked against their
            /// manifest; ordinary legacy addresses, A with a proxy.
            private static func decodedInputs() throws -> [StagedMedia] {
                let environment = ProcessInfo.processInfo.environment
                guard let manifestPath = environment["OPV_SIM_FEED_MANIFEST"] else { throw InputError.invalid }
                let manifest = try JSONDecoder().decode(PlaybackManifest.self,
                    from: Data(contentsOf: URL(fileURLWithPath: manifestPath)))
                guard manifest.files.count == 2 else { throw InputError.invalid }
                return try manifest.files.enumerated().map { index, input in
                    let key = index == 0 ? "OPV_SIM_FEED_CLIP" : "OPV_SIM_FEED_CLIP_B"
                    guard let path = environment[key], path == input.path,
                        input.name == (index == 0 ? "A" : "B"), input.duration == 12,
                        input.width == 640, input.height == 360, input.fps == 24 else { throw InputError.invalid }
                    let data = try Data(contentsOf: URL(fileURLWithPath: path))
                    let reference = try Data(contentsOf: URL(fileURLWithPath: input.reference))
                    func hash(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
                    guard data.count == input.size, hash(data) == input.sha256,
                        hash(reference) == input.reference_sha256,
                        let jpeg = UIImage(data: reference)?.jpegData(compressionQuality: 0.9) else { throw InputError.invalid }
                    let chronology = 2 - index
                    let suffix = String(format: "14000%d_00_00%d", chronology, chronology)
                    return StagedMedia(file: MediaFile(path: "DCIM/VID_20261003_\(suffix).MP4",
                        thumbPath: "DCIM/IMG_20261003_\(suffix).JPG", sizeBytes: UInt64(data.count),
                        durationSeconds: input.duration, resolution: "640x360", fps: input.fps,
                        proxyPath: index == 0 ? "DCIM/LRV_20261003_\(suffix).LRV" : nil), bytes: data, thumbnail: jpeg)
                }
            }
        }

        /// The SIMULATED camera's HTTP server. The staged clips' bytes are already in the phone's cache
        /// (`stageMedia`), so it answers every file request as a camera without that file does: 404, at
        /// once. Playback then falls back to the cached original, as it does on a real camera.
        private final class ReviewCameraHTTP: URLProtocol, @unchecked Sendable {
            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
            override func startLoading() {
                guard let url = request.url,
                    let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)
                else {
                    client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                    return
                }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
            }
            override func stopLoading() {}
        }
    #endif
#endif
