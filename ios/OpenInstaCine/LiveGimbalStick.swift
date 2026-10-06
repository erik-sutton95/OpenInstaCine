import CoreVideo
import OpenCineCameraControls
import OpenPocketViewCore

/// The shared on-feed stick and head-track dials, on this app's model and palette.
typealias LiveGimbalStick = OpenCineCameraControls.LiveGimbalStick<AppModel, LiveDesign>
typealias LiveHeadTrackAxisDials = OpenCineCameraControls.LiveHeadTrackAxisDials<LiveDesign>

/// The shared stick driving this app's camera session.
extension AppModel: GimbalStickHost {
    var gimbalStickSourceBuffer: CVPixelBuffer? { frameSamples.sourcePixelBuffer }
    func updateGimbalStick(x: Double, y: Double, mapping: GimbalStick.Mapping) {
        session.updateGimbalStick(
            x: x, y: y, sensitivity: gimbalStickSensitivity,
            assistMirror: assist.mirrorsHorizontally,
            mapping: mapping)
    }
    func endGimbalStick() { session.endGimbalStick() }
    func performGimbalDoubleTap() { session.performGimbalDoubleTap() }
    func flipGimbal() { session.flipGimbal() }
}
