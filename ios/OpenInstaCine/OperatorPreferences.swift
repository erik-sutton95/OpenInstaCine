import Foundation
import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenPocketViewCore
import SwiftUI

enum OperatorPrefs {
    private static let common = MonitorOperatorPreferences(
        storage: .standard,
        keys: .init(
            keepScreenAwake: "OpenInstaCine.KeepScreenAwake",
            hdrDisplay: "OpenInstaCine.HDRDisplay",
            recordConfirmation: "OpenInstaCine.RecordConfirmation",
            haptics: "OpenInstaCine.HapticsEnabled",
            cacheOriginals: "OpenInstaCine.CacheFullResolution"))
    private static let lutKey = "OpenInstaCine.LastLUT"
    private static let customLUTKey = "OpenInstaCine.LastCustomLUT"
    private static let lutWasCustomKey = "OpenInstaCine.LastLUTWasCustom"
    private static let lutSelectionKey = "OpenInstaCine.LUTSelection"
    private static let customRec709FileKey = "OpenInstaCine.CustomRec709File"
    private static let customDLogFileKey = "OpenInstaCine.CustomDLogFile"
    private static let customDLog2FileKey = "OpenInstaCine.CustomDLog2File"
    private static let selectedCustomFileKey = "OpenInstaCine.SelectedCustomLUTFile"
    private static let assistKey = "OpenInstaCine.Assist.v1"
    private static let headTrackingKey = "OpenInstaCine.HeadTrackingEnabled"
    private static let gimbalStickSensitivityKey = "OpenInstaCine.GimbalStickSensitivity"
    private static let virtualJoystickInvertPanKey = "OpenInstaCine.VirtualJoystickInvertPan"
    private static let virtualJoystickInvertTiltKey = "OpenInstaCine.VirtualJoystickInvertTilt"
    private static let virtualJoystickDeadzonePercentKey =
        "OpenInstaCine.VirtualJoystickDeadzonePercent"
    private static let virtualJoystickResponseCurveKey =
        "OpenInstaCine.VirtualJoystickResponseCurve"
    private static let virtualJoystickSizeKey = "OpenInstaCine.VirtualJoystickSize"
    private static let gimbalRampKey = "OpenInstaCine.GimbalRamp"
    private static let gimbalDoubleTapKey = "OpenInstaCine.GimbalDoubleTap"
    private static let dispLiveKey = "OpenInstaCine.DispChrome.Live"
    private static let dispCleanKey = "OpenInstaCine.DispChrome.Clean"
    private static let cleanPinsKey = "OpenInstaCine.CleanViewPins.v1"
    private static let playbackAssistsKey = "OpenInstaCine.PlaybackAssists.v1"
    private static let lastMonitorColorModeKey = "OpenInstaCine.LastMonitorColorMode"
    private static let portraitFeedAspectKey = "OpenInstaCine.PortraitFeedAspect"
    private static let nativeISOHopKey = "OpenInstaCine.NativeISOHop"
    private static let facePriorityExposureKey = "OpenInstaCine.FacePriorityExposure"
    private static let shutterUsesAngleKey = "OpenInstaCine.ShutterUsesAngle"
    private static let shutterAngleKey = "OpenInstaCine.ShutterAngleDegrees"
    private static let shareThisFeedKey = "OpenInstaCine.ShareThisFeed"
    private static let controlRequestsKey = "OpenInstaCine.ControlRequests"
    private static let broadcastPriorityKey = "OpenInstaCine.BroadcastPriority"
    private static let assistToolUsageKey = "OpenInstaCine.AssistToolUsage.v1"

    static var shareThisFeed: Bool {
        get { UserDefaults.standard.bool(forKey: shareThisFeedKey) }
        set { UserDefaults.standard.set(newValue, forKey: shareThisFeedKey) }
    }

    static var controlRequests: Bool {
        get {
            if UserDefaults.standard.object(forKey: controlRequestsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: controlRequestsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: controlRequestsKey) }
    }

