import Foundation

// Shared gimbal trajectory math (waypoints, A·B·C programs, the smoothed curve, head-look math,
// bounded head tracking) and the typed motion seam live in OpenCineCore's OpenCineMotion.
// Re-exported so app and facade call sites keep importing only this module.
@_exported import OpenCineMotion

extension HeadTrack {
    /// The shell's head-track and waypoint reach, inherited from the Pocket shell (display
    /// `0x04/0x05` degrees). Pan 0 is front; the positive arc passes selfie to raw −135°
    /// (= +225°). The other endpoint is −48°; the intervening negative arc is unreachable.
    /// Luna's own reach (`LunaCameraSession.motion` in Insta360Apple) contains it, so shared
    /// motion bound to it never commands Luna outside what Luna declares.
    public enum Reach {
        public static let panMinDeg = -48.0
        public static let panMaxDeg = 225.0
        public static let tiltMinDeg = -44.0
        public static let tiltMaxDeg = 70.0

        public static let bounds = MotionBounds(
            pan: panMinDeg...panMaxDeg, tilt: tiltMinDeg...tiltMaxDeg)

        /// Unbounded SET-relative look → nearest reachable yaw/pitch.
        public static func project(
            lookRight: Double, lookUp: Double, yaw0: Double, pitch0: Double
        ) -> (yaw: Double, pitch: Double) {
            bounds.project(lookRight: lookRight, lookUp: lookUp, yaw0: yaw0, pitch0: pitch0)
        }
    }
}

// Call sites from before the move, bound to the shell reach.
extension GimbalWaypoint {
    public static func unwrapYaw(_ rawDeg: Double) -> Double {
        unwrapYaw(rawDeg, in: HeadTrack.Reach.bounds)
    }
}

extension HeadTrackNative {
    public init() { self.init(bounds: HeadTrack.Reach.bounds) }
}

extension GimbalWaypointOverlay {
    /// The field of view the app's overlay has always used (Pocket 3, 2·atan(18/20) = 84°).
    public static let wideHFovDeg = 84.0

    public static func project(
        waypoint: GimbalWaypoint, slot: GimbalWaypointSlot, live: GimbalWaypoint, aspect: Double
    ) -> Mark {
        project(waypoint: waypoint, slot: slot, live: live, aspect: aspect, wideHFovDeg: wideHFovDeg)
    }

    public static func marks(program: GimbalProgram, live: GimbalWaypoint, aspect: Double) -> [Mark] {
        marks(program: program, live: live, aspect: aspect, wideHFovDeg: wideHFovDeg)
    }
}
