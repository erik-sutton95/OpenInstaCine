import Foundation
import MonitorPresentation
import OpenPocketViewCore

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
        #if targetEnvironment(simulator)
            if MonitorUIReview.isActive {
                let gimbal = ProcessInfo.processInfo.environment["OPV_UI_REVIEW_BODY"] != "nano"
                return MonitorCapabilities(
                    gimbal: gimbal, zoom: gimbal, focus: gimbal, audio: true,
                    headTracking: gimbal, clipDelete: true, clipStar: true,
                    requiresInternetHop: true, timecode: true)
            }
        #endif
        // Luna phone protocol: no AF-S/AF-C switch, iris, audio meters, gimbal attitude
        // (so no head tracking) or timecode. Favorites are kept on the phone.
        return MonitorCapabilities(
            gimbal: session.hasGimbal, zoom: session.supportsZoom,
            focus: session.supportsFocusMode, iris: session.supportsAperture, audio: false,
            headTracking: false, clipDelete: true, clipStar: true,
            requiresInternetHop: true, timecode: false)
    }
}
