import Foundation
import OpenCineCameraControls
import OpenPocketViewCore

/// The shared gimbal sheet, motion control panel and button, on this app's model and palette.
typealias LiveGimbalButton = OpenCineCameraControls.LiveGimbalButton<AppModel, LiveDesign>
typealias LiveGimbalOverlay = OpenCineCameraControls.LiveGimbalOverlay<AppModel, LiveDesign>
typealias LiveGimbalSheetHost = OpenCineCameraControls.LiveGimbalSheetHost<AppModel>

/// The shared gimbal sheet and motion control panel driving this app's camera session.
extension AppModel: GimbalPanelHost {
    var cameraLabelProfile: CameraLabelProfile { session.profile }
    var assistMirrorsHorizontally: Bool { assist.mirrorsHorizontally }
    var connectedCameraID: UUID? { session.connectedCamera?.id }
    var connectionPhaseLabel: String { session.phase.label }
    var gimbalProgram: GimbalProgram { session.gimbalProgram }
    var overlayGimbalWaypoint: GimbalWaypoint? { session.overlayGimbalWaypoint }
    var waypointOverlayHFovDeg: Double { GimbalWaypointOverlay.wideHFovDeg }
    var gimbalPoseInvertPan: Bool { session.gimbalPoseInvertPan }
    var programmedZoomUnavailableReason: String? { session.programmedZoomUnavailableReason }
    var canSetGimbalConfiguration: Bool { session.canSetGimbalConfiguration }
    var canRunProgrammedMove: Bool { session.canRunProgrammedMove }
    var gimbalMoveRunning: Bool { session.gimbalMoveRunning }
    var gimbalMovePaused: Bool { session.gimbalMovePaused }
    var gimbalMoveCanPause: Bool { session.gimbalMoveCanPause }
    var gimbalStartCountdown: Int? { session.gimbalStartCountdown }
    var gimbalMode: GimbalMode { session.gimbalMode }
    var gimbalSpeed: GimbalSpeed { session.gimbalSpeed }
    func setGimbalSpeed(_ speed: GimbalSpeed) { session.setGimbalSpeed(speed) }
    func setGimbalWaypoint(_ slot: GimbalWaypointSlot) { session.setGimbalWaypoint(slot) }
    func clearGimbalWaypoint(_ slot: GimbalWaypointSlot) { session.clearGimbalWaypoint(slot) }
    func setGimbalLegDuration(ab: TimeInterval?, bc: TimeInterval?) {
        session.setGimbalLegDuration(ab: ab, bc: bc)
    }
    func setGimbalSmoothness(_ value: Double) { session.setGimbalSmoothness(value) }
    func setGimbalLoop(_ enabled: Bool) { session.setGimbalLoop(enabled) }
    func runProgrammedMove() { session.runProgrammedMove() }
    func pauseOrResumeProgrammedMove() { session.pauseOrResumeProgrammedMove() }
    func restartProgrammedMove() { session.restartProgrammedMove() }
    func clearGimbalProgram() { session.clearGimbalProgram() }
}
