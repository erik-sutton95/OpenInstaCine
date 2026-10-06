import MonitorUI
import OpenInstaViewCore
import SwiftUI

/// Mimo's green (x) on the locked subject box.
struct LiveTrackingCancelButton: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        MonitorTrackingCancelButton(color: LiveDesign.good, ink: LiveDesign.background) {
            model.session.cancelSubjectTracking()
        }
    }
}
