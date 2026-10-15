import OpenCineAppKitApple
import OpenCineCameraControls
import OpenCineRelayApple
import OpenInstaViewCore
import UIKit

typealias WatcherBrowseView = WatcherBrowse<AppModel>

/// Browse, join, passcode and leave are the shared watcher owner's; this app names its Keychain
/// and closes its own covers when a join goes live.
extension AppModel: WatcherBrowseHost, WatcherRelayViewer {
    var relayKeychain: WatcherRelayKeychain { .app }
    var watcherDeviceName: String { UIDevice.current.name }

    func dismissCoversForWatching() { shell.dismissCover() }
}