    /// Ceiling index on the watcher-relay bitrate ladder. 0 = highest quality.
    static var broadcastPriority: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: broadcastPriorityKey)
            return min(max(0, v), 3)
        }
        set { UserDefaults.standard.set(min(max(0, newValue), 3), forKey: broadcastPriorityKey) }
    }

    static var keepScreenAwake: Bool {
        get { common.keepScreenAwake }
        set { common.keepScreenAwake = newValue }
    }

    /// Outdoor HDR panel boost for live view. Off by default.
    static var hdrDisplay: Bool {
        get { common.hdrDisplay }
        set { common.hdrDisplay = newValue }
    }

    /// Download the original camera file when a clip is opened. Off keeps the 720p proxy.
    static var cacheFullResolution: Bool {
        get { common.cacheOriginals }
        set { common.cacheOriginals = newValue }
    }

    static var recordConfirmationEnabled: Bool {
        get { common.recordConfirmation }
        set { common.recordConfirmation = newValue }
    }

    static var hapticsEnabled: Bool {
        get { common.haptics }
        set { common.haptics = newValue }
    }

    static var assistToolUsage: MonitorToolUsage {
        get {
            guard let data = UserDefaults.standard.data(forKey: assistToolUsageKey),
                let value = try? JSONDecoder().decode(MonitorToolUsage.self, from: data)
            else { return MonitorToolUsage() }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: assistToolUsageKey)
            }
        }
    }

    static var headTrackingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: headTrackingKey) }
        set { UserDefaults.standard.set(newValue, forKey: headTrackingKey) }
    }

    /// Stick double-tap / gamepad Circle/B. Absent key is Recenter.
    static var gimbalDoubleTap: GimbalDoubleTap {
        get {
            GimbalDoubleTap(rawValue: UserDefaults.standard.integer(forKey: gimbalDoubleTapKey))
                ?? .recenter
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: gimbalDoubleTapKey) }
    }

    static var gimbalRamp: GimbalRamp {
        get {
            guard UserDefaults.standard.object(forKey: gimbalRampKey) != nil else {
                return .off
            }
            return GimbalRamp(rawValue: UserDefaults.standard.integer(forKey: gimbalRampKey))
                ?? .off
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: gimbalRampKey) }
    }

    static var gimbalStickSensitivity: Int {
        get {
            guard UserDefaults.standard.object(forKey: gimbalStickSensitivityKey) != nil else {
                return GimbalStick.defaultSensitivity
            }
            return GimbalStick.clampedSensitivity(
                UserDefaults.standard.integer(forKey: gimbalStickSensitivityKey))
        }
        set {
            UserDefaults.standard.set(
                GimbalStick.clampedSensitivity(newValue), forKey: gimbalStickSensitivityKey)
        }
    }

    static var virtualJoystickInvertPan: Bool {
        get { UserDefaults.standard.bool(forKey: virtualJoystickInvertPanKey) }
        set { UserDefaults.standard.set(newValue, forKey: virtualJoystickInvertPanKey) }
    }

    static var virtualJoystickInvertTilt: Bool {
        get { UserDefaults.standard.bool(forKey: virtualJoystickInvertTiltKey) }
        set { UserDefaults.standard.set(newValue, forKey: virtualJoystickInvertTiltKey) }
    }

    static var virtualJoystickDeadzonePercent: Int {
        get {
            guard UserDefaults.standard.object(forKey: virtualJoystickDeadzonePercentKey) != nil
            else {
                return GimbalStick.defaultDeadzonePercent
            }
            return GimbalStick.clampedDeadzonePercent(
                UserDefaults.standard.integer(forKey: virtualJoystickDeadzonePercentKey))
        }
        set {
            UserDefaults.standard.set(
                GimbalStick.clampedDeadzonePercent(newValue),
                forKey: virtualJoystickDeadzonePercentKey)
        }
    }

    static var virtualJoystickResponseCurve: GimbalStick.ResponseCurve {
        get {
            GimbalStick.ResponseCurve.parse(
                UserDefaults.standard.string(forKey: virtualJoystickResponseCurveKey))
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: virtualJoystickResponseCurveKey)
        }
    }

    static var virtualJoystickSize: MonitorJoystickSize {
        get { MonitorJoystickSize.parse(UserDefaults.standard.string(forKey: virtualJoystickSizeKey)) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: virtualJoystickSizeKey) }
    }

    static var virtualJoystickMapping: GimbalStick.Mapping {
        GimbalStick.Mapping(
            invertPan: virtualJoystickInvertPan,
            invertTilt: virtualJoystickInvertTilt,
            deadzone: GimbalStick.deadzoneFromPercent(virtualJoystickDeadzonePercent),
            curve: virtualJoystickResponseCurve)
    }

    static var dispLive: PocketDispChrome {
        get { loadChrome(key: dispLiveKey) ?? .liveDefaults }
        set { saveChrome(newValue, key: dispLiveKey) }
    }

    static var dispClean: PocketDispChrome {
        get { loadChrome(key: dispCleanKey) ?? .cleanDefaults }
        set { saveChrome(newValue, key: dispCleanKey) }
    }

    static var shutterUsesAngle: Bool {
        get { UserDefaults.standard.bool(forKey: shutterUsesAngleKey) }
        set { UserDefaults.standard.set(newValue, forKey: shutterUsesAngleKey) }
    }

    static var shutterAngleDegrees: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: shutterAngleKey)
            return stored > 0 ? ShutterAngle.nearestDegrees(stored) : ShutterAngle.defaultDegrees
        }
        set {
            UserDefaults.standard.set(
                ShutterAngle.nearestDegrees(newValue), forKey: shutterAngleKey)
        }
    }

    static var portraitFeedAspect: PortraitFeedAspect {
        get {
            PortraitFeedAspect(
                rawValue: UserDefaults.standard.string(forKey: portraitFeedAspectKey) ?? "")
                ?? .fit16x9
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: portraitFeedAspectKey) }
    }

    /// Auto-expo: meter Vision faces to middle gray and write EV.
    static var facePriorityExposureEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: facePriorityExposureKey) }
        set { UserDefaults.standard.set(newValue, forKey: facePriorityExposureKey) }
    }

    /// D-Log 400 ↔ D-Log2 1600 when the operator is still on native ISO.
    static var nativeISOHopEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: nativeISOHopKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: nativeISOHopKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: nativeISOHopKey) }
    }

    /// Last live `ColorMode` so Auto LUT can bind a cube from the offline library.
    static var lastMonitorColorMode: ColorMode? {
        get {
            guard UserDefaults.standard.object(forKey: lastMonitorColorModeKey) != nil else {
                return nil
            }
            return ColorMode(
                rawValue: UInt8(
                    truncatingIfNeeded: UserDefaults.standard.integer(
                        forKey: lastMonitorColorModeKey)))
        }
        set {
            if let newValue {
                UserDefaults.standard.set(Int(newValue.rawValue), forKey: lastMonitorColorModeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastMonitorColorModeKey)
            }
        }
    }

    static var playbackVisibleAssistTools: Set<LiveAssistTool> {
        get {
            guard let raw = UserDefaults.standard.array(forKey: playbackAssistsKey) as? [String]
            else { return [] }
            return Set(raw.compactMap(LiveAssistTool.init(rawValue:)))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: playbackAssistsKey)
        }
    }

    /// Absent key = never pinned, so the stock set. Stored empty = operator cleared every pin.
    static var cleanViewPinnedTools: Set<LiveAssistTool> {
        get {
            guard let raw = UserDefaults.standard.array(forKey: cleanPinsKey) as? [String] else {
                return LiveAssistState.cleanViewDefaultPinnedTools
            }
            let allowed = Set(LiveAssistTool.cleanPinCases)
            return Set(raw.compactMap(LiveAssistTool.init(rawValue:))).intersection(allowed)
        }
        set {
            let ordered = LiveAssistTool.cleanPinCases.filter { newValue.contains($0) }.map(
                \.rawValue)
            UserDefaults.standard.set(ordered, forKey: cleanPinsKey)
        }
    }

    private static func loadChrome(key: String) -> PocketDispChrome? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PocketDispChrome.self, from: data)
    }

    private static func saveChrome(_ value: PocketDispChrome, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static var lastLUT: String {
        get {
            if lastLUTWasCustom, let file = lastCustomFileName {
                return CustomLUTIndex.displayName(fileName: file)
            }
            return lastBuiltInLUT
        }
        set { UserDefaults.standard.set(newValue, forKey: lutKey) }
    }

    static var lastBuiltInLUT: String {
        UserDefaults.standard.string(forKey: lutKey) ?? LUTSelection.auto.title
    }

    static var lastCustomFileName: String? {
        get { UserDefaults.standard.string(forKey: customLUTKey) }
        set { UserDefaults.standard.set(newValue, forKey: customLUTKey) }
    }

    static var lastLUTWasCustom: Bool {
        get { UserDefaults.standard.bool(forKey: lutWasCustomKey) }
        set { UserDefaults.standard.set(newValue, forKey: lutWasCustomKey) }
    }

    static var lutSelection: LUTSelection {
        get {
            if let raw = UserDefaults.standard.string(forKey: lutSelectionKey),
                let value = LUTSelection(rawValue: raw)
            {
                return value
            }
            return .djiAuto
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: lutSelectionKey) }
    }

    static func customFileName(for slot: CustomLUTSlot) -> String? {
        UserDefaults.standard.string(forKey: customFileKey(slot))
    }

    static func setCustomFileName(_ fileName: String?, for slot: CustomLUTSlot) {
        UserDefaults.standard.set(fileName, forKey: customFileKey(slot))
    }

    static var selectedCustomFileName: String? {
        get {
            let name = UserDefaults.standard.string(forKey: selectedCustomFileKey)
            guard let name, CustomLUTIndex.isSafeFileName(name) else { return nil }
            return name
        }
        set { UserDefaults.standard.set(newValue, forKey: selectedCustomFileKey) }
    }

    private static func customFileKey(_ slot: CustomLUTSlot) -> String {
        switch slot {
        case .rec709: customRec709FileKey
        case .dLog: customDLogFileKey
        case .dLog2: customDLog2FileKey
        }
    }

    static func load(into state: LiveAssistState) {
        if let data = UserDefaults.standard.data(forKey: assistKey),
            let snap = try? JSONDecoder().decode(Snapshot.self, from: data)
        {
            snap.apply(to: state)
        }
        migrateLegacyLUTIfNeeded(into: state)
        var migrated = lutSelection.migratedToDJICatalog
        // This app bundles no DJI cubes: a stale locked DJI pick falls back to Auto.
        if migrated.isDJI, !LUTSelection.djiCatalog(isPhotoLive: false).contains(migrated) {
            migrated = .djiAuto
        }
        if migrated != lutSelection { lutSelection = migrated }
        state.lutSelection = migrated
    }

    /// One-shot: old Built-in looks become Auto; a stored custom file becomes Custom D-Log.
    private static func migrateLegacyLUTIfNeeded(into state: LiveAssistState) {
        guard UserDefaults.standard.object(forKey: lutSelectionKey) == nil else { return }
        if lastLUTWasCustom, let file = lastCustomFileName,
            CustomLUTIndex.isSafeFileName(file)
        {
            setCustomFileName(file, for: .dLog)
            if state.lutEnabled {
                UserDefaults.standard.set(LUTSelection.customDLog.rawValue, forKey: lutSelectionKey)
                return
            }
        }
        UserDefaults.standard.set(LUTSelection.djiAuto.rawValue, forKey: lutSelectionKey)
    }

    static func save(_ state: LiveAssistState) {
        write(encoded(state))
    }

    static func encoded(_ state: LiveAssistState) -> Data? {
        try? JSONEncoder().encode(Snapshot(state))
    }

    static func write(_ data: Data?) {
        guard let data else { return }
        UserDefaults.standard.set(data, forKey: assistKey)
    }

    /// OpenZCine `operatorPreferences.v1` / `assistConfiguration.v1` analogue — one blob.
    struct Snapshot: Codable {
        var tools: [String]
        var guideAspect: String
        var guideFamily: String
        var selectedGuides: [String]
        var guideMask: Bool
        var gridThirds: Bool
        var gridPhi: Bool
        var gridDiagonal: Bool
        var peakingColor: String
        var peakingSensitivity: String
        var falseColorScale: String
        var falseColorReference: Bool
        /// Optional so settings saved before the LOG / 709 choice still decode.
        var falseColorRec709: Bool?
        var zebraHighlight: Bool
        var zebraMidtone: Bool
        var zebraHighlightIRE: Double
        var zebraMidtoneIRE: Double
        var zebraHighlightColor: String
        var zebraMidtoneColor: String
        var desqueezeFactor: Double
        var desqueezeCustom: Bool?
        var desqueezeCustomFactor: Double?
        var desqueezeHorizontal: Bool
        var splitComparison: Bool
        var splitVertical: Bool
        var lutArmed: Bool
        var lutExposureStops: Double?
        var crushClipCompensation: Int?
        var mirrorHorizontal: Bool?
        var mirrorVertical: Bool?

        init(_ s: LiveAssistState) {
            tools = LiveAssistTool.allCases.filter { s.isOn($0) }.map(\.rawValue)
            guideAspect = s.guideAspect.rawValue
            guideFamily = s.guideFamily.rawValue
            selectedGuides = s.selectedGuides.map(\.rawValue)
            guideMask = s.guideMask
            gridThirds = s.gridThirds
            gridPhi = s.gridPhi
            gridDiagonal = s.gridDiagonal
            peakingColor = s.peakingColor.rawValue
            peakingSensitivity = s.peakingSensitivity.rawValue
            falseColorScale = s.falseColorScale.rawValue
            falseColorReference = s.falseColorReference
            falseColorRec709 = s.falseColorRec709
            zebraHighlight = s.zebraHighlight
            zebraMidtone = s.zebraMidtone
            zebraHighlightIRE = s.zebraHighlightIRE
            zebraMidtoneIRE = s.zebraMidtoneIRE
            zebraHighlightColor = s.zebraHighlightColor.rawValue
            zebraMidtoneColor = s.zebraMidtoneColor.rawValue
            desqueezeCustom = s.desqueezeCustom
            desqueezeCustomFactor = s.desqueezeCustomFactor
            desqueezeFactor = s.desqueezeFactor
            desqueezeHorizontal = s.desqueezeHorizontal
            splitComparison = s.splitComparison
            splitVertical = s.splitVertical
            lutArmed = s.lutEnabled
            lutExposureStops = s.lutExposureStops
            crushClipCompensation = s.crushClipCompensation.rawValue
            mirrorHorizontal = s.mirrorHorizontal
            mirrorVertical = s.mirrorVertical
        }

        func apply(to s: LiveAssistState) {
            let on = Set(tools)
            s.peaking = on.contains(LiveAssistTool.peaking.rawValue)
            s.zebra = on.contains(LiveAssistTool.zebra.rawValue)
            s.falseColor = on.contains(LiveAssistTool.falseColor.rawValue)
            s.histogram = on.contains(LiveAssistTool.histogram.rawValue)
            s.waveform = on.contains(LiveAssistTool.waveform.rawValue)
            s.parade = on.contains(LiveAssistTool.parade.rawValue)
            s.vectorscope = on.contains(LiveAssistTool.vectorscope.rawValue)
            s.trafficLights = on.contains(LiveAssistTool.trafficLights.rawValue)
            s.ndMeter = on.contains(LiveAssistTool.ndMeter.rawValue)
            s.evMeter = on.contains(LiveAssistTool.evMeter.rawValue)
            s.audioMeters = on.contains(LiveAssistTool.audioMeters.rawValue)
            s.guides = on.contains(LiveAssistTool.guides.rawValue)
            s.grid = on.contains(LiveAssistTool.grid.rawValue)
            s.crosshair = on.contains(LiveAssistTool.crosshair.rawValue)
            s.level = on.contains(LiveAssistTool.level.rawValue)
            s.desqueeze = on.contains(LiveAssistTool.desqueeze.rawValue)
            s.mirror = on.contains(LiveAssistTool.mirror.rawValue)
            s.instantReview = on.contains(LiveAssistTool.instantReview.rawValue)
            s.guideAspect = GuideAspect(rawValue: guideAspect) ?? .cinema
            s.guideFamily = GuideFamily(rawValue: guideFamily) ?? .film
            let restored = Set(selectedGuides.compactMap(GuideAspect.init(rawValue:)))
            s.selectedGuides = restored.isEmpty ? [s.guideAspect] : restored
            s.guideMask = guideMask
            s.gridThirds = gridThirds
            s.gridPhi = gridPhi
            s.gridDiagonal = gridDiagonal
            s.peakingColor = PeakingPaint(rawValue: peakingColor) ?? .red
            s.peakingSensitivity = PeakingSense(rawValue: peakingSensitivity) ?? .medium
            s.falseColorScale = FalseColorScaleKind(rawValue: falseColorScale) ?? .sceneStops
            s.falseColorReference = falseColorReference
            s.falseColorRec709 = falseColorRec709 ?? false
            s.zebraHighlight = zebraHighlight
            s.zebraMidtone = zebraMidtone
            s.zebraHighlightIRE = zebraHighlightIRE
            s.zebraMidtoneIRE = zebraMidtoneIRE
            s.zebraHighlightColor = ZebraPaint(rawValue: zebraHighlightColor) ?? .white
            s.zebraMidtoneColor = ZebraPaint(rawValue: zebraMidtoneColor) ?? .amber
            s.desqueezeFactor = DesqueezeAssist.snap(desqueezeFactor)
            s.desqueezeCustom =
                desqueezeCustom ?? (DesqueezeRatio.matching(s.desqueezeFactor) == nil)
            s.desqueezeCustomFactor = DesqueezeAssist.snap(desqueezeCustomFactor ?? desqueezeFactor)
            s.desqueezeHorizontal = desqueezeHorizontal
            s.splitComparison = splitComparison
            s.splitVertical = splitVertical
            if let stops = lutExposureStops {
                s.lutExposureStops = LUTExposureCompensation.snap(stops)
            }
            if let raw = crushClipCompensation,
                let value = TrafficLightsAssist.CrushClipCompensation(rawValue: raw)
            {
                s.crushClipCompensation = value
            }
            s.lutEnabled = lutArmed
            s.mirrorHorizontal = mirrorHorizontal ?? true
            s.mirrorVertical = mirrorVertical ?? false
        }
    }
}
