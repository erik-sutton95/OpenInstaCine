import Insta360Apple
import MonitorUI
import OpenCineAppKit
import OpenCineAppKitApple
import OpenCineCameraControls
import OpenCineCore
import OpenInstaViewCore
import SwiftUI

/// The shared shell retains the native monitor beneath complete settings and catalog covers.
/// Integration pairing facts, diagnostic sheets and network checks stay app composition.
struct LinkExperience: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var diagnostics: MonitorDiagnosticsShareItem?
    @State private var diagnosticsFailure: String?
    @State private var showProblemReport = false

    var body: some View {
        AppShell(
            model: model.shell, brand: ShellBrand(name: "OpenInstaCine"),
            actions: ShellActions(
                diagnostics: {
                    switch DiagnosticCenter.shared.beginShare(session: model.session) {
                    case .ready(let item): diagnostics = item
                    case .failed(let message): diagnosticsFailure = message
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
            pairingFlow: model.pairingWizard().flow(
                model.cameras, onDone: { model.shell.endPairing() }, rescan: { model.integration.retryDiscovery() }),
            coverPresentation: .shell
        ) { _ in
            LiveViewScreen()
        } page: { cover in
            AppPanelHost(cover: cover)
        }
        .overlay { MonitorOperatorDeliveryChrome(model: model.delivery.lifetime, scope: .root, remoteDisplayName: "Frame.io") }
        // The app's one share sheet, above any gallery, player or photo cover (A2-52).
        .monitorDeliverySharePresenter(model.delivery.lifetime)
        .foregroundStyle(model.isLive ? AnyShapeStyle(.primary) : AnyShapeStyle(StartupColors.ink))
        .sheet(item: $diagnostics) { item in MonitorActivityShareSheet(items: [item.url]) }
        .alert(
            "Couldn't write the diagnostics report",
            isPresented: Binding(
                get: { diagnosticsFailure != nil }, set: { if !$0 { diagnosticsFailure = nil } })
        ) {
            Button("OK", role: .cancel) { diagnosticsFailure = nil }
        } message: {
            Text(diagnosticsFailure ?? "")
        }
        .sheet(isPresented: $showProblemReport) { ProblemReportView().environment(model) }
        .onChange(of: model.session.phase) { _, phase in
            if phase == .openingDatalink { LocalVPNNotice.app.noteIfActive() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from Settings after Bluetooth was off or not allowed: look again.
            if phase == .active { model.integration.retryDiscovery() }
        }
    }
}

extension AppModel {
    /// The pair wizard in OpenInstaCine's words: the Luna pages, the pre-check (or the shared
    /// still-looking hint once `CamerasModel.scanLooksEmpty` fires), the session's live label,
    /// a Bluetooth failure, the camera Wi-Fi joined and a local VPN.
    func pairingWizard() -> PairingWizard {
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
            choosing: cameras.scanLooksEmpty
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
        typealias Phase = OpenInstaViewCore.ConnectionPhase
        if cameras.attempts.isEmpty { return Phase.scanning.label }
        return session.phase == .idle ? Phase.connectingGatt.label : session.phase.label
    }
}
