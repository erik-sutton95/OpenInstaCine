import Foundation
import Insta360Apple
import Insta360Protocol
import OpenCineCameraControls
import OpenCineCore
import OpenInstaViewCore

/// Optimistic values the operator just asked for, held until the camera reports
/// them or the settle window runs out (same `CameraValuePin` rule as the Osmo shell).
/// ISO, shutter, white balance and record are not here: their pending state is the Core
/// operation (CameraSessionCore.swift).
struct LunaControlPins {
    var ev: CameraValuePin<EvComp>?
    var color: CameraValuePin<ColorMode>?
    var format: CameraValuePin<VideoFormat>?
    var shootingMode: CameraValuePin<Int>?
    var gimbalMode: CameraValuePin<GimbalMode>?
    var gimbalSpeed: CameraValuePin<GimbalSpeed>?
    var focus: CameraValuePin<FocusOption>?
    var faceMetering: CameraValuePin<Bool>?
    var photoInFlight = false
}

/// Luna ↔ shared monitor vocabulary. Wire numbers stay in `Insta360Protocol`;
/// everything the shared screens read goes through here.
enum LunaShellMapping {
    static let cameraModel = CameraModel(name: "Luna Ultra", datalinkPort: 0, tcpPoke: false, verified: true)
    /// Observed preview: 1280×720 HEVC at 25 fps.
    static let previewFPS: Double = 25
    /// fw 1.1.15 verified: 1.0…15.0 (values outside are ignored, not clamped).
    static let defaultZoomCeiling: Double = 15
    /// fw 1.1.15 official presets.
    static let zoomChips: [Double] = [1, 2, 3, 6, 15]

    /// Luna names and media addressing for a session: every file at its own path on the camera AP.
    static let profile = CameraLabelProfile(
        shootingModeLabels: shootingModeLabels, colorModeLabels: [.normal: "Standard"],
        gimbalModeLabels: gimbalModeLabels,
        media: MediaHTTP.Route(host: "192.168.42.1", addressing: .directPath))

    // MARK: Shooting mode

    static func shootingMode(_ mode: LunaShootingMode) -> ShootingMode {
        switch mode {
        case .video: .video
        case .timelapse: .timeLapse
        case .timeShift: .hyperLapse
        case .slowMotion: .slowMo
        case .pureVideo: .superNight
        case .photo, .pano: .photo
        }
    }

    static func lunaShootingMode(_ mode: ShootingMode) -> LunaShootingMode? {
        switch mode {
        case .video: .video
        case .timeLapse: .timelapse
        case .hyperLapse: .timeShift
        case .slowMo: .slowMotion
        case .superNight: .pureVideo
        case .photo: .photo
        case .livePhoto: nil
        }
    }

    /// Luna names for the shared mode drum (installed once at launch).
    static let shootingModeLabels: [ShootingMode: String] = [
        .slowMo: "Slow Motion", .timeLapse: "Timelapse", .hyperLapse: "TimeShift",
        .superNight: "PureVideo",
    ]

    // MARK: Color

    static func colorMode(_ luna: LunaColorMode) -> ColorMode {
        switch luna {
        case .iLog: .iLog
        case .dolbyVision: .dolbyVision
        case .hdr: .hdr
        case .standard, .vivid: .normal
        }
    }

    static func lunaColorMode(_ mode: ColorMode) -> LunaColorMode {
        switch mode {
        case .iLog, .dLog, .dLog2, .dLogM: .iLog
        case .dolbyVision: .dolbyVision
        case .hdr: .hdr
        case .normal, .normal10: .standard
        }
    }

    static let colorModes: [ColorMode] = [.normal, .iLog, .dolbyVision]

    /// What the phone preview actually carries. Color Recovery (camera default) bakes a
    /// Rec.709 look into the I-Log preview; with Recovery off the preview is flat I-Log.
    static func previewColorMode(recording: ColorMode?, recoveryOff: Bool) -> ColorMode {
        guard recording == .iLog else { return .normal }
        return recoveryOff ? .iLog : .normal
    }

    // MARK: Exposure

    /// Luna ISO stops offered by the official wheel.
    static let isoValues = LunaCameraSession.isoValues
    static let isoIndices: [IsoIndex] = [.auto] + isoValues.compactMap(isoIndex)

