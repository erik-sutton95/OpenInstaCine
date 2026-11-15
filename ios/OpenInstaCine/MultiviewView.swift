import Insta360Apple
import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineAppKitApple
import OpenCineCameraControls
import OpenCineCore
import SwiftUI

/// SwiftUI may construct discarded view values; only the retained owner opens camera resources.
@MainActor
private final class MultiviewSessionOwner {
    private var retained: MultiviewSession?
    private var make: (() -> MultiviewSession)?
    init(make: @escaping () -> MultiviewSession) { self.make = make }

    func session(_ model: AppModel) -> MultiviewSession {
        if let retained { return retained }
        guard let make else { preconditionFailure("Missing retained Multiview constructor") }
        let created = make()
        created.appModel = model
        retained = created
        self.make = nil
        return created
    }
}

/// OpenInstaCine's Multiview: OpenCine's shared screen (`MultiviewScreen`) over this app's session,
/// which is the screen's host (tile pictures, settings editor, Live View, network wizard values).
struct MultiviewView: View {
    @Environment(AppModel.self) private var model
    @State private var owner: MultiviewSessionOwner

    init(makeSession: @escaping @MainActor () -> MultiviewSession) {
        _owner = State(initialValue: MultiviewSessionOwner {
            let stage = makeSession()
            let store = MultiviewStagePreferencesStore(storage: .standard, key: "multiview.presentation")
            stage.coordinator.presentation.attachPersistence(load: store.load, save: store.save)
            return stage
        })
    }

    var body: some View {
        let session = owner.session(model)
        MultiviewScreen(coordinator: session.coordinator, host: session)
    }
}

/// The shared screen's app half: the tiles' pictures, the settings editor, the borrowed Live View
/// and the network wizard's values (the Add setup wizard's, so saved setups prefill).
extension MultiviewSession: MultiviewScreenHost {
    func picture(slot: Int, fill: Bool) -> some View {
        MultiviewTilePicture(tile: tiles[slot], fill: fill)
    }

    func backdrop(
        layout: MultiviewPresentationLayout, geometry: MultiviewStageGeometry, enabled: Bool
    ) -> some ViewModifier {
        EmptyModifier()
    }

    @ViewBuilder func settingsPreview(slot: Int) -> some View {
        MultiviewTilePicture(tile: tiles[slot], fill: false)
    }

    @ViewBuilder func settingsControls(
        slot: Int, category: MultiviewSettingsCategory, enabled: Bool,
        presented: @escaping () -> Bool, close: @escaping () -> Void
    ) -> some View {
        let tile = tiles[slot]
        if let model = tile.controlsModel, let sheet = CaptureSheet(rawValue: category.rawValue) {
            CapturePickerPanel(
                sheet: sheet, isPresented: { tile.controlsModel === model && presented() },
                controlsEnabled: enabled, chromeless: true, onClose: close
            )
            .fixedSize(horizontal: false, vertical: true)
            .environment(model)
            .id(MultiviewPanelIdentity(model: ObjectIdentifier(model), category: sheet))
        }
    }

    @ViewBuilder func liveView(slot: Int, exit: @escaping () -> Void) -> some View {
        if let model = tiles[slot].liveModel {
            LiveViewScreen().environment(model)
                .onAppear { model.multiviewReturn = exit }
        }
    }

    var stationBrand: StationNetworkBrand { InstaStationNetwork.brand }
    var stationServices: StationNetworkServices { InstaStationNetwork.services(setupBackend) }
    var cameraSSIDs: Set<String> {
        Set(appModel?.savedCameras.compactMap { setupBackend.storedWiFi(cameraID: $0.lunaPeripheral)?.ssid } ?? [])
    }
}

/// The settings controls start again for another camera or category.
private struct MultiviewPanelIdentity: Hashable {
    let model: ObjectIdentifier
    let category: CaptureSheet
}

/// One tile's picture: its decoder's surface, Fit or Fill, while no Live View borrows it.
private struct MultiviewTilePicture: View {
    let tile: MultiviewSession.Tile
    let fill: Bool

    var body: some View {
        if tile.liveModel == nil {
            GeometryReader { picture in
                let ratio = tile.session.pictureAspect
                VideoView(
                    decoder: tile.session.decoder, effects: tile.effects, sampleBus: tile.samples,
                    transfer: tile.session.status.monitorTransfer)
                    .frame(
                        width: fill ? max(picture.size.width, picture.size.height * ratio) : picture.size.width,
                        height: fill ? max(picture.size.height, picture.size.width / ratio) : picture.size.height
                    )
                    .position(x: picture.size.width / 2, y: picture.size.height / 2)
            }
        }
    }
}

extension SavedCamera {
    /// The Bluetooth peripheral a saved Luna was paired as (its id).
    var lunaPeripheral: UUID { UUID(uuidString: id) ?? UUID() }
}
