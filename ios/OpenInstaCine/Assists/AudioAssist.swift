import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// Presentation of the existing camera/clip level and peak measurements.
enum AudioAssist {
    static let panelSize = MonitorAudioMetrics.panelSize
    static let barCrossAxis = MonitorAudioMetrics.barCrossAxis
    static let helpCopy = "Meters the camera's audio. Available while live view is up."
    static let playbackHelpCopy = "Meters the playing clip."

    static func displayedSensitivity(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "—" : trimmed.uppercased()
    }

    static func longPressMenu(assist _: LiveAssistState, compact: Bool = false)
        -> AudioLongPressMenu
    {
        AudioLongPressMenu(compact: compact)
    }

    static func longPressMenu(compact: Bool = false) -> AudioLongPressMenu {
        AudioLongPressMenu(compact: compact)
    }

    static func meter(levels: MonitorAudioMeterLevels, sensitivity: String?) -> AudioMetersPanelMini {
        AudioMetersPanelMini(levels: levels, sensitivity: sensitivity)
    }
}

struct AudioLongPressMenu: View {
    @Environment(AppModel.self) private var model
    @Bindable private var store = AudioAssist.store
    var compact = false

    var body: some View {
        MonitorAudioMenu(orientation: Binding(get: { store.options.orientation }, set: {
            store.options.orientation = $0; store.persist()
        }), showsDB: Binding(get: { store.options.showsDB }, set: {
            store.options.showsDB = $0; store.persist()
        }), help: model.assist.gradesClip ? AudioAssist.playbackHelpCopy : AudioAssist.helpCopy,
            compact: compact, orientationFeedback: {
                OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled)
            })
    }
}

/// Draw-only body; movement and options gestures belong to AudioMeterOverlay.
struct AudioMetersPanelMini: View {
    let levels: MonitorAudioMeterLevels
    let sensitivity: String?
    var orientation: AudioAssist.Orientation = .vertical
    var showsDB = false

    var body: some View {
        MonitorAudioMeter(left: levels.left.levelDB, leftPeak: levels.left.peakDB,
            right: levels.right.levelDB, rightPeak: levels.right.peakDB,
            orientation: orientation, showDB: showsDB,
            sensitivityLabel: AudioAssist.displayedSensitivity(sensitivity))
    }
}
