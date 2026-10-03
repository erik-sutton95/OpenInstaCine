import Foundation
import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenPocketViewCore
import SwiftUI

enum OperatorPrefs {
    private static let toolUsage = MonitorToolUsagePreferences(
        storage: .standard, key: "OpenInstaCine.AssistToolUsage.v1")
    private static let display = MonitorDisplayPreferences(
        storage: .standard,
        keys: .init(live: "OpenInstaCine.DispChrome.Live", clean: "OpenInstaCine.DispChrome.Clean"))
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
        get { toolUsage.value }
        set { toolUsage.value = newValue }
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
        get { display.live }
        set { display.live = newValue }
    }

    static var dispClean: PocketDispChrome {
        get { display.clean }
        set { display.clean = newValue }
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

    @MainActor static func load(into state: LiveAssistState) {
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
    @MainActor private static func migrateLegacyLUTIfNeeded(into state: LiveAssistState) {
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

    @MainActor static func encoded(_ state: LiveAssistState) -> Data? {
        state.encodedSnapshot()
    }

    typealias Snapshot = MonitorAssistSnapshot
}
