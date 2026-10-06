import Foundation
import Insta360Apple
import MonitorPresentation
import MonitorUI
import OpenCineCore
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

    /// What the monitor lays out: the Luna integration's projection of the connected camera
    /// (`LunaCameraSession.layout`): gimbal and head tracking from its motion (GET_ANGLE is the
    /// pose), host-derived timecode, no audio levels, no iris. Only clip delete, clip star and
    /// the internet hop are the app's, until media and connection routes carry them (SHELL-02).
    /// No session: what this app has always offered before a camera connects (gimbal, zoom,
    /// focus, head tracking, timecode), so Settings keeps those rows. Simulator reviews open a
    /// session (`MonitorUIReview.prepare`), so screenshots show what a Luna operator sees.
    static func capabilities(_ session: CameraSession) -> MonitorLayoutCapabilities {
        (session.coreSession as? LunaCameraSession)?.layout(base: appBase) ?? unconnected
    }

    private static let unconnected: MonitorLayoutCapabilities = {
        var layout = appBase
        (layout.gimbal, layout.zoom, layout.focus, layout.headTracking, layout.timecode) = (true, true, true, true, true)
        return layout
    }()

    private static let appBase: MonitorLayoutCapabilities = {
        var base = MonitorLayoutCapabilities()
        base.clipDelete = true
        base.clipStar = true
        base.requiresInternetHop = true
        return base
    }()
}

/// Luna METER tile beside EXPOSURE (overlay hook): tap switches Matrix and Face Priority
/// metering (option 46). Two values, so it toggles in place instead of opening a drum.
/// Shows a dash until the camera has reported option 46.
struct LunaMeteringTile: View {
    let session: CameraSession

    var body: some View {
        if session.supportsFaceMetering {
            let face = session.faceMetering
            Button {
                if let face { session.setFaceMetering(!face) }
            } label: {
                CaptureBarReadout(
                    label: "METER", value: face.map { $0 ? "Face" : "Matrix" } ?? "-", widest: "Matrix")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .sensoryFeedback(.selection, trigger: face)
            .accessibilityIdentifier("monitor.capture.metering")
            .accessibilityLabel("Metering")
            .accessibilityValue(face.map { $0 ? "Face Priority" : "Matrix" } ?? "Unknown")
            .accessibilityHint("Switches between Matrix and Face Priority metering")
        }
    }
}
