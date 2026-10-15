import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineCameraControls
import OpenInstaViewCore
import SwiftUI
import UIKit

typealias PocketDispMode = MonitorDisplayMode
typealias PocketDispChrome = MonitorDisplayChrome

enum OpenInstaCineLinks {
    static let source = URL(string: "https://github.com/erik-sutton95/OpenInstaCine")
    static let support = URL(
        string: "https://github.com/erik-sutton95/OpenInstaCine/discussions/categories/q-a")
    static let reportProblem = URL(
        string: "https://github.com/erik-sutton95/OpenInstaCine/issues/new?template=bug_report.yml"
    )
    static let featureRequest = URL(
        string: "https://github.com/erik-sutton95/OpenInstaCine/discussions/new?category=ideas")
    static let privacy = URL(string: "https://opencapture.org/openinstacine/privacy")
    static let terms = URL(string: "https://opencapture.org/openinstacine/terms")
}

typealias OperatorSettingsHaptics = OpenCineCameraControls.OperatorSettingsHaptics

extension OperatorHaptics {
    /// The operator's haptics switch, read at each tap.
    static let app = OperatorHaptics { OperatorPrefs.hapticsEnabled }
}
