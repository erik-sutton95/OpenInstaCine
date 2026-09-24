import Foundation
import Insta360Protocol
import OpenPocketViewCore

/// Optimistic values the operator just asked for, held until the camera reports
/// them or the settle window runs out (same `CameraValuePin` rule as the Osmo shell).
struct LunaControlPins {
    var isoIndex: CameraValuePin<IsoIndex>?
    var shutterDenom: CameraValuePin<Int>?
    var expoMode: CameraValuePin<ExpoMode>?
    var ev: CameraValuePin<EvComp>?
    var whiteBalance: CameraValuePin<WhiteBalance>?
    var color: CameraValuePin<ColorMode>?
    var format: CameraValuePin<VideoFormat>?
    var shootingMode: CameraValuePin<Int>?
    var recording: CameraValuePin<Bool>?
    var gimbalMode: CameraValuePin<GimbalMode>?
    var gimbalSpeed: CameraValuePin<GimbalSpeed>?
    var photoInFlight = false
}

/// Luna ↔ shared monitor vocabulary. Wire numbers stay in `Insta360Protocol`;
/// everything the shared screens read goes through here.
enum LunaShellMapping {
    static let cameraModel = CameraModel(name: "Luna Ultra", datalinkPort: 0, tcpPoke: false, verified: true)
    /// Observed preview: 1280×720 HEVC at 25 fps.
    static let previewFPS: Double = 25
    /// fw 1.0.288 zoomed to 6×; the fw 1.1.15 notes promise 15×.
    static let defaultZoomCeiling: Double = 6
    static let zoomChips: [Double] = [1, 2, 3, 6]

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
    static let isoValues = [100, 160, 200, 400, 800, 1600, 3200, 6400]
    static let isoIndices: [IsoIndex] = [.auto] + isoValues.compactMap(isoIndex)

    static func isoIndex(_ iso: Int) -> IsoIndex? {
        IsoIndex.allCases.first { $0.isoValue == iso }
    }

    /// Official Video wheel, slowest last. fw 1.1.15 adds 1/15…1/5.
    static let shutterDenoms = [
        8000, 6400, 5000, 4000, 3200, 2500, 2000, 1600, 1250, 1000, 800, 640, 500, 400, 320, 250,
        200, 160, 125, 100, 80, 60, 50, 40, 30, 25, 15, 10, 5,
    ]

    // MARK: Format

    /// Shared `VideoResolution` for a Luna frame size. DJI bytes where the shape
    /// matches, Luna bytes (0xD0…) otherwise; labels come from the core table.
    static func resolution(width: Int, height: Int) -> VideoResolution {
        let long = max(width, height)
        let portrait = height > width
        switch (long, portrait) {
        case (1920, false): return .p1080
        case (1920, true): return .p1080_9x16
        case (2688...2720, false): return .p2_7K
        case (2688...2720, true): return .p2_7K_9x16
        case (2880...3072, true): return .p3K_9x16
        case (2880...3072, false): return .luna3K
        case (3840, false): return .p4K
        case (3840, true): return .luna4K_9x16
        case (5120...5760, false): return .luna6K
        case (7680, false): return .luna8K
        default: return VideoResolution(rawValue: 0xDF)
        }
    }

    static func videoFormat(_ luna: LunaVideoResolution) -> VideoFormat? {
        guard let rate = VideoFrameRate.fromFps(Int(luna.framesPerSecond.rounded())) else { return nil }
        return VideoFormat(
            resolution: resolution(width: luna.width, height: luna.height), frameRate: rate)
    }

