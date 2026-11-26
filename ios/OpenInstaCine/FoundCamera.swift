import Foundation
import Insta360Protocol
import OpenInstaViewCore

/// A camera seen in a scan (kept from the removed DJI BLE link, which declared it).
struct FoundCamera: Identifiable, Sendable {
    let id: UUID  // peripheral identifier (CoreBluetooth hides the MAC)
    let name: String
    let model: CameraModel
    let modelId: Int?

    /// The same camera once its connection identified the Luna body.
    func identified(as body: LunaModel) -> FoundCamera {
        FoundCamera(id: id, name: name, model: LunaShellMapping.cameraModel(for: body), modelId: modelId)
    }
}
