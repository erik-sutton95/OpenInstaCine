import MonitorPresentation
import MonitorUI
import OpenCineAppKitApple
import OpenCineCameraControls
import OpenCineCore
import OpenInstaViewCore
import SwiftUI

/// The shared complete operator surface (OpenCineCameraControls) over this app's session.
typealias LiveViewScreen = MonitorOperatorLiveScreen<AppModel>

extension AppModel: MonitorLiveScreenHost {
    static func headphoneBridge() -> HeadphoneMotionBridge { .appBridge() }
    var liveCapabilities: MonitorLayoutCapabilities { OsmoMonitorPresentation.capabilities(session) }
    var liveZoomCaption: String { OsmoMonitorPresentation.zoomCaption(session) }
    var simulatorLiveColorMode: ColorMode? {
        #if targetEnvironment(simulator)
            !MonitorUIReview.isActive && SimulatorLiveFeed.isConfigured ? .iLog : nil
        #else
            nil
        #endif
    }
    func liveLevelDisplay(_ mode: LevelReading.Mode) -> MonitorLevelDisplay { LevelAssist.display(mode) }
    var livePictureEV: (() -> EvComp?)? { { self.pictureEV } }
    func lutPicker() -> some View { LUTPicker(assist: assist) }
}

extension CameraSession: MonitorLiveScreenSession {
    var liveLevelReading: LevelReading { levelReading }
    func cancelProgrammedGimbalMove() { cancelProgrammedMove() }
    func takeLivePhoto() { pressShutter() }
}

extension HevcDecoder: MonitorOperatorLiveScreenDecoder {}
