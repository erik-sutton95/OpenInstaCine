import Insta360Apple
import Foundation
import MonitorContracts
import MonitorUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
@MainActor
struct OpenInstaCineApp: App {
    private let backend: any CameraBackend
    #if DEBUG
    private static var labBridge: LunaLabBridgeServer?
    #endif

    init() {
        OpenInstaCineBrand.apply()
        backend = Self.makeBackend()
    }

    var body: some Scene {
        WindowGroup {
            AppRoot(backend: backend)
                .observeMonitorWindowGeometry()
                .statusBarHidden(true)
                .tint(MonitorTheme.accent)
                .task { await Self.runColorRecoveryLabIfNeeded(backend) }
        }
    }

    private static func makeBackend() -> any CameraBackend {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        if let path = environment["OPENINSTA_REVIEW_INDEX"], !path.isEmpty {
            return RecordedPreviewBackend(indexURL: URL(fileURLWithPath: path))
        }
        let identity = environment["OPENINSTA_CLIENT_ID"].flatMap(UUID.init(uuidString:))
        if arguments.contains("--lab-bridge") {
            return LunaCameraBackend(authorizedIdentity: identity, colorRecoveryLab: true)
        }
        if arguments.contains("--set73-lab") {
            return LunaCameraBackend(
                authorizedIdentity: identity, colorRecoveryLab: true, autoSet73: true)
        }
        if environment["OPENINSTA_DIRECT_TCP"] == "1", let identity {
            return LunaCameraBackend(useExistingNetwork: true, authorizedIdentity: identity)
        }
        #endif
        return LunaCameraBackend()
    }

    @MainActor
    private static func runColorRecoveryLabIfNeeded(_ backend: any CameraBackend) async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let luna = backend as? LunaCameraBackend else { return }
        #if DEBUG
        if arguments.contains("--lab-bridge") {
            #if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
            let server = LunaLabBridgeServer(backend: luna)
            labBridge = server
            do {
                try server.start()
                try await luna.startColorRecoveryLab()
                server.note("camera TCP ready")
            } catch {
                server.fail(String(describing: error))
            }
            return
        }
        #endif
        guard arguments.contains("--set73-lab") else { return }
        do {
            try await luna.startColorRecoveryLab()
        } catch {
            let payload: [String: String] = ["proven": "false", "error": String(describing: error)]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
               let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("set73-lab.json")
            {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
