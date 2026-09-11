import Darwin
import Foundation
import MonitorContracts
import NetworkExtension

@MainActor
enum LunaWiFi {
    static var localAddress: String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(first) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            guard let address = current.pointee.ifa_addr,
                address.pointee.sa_family == UInt8(AF_INET)
            else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil,
                0, NI_NUMERICHOST) == 0
            {
                let text = String(cString: buffer)
                if text.hasPrefix("192.168.42."), text != "192.168.42.1" { return text }
            }
        }
        return nil
    }
    static func join(_ credentials: LunaStoredWiFi) async throws {
        try Task.checkCancellation()
        #if targetEnvironment(macCatalyst) || os(macOS)
            guard localAddress != nil else {
                throw CameraBackendError.unavailable(
                    "Join the camera Wi-Fi in macOS Wi-Fi settings, then reconnect. Its password has been read securely from the camera."
                )
            }
        #elseif targetEnvironment(simulator)
            guard localAddress != nil else {
                throw CameraBackendError.unavailable(
                    "Join the camera Wi-Fi on the Mac to test the live feed in Simulator. Bluetooth pairing requires a physical device."
                )
            }
        #else
            let config = NEHotspotConfiguration(
                ssid: credentials.ssid, passphrase: credentials.password, isWEP: false)
            config.joinOnce = false
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                NEHotspotConfigurationManager.shared.apply(config) { error in
                    if let error = error as NSError?,
                        !(error.domain == NEHotspotConfigurationErrorDomain
                            && error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue)
                    {
                        continuation.resume(
                            throwing: CameraBackendError.unavailable(
                                "The camera Wi-Fi could not be joined. Keep the camera powered on and accept the iOS Wi-Fi prompt."
                            ))
                    } else {
                        continuation.resume()
                    }
                }
            }
        #endif
        let deadline = Date().addingTimeInterval(18)
        while localAddress == nil, Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(200))
        }
        guard localAddress != nil else {
            throw CameraBackendError.unavailable(
                "The camera Wi-Fi did not assign an address. Reconnect and accept the Wi-Fi join prompt."
            )
        }
    }
    static func leave(ssid: String) {
        #if os(iOS) && !targetEnvironment(macCatalyst) && !targetEnvironment(simulator)
            NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
        #endif
    }
}