    static func isoIndex(_ iso: Int) -> IsoIndex? {
        IsoIndex.allCases.first { $0.isoValue == iso }
    }

    /// Official Video wheel, slowest last. fw 1.1.15 adds 1/15…1/5.
    static let shutterDenoms = LunaCameraSession.shutterDenominators

    // MARK: Format

    /// Shared `VideoResolution` for a Luna frame size. DJI bytes where the shape
    /// matches, Luna bytes (0xD0…) otherwise; labels come from the core table.
    static let unknownResolution = VideoResolution(rawValue: 0xDF)

    static func resolution(width: Int, height: Int) -> VideoResolution {
        let long = max(width, height)
        let portrait = height > width
        if width == height { return long == 3072 ? .p3K_1x1 : unknownResolution }
        switch (long, portrait) {
        case (1920, false): return .p1080
        case (1920, true): return .p1080_9x16
        case (2688...2720, false): return .p2_7K
        case (2688...2720, true): return .p2_7K_9x16
        case (2880...3072, true): return .p3K_9x16
        case (3840, false) where height < 2000: return .p4K_235
        case (7680, false) where height < 4000: return .p8K_235
        case (2880...3072, false): return .p3K
        case (3840, false): return .p4K
        case (3840, true): return .p4K_9x16
        case (5120...5760, false): return .p6K
        case (7680, false): return .p8K
        default: return unknownResolution
        }
    }

    static func videoFormat(_ luna: LunaVideoResolution) -> VideoFormat? {
        guard let rate = VideoFrameRate.fromFps(Int(luna.framesPerSecond.rounded())) else { return nil }
        return VideoFormat(
            resolution: resolution(width: luna.width, height: luna.height), frameRate: rate)
    }

    /// Every RecordResolution the camera stored in normal video on fw 1.1.15
    /// (docs/research/luna-fw-1.1.15-verification.md). 4:3, 5.3K and 6K were rejected.
    static let videoFormatValues: [UInt64] = [
        210, 211, 154,  // 8K 24/25/30
        219, 212, 213,  // 8K 2.35:1
        49, 48, 24, 258, 92, 23, 220, 214,  // 4K 24…120
        440, 439, 438, 437, 436, 435, 434, 433,  // 4K 2.35:1
        248, 247, 246, 331, 245, 244, 243, 242,  // 2.7K 2688x1520
        53, 52, 29, 260, 81, 40, 150, 28, 26, 27,  // 1080p 24…240
        126, 125, 124,  // 9:16 4K
        455, 454, 453, 452, 451, 450,  // 9:16 3K
        445, 444, 443, 468, 442, 441,  // 9:16 2.7K (443/444 from the fw 1.1.15 official app)
        119, 120, 121, 448, 447, 446,  // 1:1 3K 3072x3072, fw 1.1.15 official app
        85, 71, 64, 298, 82, 68,  // 9:16 1080
    ]

    static func formatTable(values: [UInt64]) -> [VideoFormat: UInt64] {
        var table: [VideoFormat: UInt64] = [:]
        for value in values {
            guard let luna = LunaVideoResolution(rawValue: value), let format = videoFormat(luna)
            else { continue }
            table[format] = table[format] ?? value
        }
        return table
    }

    // MARK: Gimbal

    static func gimbalMode(_ luna: LunaGimbalMode) -> GimbalMode? {
        switch luna {
        case .rollLock: .follow
        case .rollAndTiltLock: .tiltLocked
        case .fpv: .fpv
        // The shell's fourth slot carries FPV-V; the official app offers no lock mode.
        case .fpvVertical: .directionLock
        case .lock, .stabilizedVertical: nil
        }
    }

    /// Official Luna app names for the four modes it offers.
    static let gimbalModeLabels: [GimbalMode: String] = [
        .follow: "Roll Lock", .tiltLocked: "Roll & Tilt", .fpv: "FPV", .directionLock: "FPV-V",
    ]

    static func lunaGimbalMode(_ mode: GimbalMode) -> LunaGimbalMode {
        switch mode {
        case .follow: .rollLock
        case .tiltLocked: .rollAndTiltLock
        case .fpv: .fpv
        case .directionLock: .fpvVertical
        }
    }

