import MonitorPresentation
import MonitorUI
import SwiftUI

/// OpenZCine `MonitorSystemCluster.displayButton` (`MonitorUnified.swift` ~1143).
/// DISP 1 = live chrome. DISP 2 = clean (OpenZCine `DisplayChromeVisibility.cleanDefaults`).
struct LiveDispToggle: View {
    var size: CGSize = CGSize(
        width: LiveChromeMetrics.displayButtonWidth, height: LiveChromeMetrics.displayButtonHeight)
    @Environment(AppModel.self) private var model
    @Environment(\.interfaceLocked) private var interfaceLocked

    var body: some View {
        MonitorDisplayButton(clean: model.assist.clean, size: size, enabled: !interfaceLocked) {
            guard !interfaceLocked else { return }
            model.assist.clean.toggle()
            if model.assist.clean { model.captureSheet = nil }
        }
    }
}
