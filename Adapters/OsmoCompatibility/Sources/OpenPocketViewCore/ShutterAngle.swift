import Foundation
import MonitorCore

extension ShutterAngle {
    /// Prefer a legal `camcap_shutter` stop when the body has published a list.
    public static func denom(degrees: Double, fps: Int, available: [Int]) -> Int {
        let ideal = denom(degrees: degrees, fps: fps)
        return CamCapShutter.nearestDenom(ideal, in: available) ?? ideal
    }
}
