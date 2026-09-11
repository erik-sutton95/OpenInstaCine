import Insta360Apple
import Foundation
import MonitorUI
import MonitorContracts
import SwiftUI

@main
@MainActor
struct OpenInstaCineApp: App {
    private let backend = makeBackend()

    var body: some Scene {
        WindowGroup {
            MonitorAppRoot(brand: .openInstaCine, backend: backend)
        }
    }

    private static func makeBackend() -> any CameraBackend {
        #if DEBUG
        // Local development only: Simulator has no BLE. Use the Mac's existing
        // camera Wi-Fi and a previously authorized identity supplied at launch.
        // No identity or credentials are compiled into an app or stored in git.
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["OPENINSTA_REVIEW_INDEX"], !path.isEmpty {
            return RecordedPreviewBackend(indexURL: URL(fileURLWithPath: path))
        }
        if environment["OPENINSTA_DIRECT_TCP"] == "1",
           let value = environment["OPENINSTA_CLIENT_ID"],
           let identity = UUID(uuidString: value) {
            return LunaCameraBackend(useExistingNetwork: true, authorizedIdentity: identity)
        }
        #endif
        return LunaCameraBackend()
    }
}
