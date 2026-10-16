import OpenCineAppKitApple
import MonitorPresentation
import OpenCineCameraControls
import SwiftUI

/// Insta monitor tools around a remote source (OpenCineCameraControls).
typealias WatcherLiveView = MonitorOperatorWatcherLiveView<AppModel>

extension AppModel: MonitorWatcherLiveHost {
    typealias Picture = InstaLivePicture
    static var assistStores: AssistPanelStores { .app }
    static var falseColorLooks: FalseColorLooks { .app }
    static var operatorHaptics: OperatorHaptics { .app }
    static var watcherBrand: MonitorWatcherLiveBrand {
        MonitorWatcherLiveBrand(
            lookProfile: { _ in LunaShellMapping.lookProfile },
            zoomLabelCeiling: { Double($0.max() ?? 1_200) / 100 })
    }
    func inspectorPreview(tool: MonitorAssistSelection) -> some View { AssistInspectorPreview(tool: tool) }
    func lookMenu() -> some View { LUTAssist.longPressMenu(assist: assist) }
}

extension HevcDecoder: MonitorOperatorLiveDecoder {}
