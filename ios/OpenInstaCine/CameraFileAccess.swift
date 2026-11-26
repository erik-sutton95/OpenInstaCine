import Foundation
import Insta360Apple
import Insta360Protocol
import OpenCineAppKit

/// Whether this connection can fetch the camera's file bytes over HTTP: clip playback, originals,
/// photo originals, Save and Share. Listing, metadata and thumbnails travel the control link and
/// keep working either way.
///
/// Measured on a Luna Ultra (fw 1.2.7): while the camera sits on a router or hotspot (a Wi-Fi or
/// hotspot setup), its web server answers every file request with 503 "service restricted". On
/// the camera's own Wi-Fi the same requests are served.
enum CameraFileAccess: Equatable {
    case available
    /// The camera is on a Wi-Fi or hotspot setup's network, where it does not serve its files.
    /// `network` is the setup's network name, nil when this connection does not know it.
    case setupNetwork(network: String?, hotspot: Bool)
    /// The camera answered a file request on this connection with 503 "service restricted".
    case refused

    /// `cameraHost` is where this connection reaches the camera; anywhere but the camera's own
    /// access point is a setup's network. `station` is the setup the connection used, if any.
    static func resolve(cameraHost: String, station: LunaStationNetwork?, refused: Bool) -> CameraFileAccess {
        if cameraHost != LunaProtocol.defaultHost {
            return .setupNetwork(network: station?.ssid, hotspot: station?.hotspot ?? false)
        }
        return refused ? .refused : .available
    }

    var allowsFileTransfer: Bool { self == .available }

    /// Share and Save for one item: nil leaves the page's own answer, as while the camera shares
    /// its files. Otherwise Save is off and only an item already on this device shares.
    func heldActions(onDevice: Bool) -> (share: Bool?, download: Bool?) {
        allowsFileTransfer ? (nil, nil) : (onDevice, false)
    }

    /// The player's Save, Share and Delete for one clip. Delete and favorite travel the control
    /// link, so only `deletes` (the source offers delete) and the clip's own fact decide Delete.
    func playbackAccess(onDevice: Bool, deletes: Bool, deletable: Bool?) -> MonitorMediaGalleryAccess {
        let held = heldActions(onDevice: onDevice)
        return .init(download: held.download ?? true, share: held.share ?? true, delete: deletes && deletable == true)
    }

    /// What the operator reads where a file action cannot run.
    var message: String? {
        let stillWorks = "Browsing and thumbnails still work."
        switch self {
        case .available:
            return nil
        case .setupNetwork(let network, let hotspot):
            let place = hotspot ? "the hotspot" : network.map { "“\($0)”" } ?? "this network"
            return "Clips on the camera play over Camera Wi-Fi. On \(place) the Luna doesn’t share its files. "
                + stillWorks
        case .refused:
            return "The Luna isn’t sharing its files right now. " + stillWorks
        }
    }
}

/// The camera hosts that answered a file request with 503 "service restricted", reported by every
/// camera file transport of this app (the gallery's and each connection's). A connection reads
/// only refusals of its own host made after it connected, so a reconnect starts clean.
@MainActor @Observable final class CameraFileRefusals {
    static let shared = CameraFileRefusals()
    private(set) var sequence: UInt64 = 0
    private var latest: [String: UInt64] = [:]

    func record(host: String) {
        sequence &+= 1
        latest[host] = sequence
    }

    /// Whether `host` refused a file after `baseline` (a ``sequence`` read at connect).
    func refused(host: String, after baseline: UInt64) -> Bool {
        (latest[host] ?? 0) > baseline
    }

    /// The camera's answer to a file request is its "service restricted" refusal: 503 with that
    /// body. Any other failure (a busy camera, a missing file) is not.
    nonisolated static func isServiceRestricted(status: Int, body: Data) -> Bool {
        guard status == 503 else { return false }
        return String(decoding: body.prefix(512), as: UTF8.self).lowercased().contains("service restricted")
    }
}
