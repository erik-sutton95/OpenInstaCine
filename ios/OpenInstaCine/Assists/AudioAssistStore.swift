import OpenCineAppKit
import MonitorPresentation
import OpenCineCameraControls
import OpenPocketViewCore
import MonitorUI
import SwiftUI

extension AudioAssist {
    @MainActor static var store: MonitorAudioPreferenceStore { AssistPanelStores.app.audio }
}

extension AssistPanelStores {
    /// This app's assist panel settings, under its pre-existing key namespace.
    static let app = AssistPanelStores(storage: .standard, namespace: "OpenInstaCine")
}

extension WaveformAssist {
    @MainActor static var store: MonitorScopePanelStore<MonitorWaveformOptions> { AssistPanelStores.app.waveform }
}

extension ParadeAssist {
    @MainActor static var store: MonitorScopePanelStore<MonitorParadeOptions> { AssistPanelStores.app.parade }
}

extension VectorscopeAssist {
    @MainActor static var store: MonitorScopePanelStore<MonitorVectorscopeOptions> { AssistPanelStores.app.vectorscope }
}

extension HistogramAssist {
    @MainActor static var store: MonitorScopePanelStore<MonitorHistogramOptions> { AssistPanelStores.app.histogram }
}

extension TrafficLightsAssist {
    @MainActor static var store: MonitorTrafficLightsPreferenceStore { AssistPanelStores.app.trafficLights }
}

extension MonitorScopePanelStore where Options == MonitorWaveformOptions {
    convenience init(options: MonitorWaveformOptions = .default) {
        self.init(options: options, storage: .standard, key: "OpenInstaCine.WaveformAssist.v1")
    }
}

extension MonitorScopePanelStore where Options == MonitorParadeOptions {
    convenience init(options: MonitorParadeOptions = .default) {
        self.init(options: options, storage: .standard, key: "OpenInstaCine.ParadeAssist.v1")
    }
}

extension MonitorScopePanelStore where Options == MonitorVectorscopeOptions {
    convenience init(options: MonitorVectorscopeOptions = .default) {
        self.init(options: options, storage: .standard, key: "OpenInstaCine.VectorscopeAssist.v1")
    }
}

extension MonitorScopePanelStore where Options == MonitorHistogramOptions {
    convenience init(options: MonitorHistogramOptions = .default) {
        self.init(options: options, storage: .standard, key: "OpenInstaCine.HistogramAssist.v1")
    }
}
