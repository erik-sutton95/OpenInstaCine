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
    @State private var showMultiview = false

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
                reportProblem: { model.isProblemReportPresented = true },
                watchFeed: {
                    if model.shell.route == .pair || model.cameras.attempts.isEmpty { model.openWatcherBrowse() }
                },
                multiview: {
                    guard model.cameras.attempts.isEmpty else { return }
                    model.openMultiview()
                    showMultiview = true
                },
                // Pair on a nearby card connects it at once, on the pair page.
                pair: {
                    model.shell.beginPairing()
                    if let sighting = model.cameras.nearby.first(where: { $0.id == model.cameras.selection }) {
                        model.pair(sighting)
                    }
                }),
            pairingFlow: model.pairingFlow(),
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
        // The app's one problem report, above every cover: a draft opened from Settings
        // survives the camera session ending and the cover closing (A2-24).
        .sheet(isPresented: Bindable(model).isProblemReportPresented) { ProblemReportView().environment(model) }
        .fullScreenCover(
            isPresented: $showMultiview, onDismiss: { model.closeMultiview() },
            content: { MultiviewView(makeSession: { model.makeMultiviewSession() }).environment(model) })
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
        #if targetEnvironment(macCatalyst)
            // The Mac cannot join the camera's Wi-Fi: the camera joins the Mac's network.
            let bodies = [
                "Turn the Luna on and keep it near this Mac. It shows up by the last characters of its serial number.",
                "If the camera asks to allow this Mac, tap Allow on its screen. First-time pairing can wait up to 90 seconds.",
                "",  // The shared wizard words the Mac's network step.
                "Exposure, LUTs and scopes go live as soon as the video link is up.",
            ]
            let joinLines = [
                "Leave the camera on. It moves onto your network",
                "Close the Insta360 app on other phones so the camera is free",
            ]
        #else
            let bodies = [
                "Turn the Luna on and keep this iPhone nearby. It shows up by the last characters of its serial number.",
                "If the camera asks to allow this iPhone, tap Allow on its screen. First-time pairing can wait up to 90 seconds.",
                "We read the camera's Wi-Fi over Bluetooth, then join it for you.",
                "Exposure, LUTs and scopes go live as soon as the video link is up.",
            ]
            let joinLines = [
                "Leave the camera on. It brings up its own 5 GHz Wi-Fi",
                "Close the Insta360 app on other phones so the camera is free",
            ]
        #endif
        return PairingWizard(
            bodies: bodies,
            approveLines: ["Look for the connection request", "Tap Allow on the camera screen"],
            joinLines: joinLines,
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

    /// The wizard with its actions on the pair page. On the Mac, Continue joins the camera to the
    /// camera network (asked once) and the page shows that network with Change network.
    func pairingFlow() -> IntegrationPairingFlow {
        let wizard = pairingWizard()
        let done = { [weak self] in self?.shell.endPairing() ?? () }
        let rescan = { [weak self] in self?.integration.retryDiscovery() ?? () }
        #if targetEnvironment(macCatalyst)
            return wizard.flow(
                cameras, host: .mac, stationNetwork: cameraNetwork.network,
                connect: { [weak self] in self?.pair($0) },
                content: AnyView(
                    CameraNetworkPairingView(
                        pairing: cameraNetwork, model: cameras, brand: InstaStationNetwork.brand,
                        services: InstaStationNetwork.services(session.backend))),
                onDone: done, rescan: rescan)
        #else
            return wizard.flow(cameras, onDone: done, rescan: rescan)
        #endif
    }

    /// Pairs a nearby camera: its own Wi-Fi on iPhone and iPad, the camera network on the Mac.
    func pair(_ sighting: CamerasModel.Sighting) {
        #if targetEnvironment(macCatalyst)
            Task { await cameraNetwork.pair(sighting, in: cameras) }
        #else
            cameras.connect(sighting)
        #endif
    }

    /// Main's live label: the scan while choosing, then the session's phase (a connect starts at
    /// the Bluetooth link; the simulator review's scripted camera never moves the session).
    private var liveLabel: String {
        typealias Phase = OpenInstaViewCore.ConnectionPhase
        if cameras.attempts.isEmpty { return Phase.scanning.label }
        return session.phase == .idle ? Phase.connectingGatt.label : session.phase.label
    }
}
