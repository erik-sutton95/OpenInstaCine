import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineCameraControls
import SwiftUI

typealias FieldMonitorStatusChrome = LiveStatusChrome<AppModel>
typealias FieldMonitorAssistPalette = LiveAssistPalette<AppModel, AssistToolIcon>
typealias FieldMonitorGauges = LiveTelemetryGauges<AppModel>
typealias LiveTopPickerHost = LiveTopSheetHost<AppModel>
typealias ChromeEditBadgeLayer = ChromeEditBadges<AppModel>
typealias ChromeEditBanner = ChromeEditDoneBanner<AppModel>

/// The shared capture strip with this app's face metering tile after EXPOSURE.
struct LiveCameraControlBar: View {
    var columns = 6
    @Environment(AppModel.self) private var model

    var body: some View {
        CaptureControlBar<AppModel, LunaMeteringTile>(columns: columns) {
            LunaMeteringTile(session: model.session)
        }
    }
}

extension LiveAssistPalette where Host == AppModel, Icon == AssistToolIcon {
    init(
        layout: LiveMonitorLayout, isLocked: Bool, otherOverlayPresented: Bool = false,
        expanded: Binding<Bool>, onExpansionActivityChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.init(
            layout: layout, isLocked: isLocked, otherOverlayPresented: otherOverlayPresented,
            expanded: expanded, onExpansionActivityChange: onExpansionActivityChange
        ) { AssistToolIcon(tool: $0, size: nil) }
    }
}

extension View {
    func chromeEditable(_ section: PocketDispChrome.Section, editing mode: PocketDispMode?)
        -> some View
    {
        modifier(ChromeEditableModifier<AppModel>(section: section, mode: mode))
    }
}

/// The shared live chrome on this app's session: the status clock follows the camera's elapsed
/// seconds, and the timecode readout shows whenever its DISP section is on.
extension AppModel: LiveChromeHost {
    var liveStatus: MonitorStatusPresentation {
        control.statusPresentation(elapsedSeconds: session.status.recordElapsedSec)
    }
    var timecodeAvailable: Bool { true }
    var liveSignalBars: Int { session.liveSignalBars }
    var liveFPS: String { session.liveFPS }
    var gimbalPanelOpen: Bool { liveGimbalPanel != .none }
}
