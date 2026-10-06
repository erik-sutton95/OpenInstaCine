import MonitorUI
import OpenCineCameraControls
import OpenPocketViewCore
import SwiftUI

extension FalseColorLooks {
    /// This app's curves, named in the scale help, and their official Rec.709 looks.
    static let app = FalseColorLooks(
        scaleHelp:
            "The camera color mode selects I-Log, Standard, or Dolby Vision automatically. "
            + "CineStop paints five stops around 18% gray, read through the "
            + "camera's log curve: dark green −2, yellow-green −1, gray at 18%, light pink +1 "
            + "(skin), soft yellow +2 (upper skin limit). Red is clipped and violet is crushed; "
            + "other shadows are flat dark gray and other highlights flat light gray. "
            + "Video paints video-level IRE stripes (green 41–48, pink 61–70, red clip) "
            + "over luminance grayscale. IRE paints six video-level zones over "
            + "luminance grayscale: purple crush, blue near-black, green 18% gray, pink one "
            + "stop over, yellow near clip, red clip. On log, Video and IRE read the camera's "
            + "Rec.709 look (709) or the raw signal (LOG), set under Read. Limits paints only shadow and highlight warnings, leaving other colors untouched.",
        rec709LookCurve: { LiveColorScience.rec709LookCurve($0) })
}

extension FalseColorAssist {
    @MainActor
    static func selectScale(_ label: String, assist: LiveAssistState) {
        assist.falseColorScale = scale(forMenuLabel: label)
        assist.persist()
    }
}

/// The false color menu over the monitored source's transfer and its live ceiling.
struct LiveFalseColorMenu: View {
    @Bindable var assist: LiveAssistState
    var compact = false
    @Environment(AppModel.self) private var model

    var body: some View {
        let transfer =
            model.monitorTransfer ?? model.monitorColorMode.map(MonitorTransfer.init) ?? .rec709
        FalseColorAssist.commonMenu(
            assist: assist, looks: .app, haptics: .app, compact: compact, transfer: transfer,
            clipByte: model.monitorSamples.exposureCeiling.clipByte(transfer: transfer))
    }
}
