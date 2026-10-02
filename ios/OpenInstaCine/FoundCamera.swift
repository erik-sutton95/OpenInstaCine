import Foundation
import OpenPocketViewCore

/// A camera seen in a scan (kept from the removed DJI BLE link, which declared it).
struct FoundCamera: Identifiable, Sendable {
    let id: UUID  // peripheral identifier (CoreBluetooth hides the MAC)
    let name: String
    let model: CameraModel
    let modelId: Int?

    /// A nameless first advert of a saved Nano must not resolve as a Pocket.
    func enriched(from saved: SavedCamera?) -> FoundCamera {
        let next = FoundCameraIdentity.enriched(
            name: name, modelId: modelId,
            savedName: saved?.advertisedName, savedModelId: saved?.modelId)
        guard next.name != name || next.modelId != modelId else { return self }
        return FoundCamera(
            id: id,
            name: next.name,
            model: CameraModel.resolve(
                modelId: next.modelId,
                name: next.name,
                brand: CameraBrand.of(address: nil, name: next.name)
            ),
            modelId: next.modelId
        )
    }
}
