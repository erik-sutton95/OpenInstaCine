import Foundation
import OpenPocketViewCore

/// UserDefaults persistence for saved Pocket records. Passwords stay out of this store —
/// they live in the iOS Keychain (`CameraWifiKeychain`) so reconnect survives a Mimo session.
enum SavedCameraStore {
    static let key = "OpenPocketCine.SavedCameras"

    static func load() -> [SavedCamera] {
        guard let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode([SavedCamera].self, from: data)
        else { return [] }
        return SavedCameras.canonicalized(decoded)
    }

    static func save(_ records: [SavedCamera]) {
        let canonical = SavedCameras.canonicalized(records)
        guard let data = try? JSONEncoder().encode(canonical) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
