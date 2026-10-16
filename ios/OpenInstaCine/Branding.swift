import MonitorUI
import SwiftUI

/// OpenInstaCine launch identity: Luna yellow on black.
enum AppBrand {
    static var identity: MonitorBrandIdentity {
        MonitorBrandIdentity(
            name: "OpenInstaCine", monogram: "OPC", accent: { MonitorTheme.accent },
            glow: Color(red: 120 / 255, green: 102 / 255, blue: 70 / 255))
    }
}

struct LaunchSplashOverlay: View {
    @Binding var isVisible: Bool

    var body: some View {
        MonitorLaunchSplashOverlay(isVisible: $isVisible) {
            MonitorBrandLaunchSplash(AppBrand.identity)
        }
    }
}
