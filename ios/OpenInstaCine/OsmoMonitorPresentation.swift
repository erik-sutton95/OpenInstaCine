import Foundation
import MonitorPresentation
import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// Capability translation for the Luna adapter (type name kept from the shared shell so
/// every call site binds unchanged). Monitor modules never identify a camera brand.
@MainActor
enum OsmoMonitorPresentation {
    static func zoomTapStops(_ session: CameraSession) -> MonitorZoomTapStops {
        MonitorZoomTapStops(supported: session.zoomStops, extended: [])
    }

    static func zoomCaption(_ session: CameraSession) -> String {
        MonitorZoomCaption.label(factor: session.zoomReadout, opticalStops: session.zoomStops)
    }

    static func capabilities(_ session: CameraSession) -> MonitorCapabilities {
        // Luna phone protocol: no AF-S/AF-C switch, iris, audio meters, gimbal attitude
        // (so no head tracking) or timecode. Favorites are kept on the phone. Simulator
        // reviews use these same gates so screenshots show what a Luna operator sees.
        return MonitorCapabilities(
            gimbal: session.hasGimbal, zoom: session.supportsZoom,
            focus: session.supportsFocusMode, iris: session.supportsAperture, audio: session.supportsAudio,
            headTracking: true, clipDelete: true, clipStar: true,
            requiresInternetHop: true, timecode: session.supportsTimecode)
    }
}

/// Luna Matrix / Face Priority metering row in the shared Exposure sheet (overlay hook).
/// Hidden until the camera has reported option 46.
struct LunaMeteringToggle: View {
    let session: CameraSession

    var body: some View {
        if session.supportsFaceMetering, let on = session.faceMetering {
            MonitorCaptureToggle(
                "Face metering",
                help: on
                    ? "Face Priority: the camera meters on faces."
                    : "Matrix: the camera meters the whole frame.",
                isOn: Binding(get: { on }, set: { session.setFaceMetering($0) }))
        }
    }
}
