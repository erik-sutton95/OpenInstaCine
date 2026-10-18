import Foundation
import Insta360Apple
import MonitorPresentation
import MonitorUI
import OpenCineCameraControls
import OpenCineCameraVocabulary
import OpenCineCore
import OpenInstaViewCore
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

    /// What the monitor lays out: the Luna integration's projection of the connected camera
    /// (`LunaCameraSession.layout`): gimbal and head tracking from its motion (GET_ANGLE is the
    /// pose), host-derived timecode, no audio levels, no iris. Only clip delete, clip star and
    /// the internet hop are the app's, until media and connection routes carry them (SHELL-02).
    /// No session: the shared pre-connection rule over Luna's static profile (gimbal, zoom,
    /// focus, head tracking), so Settings keeps those rows. Simulator reviews open a
    /// session (`MonitorUIReview.prepare`), so screenshots show what a Luna operator sees.
    static func capabilities(_ session: CameraSession) -> MonitorLayoutCapabilities {
        (session.coreSession as? LunaCameraSession)?.layout(base: appBase)
            ?? MonitorLayoutCapabilities(controls: session.controlCapabilities(), base: appBase)
    }

    private static let appBase: MonitorLayoutCapabilities = {
        var base = MonitorLayoutCapabilities()
        base.clipDelete = true
        base.clipStar = true
        base.requiresInternetHop = true
        return base
    }()
}