    static func gimbalSpeed(_ luna: LunaGimbalFollowSpeed) -> GimbalSpeed {
        switch luna {
        case .slow: .slow
        case .medium: .defaultSpeed
        case .fast, .sensitive: .fast
        }
    }

    static func lunaGimbalSpeed(_ speed: GimbalSpeed) -> LunaGimbalFollowSpeed {
        switch speed {
        case .slow: .slow
        case .defaultSpeed: .medium
        case .fast: .fast
        }
    }

    // MARK: Focus

    /// The official app's three AF modes (it lists AF-C first; the shell keeps AF-S first).
    static let focusOptions: [FocusOption] = [.single, .continuousDefault, .productShowcase]

    static func focusOption(_ luna: LunaAFMode) -> FocusOption {
        switch luna {
        case .single: .single
        case .continuous: .continuousDefault
        case .productShowcase: .productShowcase
        }
    }

    static func lunaAFMode(_ option: FocusOption) -> LunaAFMode? {
        switch option {
        case .single: .single
        case .continuousDefault: .continuous
        case .productShowcase: .productShowcase
        case .subjectLock, .registeredPriority: nil
        }
    }

    // MARK: Status


    static func apply(device: LunaDeviceStatus, to status: inout CameraStatus) {
        if let battery = device.battery {
            status.batteryPercent = Int(battery.percent)
            status.charging = battery.isCharging
        }
        let storages = device.storageList.isEmpty ? device.storage.map { [$0] } ?? [] : device.storageList
        if let inner = storages.first(where: { $0.location == 2 }) ?? storages.first {
            status.internalTotalMb = Int(inner.totalBytes / 1_000_000)
            status.internalFreeMb = Int(inner.freeBytes / 1_000_000)
        }
        if let sd = storages.first(where: { $0.location == 3 }), sd.isUsable {
            status.sdTotalMb = Int(sd.totalBytes / 1_000_000)
            status.sdFreeMb = Int(sd.freeBytes / 1_000_000)
        }
        guard !storages.isEmpty else { return }
        let usable = storages.filter(\.isUsable)
        status.storageTotalMb = Int(usable.reduce(0) { $0 + $1.totalBytes } / 1_000_000)
        status.storageFreeMb = Int(usable.reduce(0) { $0 + $1.freeBytes } / 1_000_000)
    }

    static func apply(
        settings: LunaPhotographySettings, to status: inout CameraStatus,
        pins: inout LunaControlPins, table: inout [VideoFormat: UInt64]
    ) {
        let now = Date.timeIntervalSinceReferenceDate
        let exposure =
            status.isPhoto
            ? settings.stillExposure ?? settings.videoExposure
            : settings.videoExposure ?? settings.stillExposure
        // Live readouts only (Auto may report what it chose; AE Lock reads them). The ISO,
        // shutter and WB settings and the exposure mode come from the Core session.
        if let exposure {
            status.iso = exposure.iso > 0 ? Int(exposure.iso) : -1
            status.shutterDenom =
                exposure.shutterSeconds > 0 ? Int((1 / exposure.shutterSeconds).rounded()) : -1
        }
        if let stops = settings.exposureBiasStops {
            let ev = EvComp(thirds: Int((stops * 3).rounded()))
            status.evComp = CameraValuePin.reconcile(&pins.ev, reported: ev, now: now) ?? ev
        }
        if let luna = settings.color {
            let color = colorMode(luna)
            status.colorMode = CameraValuePin.reconcile(&pins.color, reported: color, now: now) ?? color
        }
        status.availableColorModes = colorModes
        if table.isEmpty { table = formatTable(values: videoFormatValues) }
        // Photo mode reports a still size (unknown 0xDF here); keep the last video format.
        if let raw = settings.recordResolution, let luna = LunaVideoResolution(rawValue: raw),
            let format = videoFormat(luna), format.resolution != unknownResolution
        {
            if table[format] == nil { table[format] = raw }
            let shown = CameraValuePin.reconcile(&pins.format, reported: format, now: now) ?? format
            status.videoFormat = shown
            status.videoResolution = shown.resolution
            status.fps = shown.frameRate.fps
        }
        status.availableVideoFormats = table.keys.sorted {
            ($0.resolution.rawValue, $0.frameRate.fps) < ($1.resolution.rawValue, $1.frameRate.fps)
        }
        status.availableIsoIndices = isoIndices
        status.availableShutterDenoms = shutterDenoms
        // AF modes the official app never offers (0, 2, 4, 5) leave the readout blank.
        if let af = settings.afMode {
            let reported = LunaAFMode(rawValue: af).map(focusOption)
            let shown = CameraValuePin.reconcile(&pins.focus, reported: reported, now: now) ?? reported
            status.focusMode = shown?.focusMode
            status.focusTrack = shown?.track
        }
    }

