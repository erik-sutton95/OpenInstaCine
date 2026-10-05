import MonitorUI
import SwiftUI

/// OpenZCine `MonitorSystemCluster.lockButton` (`MonitorUnified.swift` ~1068).
struct LiveLockButton: View {
    @Binding var locked: Bool
    var size: CGFloat = LiveChromeMetrics.lockButtonSize

    var body: some View {
        MonitorLockButton(locked: $locked, side: size)
    }
}
