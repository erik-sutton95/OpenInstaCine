import Foundation
import OpenPocketViewCore

/// A camera seen in a scan (kept from the removed DJI BLE link, which declared it).
struct FoundCamera: Identifiable, Sendable {
    let id: UUID  // peripheral identifier (CoreBluetooth hides the MAC)
    let name: String
    let model: CameraModel
    let modelId: Int?
}