    // MARK: Helpers

    static func nearestStop(_ factor: Double, stops: [Double]) -> Double {
        stops.min { abs($0 - factor) < abs($1 - factor) } ?? 1
    }

    /// Time-of-day timecode text (`LunaFrameTimecode.timecode`).
    static func timecode(unixSeconds: Double, timeZoneSeconds: Int, fps: Int) -> String {
        timecodeText(LunaFrameTimecode.timecode(unixSeconds: unixSeconds, timeZoneSeconds: timeZoneSeconds, fps: fps))
    }

    /// `HH:MM:SS:FF`, the status text the HUD reads.
    static func timecodeText(_ timecode: CameraTimecode) -> String {
        String(
            format: "%02d:%02d:%02d:%02d", timecode.hours, timecode.minutes, timecode.seconds,
            timecode.frames)
    }
}

extension LunaPhotographySettings {
    static var empty: LunaPhotographySettings {
        // An empty body decodes to all-unknown settings.
        (try? LunaPhotographySettings(response: Data())) ?? { fatalError("empty settings") }()
    }

    /// Later partial reads overwrite only the fields they carry (proto3 omits defaults).
    mutating func merge(_ other: LunaPhotographySettings) {
        types = Array(Set(types).union(other.types)).sorted()
        functionMode = other.functionMode ?? functionMode
        sharpness = other.sharpness ?? sharpness
        exposureBiasTenths = other.exposureBiasTenths ?? exposureBiasTenths
        whiteBalancePreset = other.whiteBalancePreset ?? whiteBalancePreset
        filter = other.filter ?? filter
        stillExposure = other.stillExposure ?? stillExposure
        videoExposure = other.videoExposure ?? videoExposure
        isoTopLimit = other.isoTopLimit ?? isoTopLimit
        recordResolution = other.recordResolution ?? recordResolution
        fov = other.fov ?? fov
        colorMode = other.colorMode ?? colorMode
        whiteBalanceKelvin = other.whiteBalanceKelvin ?? whiteBalanceKelvin
        photoResolution = other.photoResolution ?? photoResolution
        darkEIS = other.darkEIS ?? darkEIS
        flowStateLevel = other.flowStateLevel ?? flowStateLevel
        faceMetering = other.faceMetering ?? faceMetering
        zoom = other.zoom ?? zoom
        iLog = other.iLog ?? iLog
        colorRecovery = other.colorRecovery ?? colorRecovery
        gimbal = other.gimbal ?? gimbal
        gimbalStatus = other.gimbalStatus ?? gimbalStatus
        afMode = other.afMode ?? afMode
        gimbalPanoType = other.gimbalPanoType ?? gimbalPanoType
        iq3AMode = other.iq3AMode ?? iq3AMode
        filterStrength = other.filterStrength ?? filterStrength
    }
}

/// The shared FOCUS drum and chip list only the modes Luna offers.
extension CaptureLists {
    static var focusOptions: [FocusOption] { LunaShellMapping.focusOptions }
}

extension OperatorPrefs {
    /// Operator says Color Recovery is off on the camera, so the I-Log preview is flat.
    static var lunaFlatPreview: Bool {
        // fw 1.1.15: the I-Log phone preview measures flat (log black ~Y 37), so default on.
        get { UserDefaults.standard.object(forKey: "OpenInstaCine.luna.flatPreview") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "OpenInstaCine.luna.flatPreview") }
    }
}

extension TrackingBox {
    /// The Luna owner's box is the same top-left preview fraction box.
    init(_ box: LunaSubjectTracking.Box) {
        self.init(x: box.x, y: box.y, width: box.width, height: box.height)
    }
}
