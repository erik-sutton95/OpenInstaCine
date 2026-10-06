import Insta360Apple
import MonitorUI
import OpenCineAppKit
import OpenCineCore
import OpenPocketViewCore
import SwiftUI

/// The app root on the shared shell (SHELL-03): `AppShell` shows the cameras or pair page, or
/// the monitor, from `model.shell`. The existing native monitor (`LiveViewScreen`) is its monitor
/// slot and still presents Settings and Media over itself (temporary); the cover pages over the
/// cameras page are `AppPanelHost`. Sheets, the scene and network checks stay app composition.
struct LinkExperience: View {
    @Environment(AppModel.self) private var model
    @Environment(\.monitorWindowGeometry) private var windowGeometry
    @Environment(\.scenePhase) private var scenePhase
    @State private var orientation = InterfaceOrientationObserver()
    @State private var diagnostics: DiagnosticSharePayload?
    @State private var showProblemReport = false
    /// Twenty seconds on the pair page without a camera: the hint replaces the pre-check.
    @State private var stillLooking = false

    var body: some View {
        AppShell(
            model: model.shell, brand: ShellBrand(name: "OpenInstaCine"),
            actions: ShellActions(
                diagnostics: {
                    if let url = DiagnosticCenter.shared.beginShare(session: model.session) {
                        diagnostics = DiagnosticSharePayload(url: url)
                    }
                },
                reportProblem: { showProblemReport = true },
                // No Multiview entry: this app qualifies no multicam budget (one camera).
                watchFeed: {
                    if model.shell.route == .pair || model.cameras.attempts.isEmpty { model.openWatcherBrowse() }
                },
                // Pair on a nearby card connects it at once, on the pair page.
                pair: {
                    model.shell.beginPairing()
                    if let sighting = model.cameras.nearby.first(where: { $0.id == model.cameras.selection }) {
                        model.cameras.connect(sighting)
                    }
                }),
            safeArea: safeArea,
            pairingFlow: model.pairingWizard(stillLooking: stillLooking).flow(
                model.cameras, onDone: { model.shell.endPairing() }, rescan: { model.integration.retryDiscovery() })
        ) { _ in
            LiveViewScreen()
        } page: { cover in
            AppPanelHost(cover: cover)
        }
        .foregroundStyle(model.isLive ? AnyShapeStyle(.primary) : AnyShapeStyle(StartupColors.ink))
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
        .task(id: model.shell.route == .pair) {
            stillLooking = false
            guard model.shell.route == .pair, (try? await Task.sleep(for: .seconds(20))) != nil else { return }
            stillLooking = true
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

extension AppModel {
    /// The pair wizard in OpenInstaCine's words: the Luna pages, the pre-check (or the hint after
    /// twenty seconds without a camera), the session's live label, a Bluetooth failure, the camera
    /// Wi-Fi joined and a local VPN.
    func pairingWizard(stillLooking: Bool) -> PairingWizard {
        PairingWizard(
            bodies: [
                "Turn the Luna on and keep this iPhone nearby. It shows up by the last characters of its serial number.",
                "If the camera asks to allow this iPhone, tap Allow on its screen. First-time pairing can wait up to 90 seconds.",
                "We read the camera's Wi-Fi over Bluetooth, then join it for you.",
                "Exposure, LUTs and scopes go live as soon as the video link is up.",
            ],
            approveLines: ["Look for the connection request", "Tap Allow on the camera screen"],
            joinLines: [
                "Leave the camera on. It brings up its own 5 GHz Wi-Fi",
                "Close the Insta360 app on other phones so the camera is free",
            ],
            choosing: stillLooking && cameras.nearby.isEmpty
                ? .init(
                    title: StartupConnectionCopy.scanEmptyTitle, icon: .camera,
                    lines: [StartupConnectionCopy.scanEmptyHint])
                : .init(
                    title: StartupConnectionCopy.preCheckTitle, icon: .phone, lines: [StartupConnectionCopy.preCheck]),
            label: liveLabel,
            discoveryFailure: discoveryFailure, joinedNetwork: session.joinedSSID,
            vpnActive: LocalVPNProbe.isActive())
    }

    /// Main's live label: the scan while choosing, then the session's phase (a connect starts at
    /// the Bluetooth link; the simulator review's scripted camera never moves the session).
    private var liveLabel: String {
        typealias Phase = OpenPocketViewCore.ConnectionPhase
        if cameras.attempts.isEmpty { return Phase.scanning.label }
        return session.phase == .idle ? Phase.connectingGatt.label : session.phase.label
    }
}
