import Foundation
import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineCameraControls
import OpenInstaViewCore
import SwiftUI

enum OperatorPrefs {
    private static let toolUsage = MonitorToolUsagePreferences(
        storage: .standard, key: "OpenInstaCine.AssistToolUsage.v1")
    static let motion = MonitorMotionPreferences.camera(storage: .standard, prefix: "OpenInstaCine")
    static let sharing = MonitorSharingPreferences.camera(storage: .standard, prefix: "OpenInstaCine")
    static let capture = MonitorCaptureOperatorPreferences(storage: .standard, prefix: "OpenInstaCine")
    static let display = MonitorDisplayPreferences(
        storage: .standard,
        keys: .init(live: "OpenInstaCine.DispChrome.Live", clean: "OpenInstaCine.DispChrome.Clean"))
    static let common = MonitorOperatorPreferences(
        storage: .standard,
        keys: .init(
            keepScreenAwake: "OpenInstaCine.KeepScreenAwake",
            hdrDisplay: "OpenInstaCine.HDRDisplay",
            recordConfirmation: "OpenInstaCine.RecordConfirmation",
            haptics: "OpenInstaCine.HapticsEnabled",
            cacheOriginals: "OpenInstaCine.CacheFullResolution",
            remoteShutter: "OpenInstaCine.RemoteShutter"))
    private static let cleanPinsKey = "OpenInstaCine.CleanViewPins.v1"

    static var shareThisFeed: Bool {
        get { sharing.shareThisFeed }
        set { sharing.shareThisFeed = newValue }
    }

    static var controlRequests: Bool {
        get { sharing.controlRequests }
        set { sharing.controlRequests = newValue }
    }

    /// Ceiling index on the watcher-relay bitrate ladder. 0 = highest quality.
    static var broadcastPriority: Int {
        get { sharing.broadcastPriority }
        set { sharing.broadcastPriority = newValue }
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

    /// Volume and media presses toggle recording while the live view is in front (A2-32); on by default.
    static var remoteShutterEnabled: Bool {
        get { common.remoteShutter }
        set { common.remoteShutter = newValue }
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
        get { motion.headTrackingEnabled }
        set { motion.headTrackingEnabled = newValue }
    }

    /// Stick double-tap / gamepad Circle/B. Absent key is Recenter.
    static var gimbalDoubleTap: GimbalDoubleTap {
        get { motion.doubleTap }
        set { motion.doubleTap = newValue }
    }

    static var gimbalRamp: GimbalRamp {
        get { motion.ramp }
        set { motion.ramp = newValue }
    }

    static var gimbalStickSensitivity: Int {
        get { motion.gimbalStickSensitivity }
        set { motion.gimbalStickSensitivity = newValue }
    }

    static var virtualJoystickInvertPan: Bool {
        get { motion.virtualJoystickInvertPan }
        set { motion.virtualJoystickInvertPan = newValue }
    }

    static var virtualJoystickInvertTilt: Bool {
        get { motion.virtualJoystickInvertTilt }
        set { motion.virtualJoystickInvertTilt = newValue }
    }

    static var virtualJoystickDeadzonePercent: Int {
        get { motion.virtualJoystickDeadzonePercent }
        set { motion.virtualJoystickDeadzonePercent = newValue }
    }

    static var virtualJoystickResponseCurve: GimbalStick.ResponseCurve {
        get { motion.responseCurve }
        set { motion.responseCurve = newValue }
    }

    static var virtualJoystickSize: MonitorJoystickSize {
        get { motion.joystickSize }
        set { motion.joystickSize = newValue }
    }

    static var virtualJoystickMapping: GimbalStick.Mapping { motion.joystickMapping }

    static var dispLive: MonitorDisplayChrome {
        get { display.live }
        set { display.live = newValue }
    }

    static var dispClean: MonitorDisplayChrome {
        get { display.clean }
        set { display.clean = newValue }
    }

    static var shutterUsesAngle: Bool {
        get { capture.shutterUsesAngle }
        set { capture.shutterUsesAngle = newValue }
    }

    static var shutterAngleDegrees: Double {
        get { capture.shutterAngleDegrees }
        set { capture.shutterAngleDegrees = newValue }
    }

    static var portraitFeedAspect: PortraitFeedAspect {
        get { capture.portraitFeedAspect }
        set { capture.portraitFeedAspect = newValue }
    }

    /// Auto-expo: meter Vision faces to middle gray and write EV.
    static var facePriorityExposureEnabled: Bool {
        get { capture.facePriorityExposure }
        set { capture.facePriorityExposure = newValue }
    }

    /// D-Log 400 and D-Log2 1600 when the operator is still on native ISO.
    static var nativeISOHopEnabled: Bool {
        get { capture.nativeISOHop }
        set { capture.nativeISOHop = newValue }
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

    @MainActor static func load(into state: LiveAssistState) {
        LUTPreferences.app.migrateLegacySelectionIfNeeded(lutEnabled: state.lutEnabled)
        var migrated = LUTPreferences.app.lutSelection.migratedToDJICatalog
        // This app bundles no DJI cubes: a stale locked DJI pick falls back to Auto.
        if migrated.isOfficial, !OfficialLUTs.app.catalog(false).contains(migrated) {
            migrated = .officialAuto
        }
        if migrated != LUTPreferences.app.lutSelection {
            LUTPreferences.app.lutSelection = migrated
        }
        state.lutSelection = migrated
    }

    @MainActor static func encoded(_ state: LiveAssistState) -> Data? {
        state.encodedSnapshot()
    }

    typealias Snapshot = MonitorAssistSnapshot
}
