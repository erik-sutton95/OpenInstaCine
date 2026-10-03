import OpenCineAppKit
import MonitorPresentation
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

    @MainActor static var store: AudioAssistStore { AudioAssistStore.shared }
}

typealias AudioAssistStore = MonitorAudioPreferenceStore

// The app selects its storage domain and keeps each pre-existing namespace.
@MainActor private enum InstaAssistStores {
    static let waveform = MonitorScopePanelStore<MonitorWaveformOptions>(storage: .standard, key: "OpenInstaCine.WaveformAssist.v1")
    static let parade = MonitorScopePanelStore<MonitorParadeOptions>(storage: .standard, key: "OpenInstaCine.ParadeAssist.v1")
    static let vectorscope = MonitorScopePanelStore<MonitorVectorscopeOptions>(storage: .standard, key: "OpenInstaCine.VectorscopeAssist.v1")
    static let histogram = MonitorScopePanelStore<MonitorHistogramOptions>(storage: .standard, key: "OpenInstaCine.HistogramAssist.v1")
    static let audio = MonitorAudioPreferenceStore(storage: .standard, key: "OpenInstaCine.Assist.audio.v1")
    static let reference = MonitorFalseColorReferencePositionStore(storage: .standard, key: "OpenInstaCine.Assist.falseColorReference.positions.v1")
    static let nd = MonitorNDPreferenceStore(storage: .standard, key: "OpenInstaCine.Assist.ndMeter.v1")
    static let lights = MonitorTrafficLightsPreferenceStore(storage: .standard,
        key: "OpenInstaCine.Assist.trafficLights.v1", histogram: histogram)
}

extension MonitorScopePanelStore where Options == MonitorWaveformOptions {
    static var shared: MonitorScopePanelStore<MonitorWaveformOptions> { InstaAssistStores.waveform }
    convenience init(options: MonitorWaveformOptions = .default) {
        self.init(options: options, storage: .standard, key: "OpenInstaCine.WaveformAssist.v1")
    }
    static func load() -> MonitorWaveformOptions {
        load(storage: .standard, key: "OpenInstaCine.WaveformAssist.v1")
    }
}

extension MonitorScopePanelStore where Options == MonitorParadeOptions {
    static var shared: MonitorScopePanelStore<MonitorParadeOptions> { InstaAssistStores.parade }
    convenience init(options: MonitorParadeOptions = .default) {
        self.init(options: options, storage: .standard, key: "OpenInstaCine.ParadeAssist.v1")
    }
    static func load() -> MonitorParadeOptions {
        load(storage: .standard, key: "OpenInstaCine.ParadeAssist.v1")
    }
}

extension MonitorScopePanelStore where Options == MonitorVectorscopeOptions {
    static var shared: MonitorScopePanelStore<MonitorVectorscopeOptions> { InstaAssistStores.vectorscope }
    convenience init(options: MonitorVectorscopeOptions = .default) {
        self.init(options: options, storage: .standard, key: "OpenInstaCine.VectorscopeAssist.v1")
    }
    static func load() -> MonitorVectorscopeOptions {
        load(storage: .standard, key: "OpenInstaCine.VectorscopeAssist.v1")
    }
}

extension MonitorScopePanelStore where Options == MonitorHistogramOptions {
    static var shared: MonitorScopePanelStore<MonitorHistogramOptions> { InstaAssistStores.histogram }
    convenience init(options: MonitorHistogramOptions = .default) {
        self.init(options: options, storage: .standard, key: "OpenInstaCine.HistogramAssist.v1")
    }
    static func load() -> MonitorHistogramOptions {
        load(storage: .standard, key: "OpenInstaCine.HistogramAssist.v1")
    }
}

extension MonitorAudioPreferenceStore {
    static var shared: MonitorAudioPreferenceStore { InstaAssistStores.audio }
    convenience init(defaults: UserDefaults = .standard, key: String = "OpenInstaCine.Assist.audio.v1") {
        self.init(storage: defaults, key: key)
    }
}
extension MonitorFalseColorReferencePositionStore {
    static var shared: MonitorFalseColorReferencePositionStore { InstaAssistStores.reference }
    convenience init(defaults: UserDefaults = .standard) {
        self.init(storage: defaults, key: "OpenInstaCine.Assist.falseColorReference.positions.v1")
    }
}
extension MonitorNDPreferenceStore {
    static var shared: MonitorNDPreferenceStore { InstaAssistStores.nd }
    convenience init() { self.init(storage: .standard, key: "OpenInstaCine.Assist.ndMeter.v1") }
}
extension MonitorTrafficLightsPreferenceStore {
    static var shared: MonitorTrafficLightsPreferenceStore { InstaAssistStores.lights }
    convenience init() {
        self.init(storage: .standard, key: "OpenInstaCine.Assist.trafficLights.v1",
            histogram: HistogramAssist.store)
    }
}