    /// Observed/accepted RecordResolution values for normal video on this body.
    /// Updated from the fw 1.1.15 hardware verification (see docs/research).
    static let videoFormatValues: [UInt64] = [52, 48, 24, 454, 211, 14, 31, 43, 214]

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
        case .fpv, .fpvVertical: .fpv
        case .lock: .directionLock
        case .stabilizedVertical: nil
        }
    }

    static func lunaGimbalMode(_ mode: GimbalMode) -> LunaGimbalMode {
        switch mode {
        case .follow: .rollLock
        case .tiltLocked: .rollAndTiltLock
        case .fpv: .fpv
        case .directionLock: .lock
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
        let usable = storages.filter(\.isUsable)
        status.storageTotalMb = Int(usable.reduce(0) { $0 + $1.totalBytes } / 1_000_000)
        status.storageFreeMb = Int(usable.reduce(0) { $0 + $1.freeBytes } / 1_000_000)
    }

    static func apply(
        settings: LunaPhotographySettings, to status: inout CameraStatus,
        pins: inout LunaControlPins, table: inout [VideoFormat: UInt64]
    ) {
        let now = Date.timeIntervalSinceReferenceDate
        if let exposure = settings.videoExposure ?? settings.stillExposure {
            let mode: ExpoMode = exposure.program == 0 ? .auto : .manual
            status.expoMode = CameraValuePin.reconcile(&pins.expoMode, reported: mode, now: now) ?? mode
            let reportedISO: IsoIndex? = exposure.iso == 0 ? .auto : isoIndex(Int(exposure.iso))
            if let held = CameraValuePin.reconcile(&pins.isoIndex, reported: reportedISO, now: now) {
                status.isoIndex = held
            } else {
                status.isoIndex = reportedISO
            }
            status.iso = status.isoIndex?.isoValue ?? (exposure.iso > 0 ? Int(exposure.iso) : -1)
            let denom = exposure.shutterSeconds > 0 ? Int((1 / exposure.shutterSeconds).rounded()) : -1
            status.shutterDenom =
                CameraValuePin.reconcile(&pins.shutterDenom, reported: denom, now: now) ?? denom
        }
        if let stops = settings.exposureBiasStops {
            let ev = EvComp(thirds: Int((stops * 3).rounded()))
            status.evComp = CameraValuePin.reconcile(&pins.ev, reported: ev, now: now) ?? ev
        }
        if let kelvin = settings.whiteBalanceKelvin {
            let tint = status.whiteBalanceTint ?? 0
            let wb: WhiteBalance = kelvin == 0 ? .auto(tint: tint) : .custom(kelvin: Int(kelvin), tint: tint)
            if kelvin > 0 { status.whiteBalanceKelvin = Int(kelvin) }
            status.whiteBalance =
                CameraValuePin.reconcile(&pins.whiteBalance, reported: wb, now: now) ?? wb
            status.whiteBalanceTint = status.whiteBalance?.tint ?? tint
        }
        if let luna = settings.color {
            let color = colorMode(luna)
            status.colorMode = CameraValuePin.reconcile(&pins.color, reported: color, now: now) ?? color
        }
        status.availableColorModes = colorModes
        if table.isEmpty { table = formatTable(values: videoFormatValues) }
        if let raw = settings.recordResolution, let luna = LunaVideoResolution(rawValue: raw),
            let format = videoFormat(luna)
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
        if let af = settings.afMode {
            status.focusMode = af == 1 ? .single : .continuous
        } else if status.focusMode == nil {
            status.focusMode = .continuous
        }
    }

    // MARK: Helpers

    static func nearestStop(_ factor: Double, stops: [Double]) -> Double {
        stops.min { abs($0 - factor) < abs($1 - factor) } ?? 1
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%02d:%02d:%02d:00", seconds / 3600, (seconds / 60) % 60, seconds % 60)
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

extension OperatorPrefs {
    /// Operator says Color Recovery is off on the camera, so the I-Log preview is flat.
    static var lunaFlatPreview: Bool {
        get { UserDefaults.standard.bool(forKey: "OpenInstaCine.luna.flatPreview") }
        set { UserDefaults.standard.set(newValue, forKey: "OpenInstaCine.luna.flatPreview") }
    }
}

/// How the pairing list names a Luna: the official app shows "Luna Ultra XBQFN7".
enum LunaCameraNames {
    static func title(advertised: String) -> String {
        let trimmed = advertised.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Luna Ultra" }
        if trimmed.lowercased().contains("luna") { return trimmed }
        return "Luna Ultra \(trimmed)"
    }
}
