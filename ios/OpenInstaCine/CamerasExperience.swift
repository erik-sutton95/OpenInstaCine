import Insta360Apple
import MonitorUI
import OpenCineAppKit
import OpenCineCore
import OpenPocketViewCore
import SwiftUI

/// Connection home on the shared OpenCine screens (SHELL-02): the pair page while no camera is
/// saved or the operator chose Pair, else the cameras page. Mirrors OpenZCine `LinkExperience`.
struct LinkExperience: View {
    @Environment(AppModel.self) private var model
    @Environment(\.monitorWindowGeometry) private var windowGeometry
    @Environment(\.scenePhase) private var scenePhase
    @State private var orientation = InterfaceOrientationObserver()
    @State private var diagnostics: DiagnosticSharePayload?
    @State private var showProblemReport = false

    var body: some View {
        GeometryReader { proxy in
            let safeArea = safeArea(proxy)
            if model.shouldShowWizard {
                PairScreen(
                    model: model.cameras, safeArea: safeArea,
                    onDone: { model.isPairingNewCamera = false },
                    onDiagnostics: {
                        if let url = DiagnosticCenter.shared.beginShare(session: model.session) {
                            diagnostics = DiagnosticSharePayload(url: url)
                        }
                    },
                    onReportProblem: { showProblemReport = true },
                    onWatchFeed: { model.openWatcherBrowse() })
            } else {
                CamerasScreen(
                    model: model.cameras, brandName: "OpenInstaCine", safeArea: safeArea,
                    onPair: { model.isPairingNewCamera = true },
                    onMedia: { model.homePanel = .media }, onSettings: { model.homePanel = .settings },
                    // No Multiview entry: this app qualifies no multicam budget (one camera).
                    onWatchFeed: { if model.cameras.attempts.isEmpty { model.openWatcherBrowse() } })
            }
        }
        .ignoresSafeArea()
        .background(StartupColors.background.ignoresSafeArea())
        .foregroundStyle(StartupColors.ink)
        .onAppear { orientation.start() }
        .onDisappear { orientation.stop() }
        .sheet(item: $diagnostics) { payload in DiagnosticActivityShareView(items: [payload.url]) }
        .sheet(isPresented: $showProblemReport) { ProblemReportView().environment(model) }
        .onChange(of: model.session.phase) { _, phase in
            if phase == .openingDatalink { LocalVPNProbe.noteIfActive() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from Settings after Bluetooth was off or not allowed: look again.
            if phase == .active { model.integration.retryDiscovery() }
        }
    }

    private func safeArea(_ proxy: GeometryProxy) -> EdgeInsets {
        let raw = LiveMonitorLayout.resolvedSafeArea(proxy.safeAreaInsets, scene: windowGeometry.safeArea)
        guard proxy.size.height <= proxy.size.width else { return raw }
        return OperatorPanelMetrics.fullScreenPanelSafeArea(
            from: raw, isPortrait: false,
            mirrored: LiveMonitorLayout.shouldMirror(
                leading: raw.leading, trailing: raw.trailing, orientation: orientation.orientation))
    }
}

/// The Luna pairing slot: why Bluetooth discovery is not running (with Open Settings), else the
/// tips this app has always shown while choosing a camera.
struct LunaPairingTips: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var stillLooking = false

    var body: some View {
        Group {
            if let failure = model.discoveryFailure {
                tip("Bluetooth", failure.message, settings: failure.actions.contains(.openSettings))
            } else if stillLooking, model.cameras.nearby.isEmpty {
                tip(StartupConnectionCopy.scanEmptyTitle, StartupConnectionCopy.scanEmptyHint)
            } else {
                tip(StartupConnectionCopy.preCheckTitle, StartupConnectionCopy.preCheck)
            }
            if LocalVPNProbe.isActive() { tip("Check the connection", LocalVPNFilter.wizardBanner) }
        }
        .task {
            try? await Task.sleep(for: .seconds(20))
            stillLooking = true
        }
    }

    /// The shared pair page's instruction card, with an optional Open Settings.
    private func tip(_ title: String, _ text: String, settings: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased()).font(MonitorTheme.font(9, weight: .bold)).tracking(1.4)
            Text(text).font(MonitorTheme.font(12.5)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            if settings, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { openURL(url) }
                    .font(MonitorTheme.font(12.5, weight: .semibold)).foregroundStyle(MonitorTheme.accent)
            }
        }
        .foregroundStyle(MonitorTheme.secondary).frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
}
