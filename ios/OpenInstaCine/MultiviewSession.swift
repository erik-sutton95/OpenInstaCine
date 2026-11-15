import Foundation
import Insta360Apple
import Insta360Protocol
import Observation
import OpenCineAppKit
import OpenCineApple
import OpenCineCore
import OpenCineMedia
import OpenCineMulticam
import OpenInstaViewCore
import UIKit

/// OpenInstaCine's Multiview: OpenCine's shared stage (`MultiviewCoordinator`) over Luna's
/// Multiview seams (`LunaMultiview.policy`, `LunaStationCommissioner`, `LunaMemberLink`), with this
/// app as its host. Each tile has its own connection (a `LunaCameraBackend`), its own app session
/// (decoder, status and controls; never the monitor's, and without the monitor's own recovery) and
/// its own member link. Hardware-untested.
@MainActor @Observable
final class MultiviewSession {
    /// One stage slot: its connection, picture and controls.
    @MainActor @Observable final class Tile {
        let backend: LunaCameraBackend
        /// The tile's picture and status (its decoder, the camera's settings) and its controls.
        let session: CameraSession
        /// The stage's link to the tile's camera (OpenCine `Insta360Apple`).
        let link: LunaMemberLink
        let member = MultiviewMember<NearbyCamera>()
        let samples = LiveFrameSampleBus(profile: ScopeExposureCeiling.sourceProfile)
        /// The tile's picture effects: its Auto LUT.
        private(set) var effects = MonitorFrameEffects()
        /// A borrowed Live View, while one is open.
        var liveModel: AppModel?
        /// A settings editor, while one is open.
        var controlsModel: AppModel?

        init(backend: LunaCameraBackend) {
            self.backend = backend
            session = CameraSession(backend: backend)
            // The stage owns this camera's repair; the session never reconnects it itself.
            session.multiviewMember = true
            link = LunaMemberLink(port: backend, conversion: MultiviewSession.conversion)
            session.control.bind(link.session)
        }

        var camera: NearbyCamera? { member.camera }
        var hasPicture: Bool { link.pictureHealth == .live }

        /// Applies the member's Auto LUT choice to the tile's picture.
        func updateLUT() {
            var next = MonitorFrameEffects()
            if member.lutEnabled, link.autoLUT.conversion != nil,
                let cube = BundledLunaLUT.iLogToRec709
            {
                let gpu = cube.colorCube
                next.lutDimension = gpu.size
                next.lutRGBA = gpu.rgbaComponents.withUnsafeBytes { Data($0) }
            }
            effects = next
            session.decoder.effects = next
            session.decoder.adoptIncomingTransfer(session.status.monitorTransfer)
            if next.needsGPUFeed { session.decoder.unlockHardwareDecoder() }
        }

        /// Ends the tile's editor (its controls stay bound to the member's session).
        func retireControls() { controlsModel = nil }
    }

    /// This app's four-camera qualification (Pocket's), not a Luna constant.
    static let budget = ResourceBudget(qualifiedEntries: 4)

    /// The conversion this app grades a reported color profile with (the bundled cube).
    static func conversion(_ colorProfile: String) -> String? {
        colorProfile == LunaColorMode.iLog.label ? "I-Log to Rec.709" : nil
    }

    let tiles: [Tile]
    @ObservationIgnored let coordinator: MultiviewCoordinator<LunaMemberLink>
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// The app's model: the record confirmation preference and the saved cameras' networks.
    @ObservationIgnored weak var appModel: AppModel?
    /// The connection the wizard reads saved setups from.
    @ObservationIgnored let setupBackend: LunaCameraBackend

    /// - Parameters:
    ///   - makeBackend: one new connection (a tile's, a commission's or a return's).
    ///   - discover: the app's passive Luna discovery for the Add list.
    ///   - journal: where the stage journal lives.
    init(
        makeBackend: @escaping @MainActor () -> LunaCameraBackend,
        discover: @escaping @MainActor () -> AsyncStream<[NearbyCamera]>,
        journal: MultiviewJournalStorage = MultiviewStageStore.storage
    ) {
        let tiles = (0..<(Self.budget.qualifiedEntries ?? 4)).map { _ in Tile(backend: makeBackend()) }
        self.tiles = tiles
        let setupBackend = makeBackend()
        self.setupBackend = setupBackend
        coordinator = MultiviewCoordinator(
            links: tiles.map(\.link), members: tiles.map(\.member), policy: LunaMultiview.policy,
            commissioner: LunaStationCommissioner(makePort: { makeBackend() }),
            scanner: LunaNearbyScanner(discover: discover), hostPath: SharedWiFiPath(),
            describe: { LunaMultiview.record($0) }, journal: journal,
            networks: MultiviewNetworkStorage(
                password: { setupBackend.stationPassword(for: $0, hotspot: $1) },
                save: {
                    setupBackend.saveStation(
                        LunaStationNetwork(ssid: $0.ssid, password: $0.password, hotspot: $0.hotspot))
                }),
            budget: Self.budget)
        coordinator.host = self
        // No search or open of one member reaches a camera another member holds.
        for (slot, tile) in tiles.enumerated() {
            tile.backend.stationHostsInUse = { [weak self] in
                guard let self else { return [] }
                return Set(
                    self.tiles.enumerated().compactMap { other in
                        other.offset == slot ? nil : other.element.member.controlHost
                    })
            }
        }
    }
}

