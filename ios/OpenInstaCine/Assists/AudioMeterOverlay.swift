import OpenCineCameraControls
import OpenInstaViewCore
import SwiftUI

/// Keeps frequent audio observations inside the meter, not the scope host.
struct LiveAudioMeterOverlay: View {
    @Environment(AppModel.self) private var model
    let bounds: CGRect
    var chromeClearance: EdgeInsets = EdgeInsets()

    var body: some View {
        AudioMeterOverlay(
            stores: .app,
            levels: model.session.status.audioMeters ?? .silent,
            sensitivity: model.session.status.audioChannel?.label,
            bounds: bounds, chromeClearance: chromeClearance,
            hapticsEnabled: model.hapticsEnabled,
            onConfigure: { model.assist.configureTool = .audioMeters })
    }
}
