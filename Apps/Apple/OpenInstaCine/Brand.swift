import MonitorUI
import SwiftUI

enum OpenInstaCineBrand {
    /// Insta360-adjacent yellow, not the OEM chip.
    static let accentRGB: UInt32 = 0xFFCF00

    static func apply() {
        MonitorTheme.accentRGB = accentRGB
        MonitorTheme.prepareResources()
    }
}