extension MultiviewSession: MultiviewHost {
    var confirmsRecord: Bool { appModel?.recordConfirmationEnabled ?? true }
    var editsCameraSettings: Bool { true }
    var appliesAutoLUT: Bool { true }

    func lutChanged(slot: Int) { tiles[slot].updateLUT() }

    /// Lends the tile's own session (picture, status, controls) to a Live View model; the stage
    /// keeps the link and its repair.
    func openLiveView(slot: Int) -> Bool {
        let tile = tiles[slot]
        guard tile.camera != nil else { return false }
        let model = AppModel(session: tile.session)
        model.assist.lutEnabled = tile.member.lutEnabled
        tile.liveModel = model
        return true
    }

    func closeLiveView() {
        for tile in tiles where tile.liveModel != nil {
            tile.member.lutEnabled = tile.liveModel?.assist.lutEnabled ?? tile.member.lutEnabled
            tile.liveModel?.multiviewReturn = nil
            tile.liveModel = nil
            tile.updateLUT()
        }
    }

    func closeEditors() {
        for tile in tiles { tile.retireControls() }
    }

    func memberChanged(slot: Int, _ change: MultiviewMemberChange) {
        let tile = tiles[slot]
        switch change {
        case .camera, .control: tile.retireControls()
        case .removed:
            tile.retireControls()
            tile.session.decoder.reset()
            tile.updateLUT()
        }
    }

    func applicationActivityChanged(_ active: Bool) {
        if active {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        } else if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Multiview transition") {
                [weak self] in
                guard let self else { return }
                UIApplication.shared.endBackgroundTask(self.backgroundTask)
                self.backgroundTask = .invalid
            }
        }
    }

    func stageStopped() {
        for tile in tiles { tile.session.decoder.reset() }
    }

    func log(_ line: String) { ControlLiveLog.line(line) }

    /// The tile's camera readings, from its own session's status.
    func readings(slot: Int) -> MultiviewTileReadings? {
        let tile = tiles[slot]
        guard let camera = tile.camera else { return nil }
        let status = tile.session.status
        let snapshot = tile.link.snapshot
        return MultiviewTileReadings(
            name: camera.name, model: LunaShellMapping.cameraModel.name,
            format: MultiviewReadings.format(status), storage: MultiviewReadings.storage(snapshot.storage),
            timecode: status.timecode, readouts: MultiviewReadings.readouts(status),
            recordingSeconds: status.recordElapsedSec, power: snapshot.power,
            hasPicture: tile.hasPicture, accessibilityValue: tile.hasPicture ? "Live" : "Reconnecting")
    }

    /// Opens a settings editor over the tile's own controls.
    func openCameraSettings(slot: Int) {
        closeEditors()
        let tile = tiles[slot]
        guard tile.camera != nil, coordinator.controlsAvailable(slot: slot) else { return }
        tile.controlsModel = AppModel(session: tile.session)
    }

    func cameraSettings(slot: Int) -> MultiviewCameraSettingsState? {
        let tile = tiles[slot]
        guard tile.controlsModel != nil else { return nil }
        let status = tile.session.status
        return MultiviewCameraSettingsState(
            categories: MultiviewSettingsCategory.offered(
                focus: true, aperture: false, photo: status.isPhoto, audio: false),
            recording: status.isRecording, note: tile.session.controlNote)
    }

    /// The tile's own link is open and no Live View borrows it.
    func admitsControls(slot: Int) -> Bool {
        tiles[slot].link.port.isControlReady && tiles[slot].liveModel == nil
    }
}

/// The tile readouts as Live View words them.
enum MultiviewReadings {
    static func readouts(_ status: CameraStatus) -> [MultiviewReadout] {
        [
            .init(title: "ISO", value: status.iso > 0 ? "\(status.iso)" : "\u{2014}"),
            .init(title: "SHUTTER", value: status.shutterDenom > 0 ? "1/\(status.shutterDenom)" : "\u{2014}"),
            .init(
                title: "WB",
                value: status.whiteBalance.map { $0.mode == .auto ? "Auto" : "\($0.kelvin)K" } ?? "\u{2014}"),
            .init(
                title: "FOCUS",
                value: {
                    switch status.focusMode {
                    case .single: "AF-S"
                    case .continuous: "AF-C"
                    case nil: "\u{2014}"
                    default: "MF"
                    }
                }()),
        ]
    }

    static func format(_ status: CameraStatus) -> String {
        let resolution = status.videoResolution?.label ?? "\u{2014}"
        let rate = status.fps > 0 ? "\(status.fps)p" : "\u{2014}"
        return "\(resolution) \(rate) · \(status.colorMode?.label ?? "\u{2014}")"
    }

    static func storage(_ storage: StorageStatus) -> String {
        storage.storageReadout?.free ?? StorageReadout.unavailable
    }
}
