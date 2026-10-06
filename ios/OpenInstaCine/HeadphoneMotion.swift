import Foundation
import OpenCineAppKitApple
import OpenInstaViewCore

/// The shared head-track bridge driving this app's camera session.
extension AppModel: HeadTrackHost {
    var headTrackCanDrive: Bool {
        if !session.gimbalControlSceneActive || session.isLocked || session.gimbalMoveRunning {
            return false
        }
        if session.isBrowsingMedia { return false }
        if shell.cover != nil { return false }
        if isEditingChrome { return false }
        return isLive && session.hasControlLink
    }
    var isLiveVideoStale: Bool { session.isLiveVideoStale }
    var controlNote: String? {
        get { session.controlNote }
        set { session.controlNote = newValue }
    }
    var freshGimbalWaypoint: GimbalWaypoint? { session.freshGimbalWaypoint }
    var gimbalYawTenthDeg: Int16? { session.gimbalYawTenthDeg }
    var gimbalPitchTenthDeg: Int16? { session.gimbalPitchTenthDeg }
    var gimbalAttitudeHex: String { session.lastGimbalAttitudeHex }
    var gimbalAttitudeDump: String { session.lastGimbalAttitudeDump }
    func beginNativeHeadTrack() -> UInt64? { session.beginNativeHeadTrack() }
    func updateNativeHeadTrack(target: GimbalWaypoint, token: UInt64, measuredAt: TimeInterval?) -> Bool {
        session.updateNativeHeadTrack(target: target, token: token, measuredAt: measuredAt)
    }
    func endNativeHeadTrack(token: UInt64) { session.endNativeHeadTrack(token: token) }
}

extension HeadphoneMotionBridge {
    /// This app's bridge: its name in the permission note, the gimbal reach and stream rate.
    static func appBridge() -> HeadphoneMotionBridge {
        HeadphoneMotionBridge(
            appName: "OpenInstaCine", bounds: HeadTrack.Reach.bounds,
            sampleInterval: GimbalStick.streamInterval, hudInterval: LiveChromeThrottle.statusInterval,
            log: ControlLiveLog.line)
    }
}
