import MonitorUI
import OpenCineAppKit
import SwiftUI

@main
struct OpenInstaCineApp: App {
    init() {
        #if DEBUG
            AppDiagnostics.verification.prepareIfRequested()
        #endif
        AppDiagnostics.reporting.install()
        #if DEBUG
            AppDiagnostics.verification.runIfRequested()
        #endif
        OpenInstaCineBrand.apply()
        MonitorTheme.prepareResources()
        FeedStressAutomation.installIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            root
                .observeMonitorWindowGeometry()
                // iPad ignores Info.plist `UIStatusBarHidden` after launch unless
                // the hosting controller prefers it hidden. `~ipad` covers launch.
                .statusBarHidden(true)
        }
    }

    @ViewBuilder private var root: some View {
        #if DEBUG
            if ReliabilityReportingVerification.mode != nil {
                Text("Reliability verification")
            } else {
                AppRoot()
            }
        #else
            AppRoot()
        #endif
    }
}
