import MonitorPresentation
import OpenCineCameraControls
import OpenCineCameraVocabulary
import OpenInstaViewCore

/// This app's side of the shared debug feed-stress seam (`FeedStressAutomation` in OpenCine).
/// A Luna session records `live` or `none`; the seam does not reconnect a saved camera.
extension AppModel: FeedStressHost {
    var feedStressIsLive: Bool { session.phase == .live }
    var feedStressStatus: CameraStatus { session.status }
    var feedStressBodyFamily: CameraBodyFamily { session.bodyFamily }

    func feedStressAssistIsOn(_ tool: MonitorAssistSelection) -> Bool { assist.isOn(tool) }
    func feedStressToggleAssist(_ tool: MonitorAssistSelection) { assist.toggle(tool) }

    func feedStressReconnect() -> FeedStressReconnect {
        .observed(isLive: session.phase == .live)
    }

    func feedStressEndGimbalStick() { session.endGimbalStick(cancelMove: true) }
    func feedStressStopRecording() { session.pressShutter() }
    func feedStressSetISO(_ index: IsoIndex) { session.setISO(index) }
    func feedStressSetIsoLimit(_ limit: IsoLimit) { session.setIsoLimit(limit) }
    func feedStressSetWhiteBalanceAuto(tint: Int) { session.setWhiteBalanceAuto(tint: tint) }

    func feedStressSetWhiteBalanceCustom(kelvin: Int, tint: Int) {
        session.setWhiteBalanceCustom(kelvin: kelvin, tint: tint)
    }
}
