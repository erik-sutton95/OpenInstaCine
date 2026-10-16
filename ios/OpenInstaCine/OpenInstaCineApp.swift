import MonitorUI
import OpenCineAppKit
import OpenCineCameraControls
import SwiftUI

@main
struct OpenInstaCineApp: App {
    init() {
        #if DEBUG
            AppDiagnostics.verification.prepareIfRequested()
        #endif
        AppDiagnostics.reporting.noteFeedUpscaler(FeedUpscaleSwitch.shared.upscaler.rawValue)
        AppDiagnostics.reporting.install()
        #if DEBUG
            AppDiagnostics.verification.runIfRequested()
        #endif
        OpenInstaCineBrand.apply()
        MonitorTheme.prepareResources()
        FeedStressAutomation.installIfRequested(
            host: { AppModelDiagnosticsAnchor.model },
            onInjectionActivated: { AppDiagnostics.reporting.noteCurrentTestSource(.faultInjection) })
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
