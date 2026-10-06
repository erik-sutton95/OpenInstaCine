import OpenCineAppKit
import MonitorPresentation
import OpenCineCameraControls
import OpenPocketViewCore
import MonitorUI
import SwiftUI

/// Presentation preferences only. Meter values and peak hold remain the camera's.
extension AudioAssist {
    typealias Orientation = MonitorAudioOrientation

    typealias StoredCenter = MonitorAudioStoredCenter

    typealias Options = MonitorAudioOptions

    static func panelSize(orientation: Orientation) -> CGSize {
        MonitorAudioMetrics.panelSize(orientation: orientation)
    }

    static func levelFraction(_ db: Double) -> Double {
        MonitorAudioReadout.fraction(db)
    }

    static func dbText(_ db: Double) -> String {
        MonitorAudioReadout.label(db)
    }

    static func center(
        stored: StoredCenter?, size: CGSize, canvas: CGRect, movement: CGRect
    ) -> CGPoint {
        let fallback = CGPoint(x: movement.minX + size.width / 2, y: canvas.midY)
        let point = stored?.point(in: canvas) ?? fallback
        let minX = movement.minX + size.width / 2
        let minY = movement.minY + size.height / 2
        return CGPoint(
            x: min(max(minX, point.x), max(minX, movement.maxX - size.width / 2)),
            y: min(max(minY, point.y), max(minY, movement.maxY - size.height / 2)))
    }

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

extension MonitorAudioPreferenceStore {
    convenience init(defaults: UserDefaults = .standard, key: String = "OpenInstaCine.Assist.audio.v1") {
        self.init(storage: defaults, key: key)
    }
}

extension MonitorFalseColorReferencePositionStore {
    convenience init(defaults: UserDefaults = .standard) {
        self.init(storage: defaults, key: "OpenInstaCine.Assist.falseColorReference.positions.v1")
    }
}
