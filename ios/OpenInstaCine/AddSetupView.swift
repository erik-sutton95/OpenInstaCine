import Insta360Apple
import Insta360Protocol
import MonitorUI
import OpenCineAppKit
import OpenCineAppKitApple
import OpenCineCore
import SwiftUI

/// Cameras › Add setup: OpenCine's shared chooser ("How should this camera connect?") and its
/// Wi-Fi and Hotspot wizard, as in every OpenCine app. The Luna integration moves the camera onto
/// the chosen network over Bluetooth and keeps the password; the wizard's choice becomes a
/// `RouteDraft`.
@MainActor
enum InstaAddSetup {
    static func flow(
        camera: SavedCamera, cameras: CamerasModel, backend: LunaCameraBackend,
        done: @escaping (RouteDraft?) -> Void
    ) -> AddSetupFlow {
        let chooser = StationNetworkSetupRules.setupChooser(context: .camera(camera))
        return AddSetupFlow(
            chooser: chooser,
            onSelect: { _ in },
            destination: { option in
                AnyView(
                    InstaSetupDestination(
                        camera: camera, kind: option.kind, backend: backend,
                        editing: CamerasMapping.addSetupSelection(cameras, camera: camera, chooser: chooser)
                            == option.id,
                        done: done))
            },
            onCancel: { done(nil) })
    }
}

/// The wizard for one route kind. The Luna cannot list networks, so the wizard offers this
/// phone's network, the setups this phone saved, and Other network.
private struct InstaSetupDestination: View {
    let camera: SavedCamera
    let kind: RouteKind
    let backend: LunaCameraBackend
    /// Reopened from a failed setup of this kind: straight to its password.
    let editing: Bool
    let done: (RouteDraft?) -> Void

    var body: some View {
        StationNetworkSetupView(
            context: .camera(camera), brand: InstaStationNetwork.brand,
            services: InstaStationNetwork.services(backend), scan: nil, cameraScansNetworks: false,
            save: { network in
                done(
                    RouteDraft(
                        kind: network.hotspot ? .phoneHotspot : .infrastructureNetwork,
                        network: network.ssid, secret: network.password))
                return true
            }, close: { done(nil) }, path: path
        )
        .presentationBackground(MonitorTheme.background)
    }

    private var path: [StationNetworkSetupView.Page] {
        if kind == .phoneHotspot { return [.hotspot] }
        if editing, let network = StationNetworkSetupRules.network(camera, .infrastructureNetwork) {
            return [.password(network)]
        }
        return [.networks]
    }
}

/// This app's brand words and Luna services for OpenCine's station-network wizard.
@MainActor
enum InstaStationNetwork {
    /// Luna access points are named after the camera ("Luna Ultra 1A2B3C.OSC").
    static let brand = StationNetworkBrand(
        appName: "OpenInstaCine", cameraFamily: "Luna", cameraNetworkPrefix: "luna")

    static func services(_ backend: LunaCameraBackend) -> StationNetworkServices {
        StationNetworkServices(
            savedNetworks: {
                backend.savedStations().map {
                    StationNetwork(ssid: $0.ssid, password: $0.password, hotspot: $0.hotspot)
                }
            },
            currentSSID: { await LunaCameraBackend.phoneWiFiName() },
            hotspotActive: { LunaCameraBackend.phoneHotspotActive },
            acceptsJoin: { LunaProtocol.acceptsStationNetwork(ssid: $0, password: $1) })
    }
}
