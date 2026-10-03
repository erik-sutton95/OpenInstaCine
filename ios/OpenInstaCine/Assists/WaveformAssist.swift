import MonitorPresentation
import MonitorUI
import SwiftUI
import UIKit

/// OpenZCine waveform operator options + `MovablePanel` (id `"wave"`).
///
/// Long-press toolbar rows (`AssistQuickSettingsContent.waveformRows`):
/// * Mode — Luma / RGB
/// * Brightness — 0…200% (default 100; OpenZCine `/400`, so 100% = 0.25)
/// * Safe Border Clip / Crush / Middle Gray
///
/// Size is the L-corner grip only (OpenZCine dropped Small/Medium/Large; no
/// Size slider in the popup). Scale is 0.6…1.6.
/// WAVE axis matches traffic lights: 0 = paper black, 100 = live-tap
/// ceiling, 18% gray at the log paper IRE (D-Log2 = 30.50). Dotted 5 / 95
/// are safe-border guides. Hold the panel (no drag) or long-press WAVE
/// on the assist bar to open options.
/// On the panel: 0.3s long-press then drag to reposition (4pt snap, 22pt haptic grid).
/// No pinch-resize — OpenZCine scales only from the L-corner grip.
enum WaveformAssist {
    static let panelID = "wave"
    static let baseSize = ScopePanelSize.waveform
    static let scaleRange: ClosedRange<Double> = 0.6...1.6
    static let defaultScale = 1.0
    static let brightnessRange: ClosedRange<Int> = 0...200
    static let defaultBrightness = 100
    static let holdDuration: Double = 0.3
    static let positionGrid: CGFloat = 4
    static let hapticGrid: CGFloat = 22
    static let dragHitPadding: CGFloat = 10
    static let gripHitSize: CGFloat = 56
    static let gripVisualSize: CGFloat = 14
    static let gripExteriorGap: CGFloat = 2

    static let brightnessHelp =
        "Raise trace intensity when the waveform is hard to read in bright light."

    typealias Mode = MonitorWaveformMode

    typealias GuideLines = MonitorScopeGuides

    /// OpenZCine `MovablePanelStoredCenter` — centre as a fraction of the overlay bounds.
    typealias StoredCenter = MonitorScopeStoredCenter

    struct Options: Equatable, Codable, Sendable {
        var mode: Mode
        var brightness: Int
        var guides: GuideLines
        var scale: Double
        /// False only for a fresh automatic size; legacy saved scales stay explicit.
        var hasCustomScale: Bool
        var storedCenter: StoredCenter?
        var storedCenterPortrait: StoredCenter?

        static let `default` = Options(
            mode: .rgb,
            brightness: defaultBrightness,
            guides: .default,
            scale: defaultScale,
            storedCenter: nil,
            storedCenterPortrait: nil)

        init(
            mode: Mode = .rgb,
            brightness: Int = defaultBrightness,
            guides: GuideLines = .default,
            scale: Double = defaultScale,
            hasCustomScale: Bool = false,
            storedCenter: StoredCenter? = nil,
            storedCenterPortrait: StoredCenter? = nil
        ) {
            self.mode = mode
            self.brightness = Self.clampedBrightness(brightness)
            self.guides = guides
            self.scale = Self.clampedScale(scale)
            self.hasCustomScale = hasCustomScale || scale != defaultScale
            self.storedCenter = storedCenter
            self.storedCenterPortrait = storedCenterPortrait
        }

        enum CodingKeys: String, CodingKey {
            case mode, brightness, guides, scale, hasCustomScale, storedCenter, storedCenterPortrait
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .rgb
            brightness = Self.clampedBrightness(
                try c.decodeIfPresent(Int.self, forKey: .brightness) ?? defaultBrightness)
            guides = try c.decodeIfPresent(GuideLines.self, forKey: .guides) ?? .default
            scale = Self.clampedScale(
                try c.decodeIfPresent(Double.self, forKey: .scale) ?? defaultScale)
            // Old JSON cannot distinguish an untouched 1.0 from a manual 1.0.
            // Preserve it rather than rewriting an operator's layout on upgrade.
            hasCustomScale =
                try c.decodeIfPresent(Bool.self, forKey: .hasCustomScale)
                ?? true
            storedCenter = try c.decodeIfPresent(StoredCenter.self, forKey: .storedCenter)
            storedCenterPortrait = try c.decodeIfPresent(
                StoredCenter.self, forKey: .storedCenterPortrait)
        }

        static func clampedScale(_ value: Double) -> Double {
            min(max(value, scaleRange.lowerBound), scaleRange.upperBound)
        }

        static func clampedBrightness(_ value: Int) -> Int {
            min(max(value, brightnessRange.lowerBound), brightnessRange.upperBound)
        }
    }

    /// OpenZCine `waveformParadeBrightnessMultiplier` — 100% = former 25%.
    static func intensity(_ brightness: Int) -> Double {
        Double(Options.clampedBrightness(brightness)) / 400
    }

    static func panelSize(scale: Double) -> CGSize {
        let clamped = Options.clampedScale(scale)
        return CGSize(
            width: (baseSize.width * clamped).rounded(),
            height: (baseSize.height * clamped).rounded())
    }

    /// Unplaced tools start at the canvas center; saved/session centers win later.
    static func defaultCenter(
        feed _: CGRect,
        size: CGSize,
        bounds: CGRect,
        chromeClearance _: EdgeInsets = EdgeInsets(),
        gap _: CGFloat = 10
    ) -> CGPoint {
        clamp(
            CGPoint(x: bounds.midX, y: bounds.midY), size: size, bounds: bounds)
    }

    static func clamp(_ point: CGPoint, size: CGSize, bounds: CGRect) -> CGPoint {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        return CGPoint(
            x: min(max(bounds.minX + halfWidth, point.x), bounds.maxX - halfWidth),
            y: min(max(bounds.minY + halfHeight, point.y), bounds.maxY - halfHeight))
    }

    static func snap(_ point: CGPoint, grid: CGFloat = positionGrid) -> CGPoint {
        CGPoint(
            x: (point.x / grid).rounded() * grid,
            y: (point.y / grid).rounded() * grid)
    }

    static func hapticCell(_ point: CGPoint, grid: CGFloat = hapticGrid) -> Int {
        Int((point.x / grid).rounded()) &* 100_000
            &+ Int((point.y / grid).rounded())
    }

    static func resolvedCenter(
        session: CGPoint?,
        stored: StoredCenter?,
        defaultCenter: CGPoint,
        size: CGSize,
        bounds: CGRect
    ) -> CGPoint {
        if let session { return clamp(session, size: size, bounds: bounds) }
        if let stored { return clamp(stored.center(in: bounds), size: size, bounds: bounds) }
        return clamp(defaultCenter, size: size, bounds: bounds)
    }

    @MainActor
    static var store: WaveformAssistStore { WaveformAssistStore.shared }

    /// OpenZCine `AssistQuickSettingsContent.waveformRows`.
    static func longPressMenu(
        options: Binding<Options>,
        compact: Bool = false
    ) -> WaveformLongPressMenu {
        WaveformLongPressMenu(options: options, compact: compact)
    }

    /// Binds the shared waveform store. Options live off `LiveAssistState` so
    /// parallel assist agents do not collide on that blob.
    @MainActor
    static func longPressMenu(
        assist: LiveAssistState,
        compact: Bool = false
    ) -> WaveformLongPressMenu {
        longPressMenu(options: store.optionsBinding, compact: compact)
    }

    @MainActor
    static func longPressMenu(_ assist: LiveAssistState) -> WaveformLongPressMenu {
        longPressMenu(assist: assist)
    }

    @MainActor
    static func longPressMenu() -> WaveformLongPressMenu {
        longPressMenu(options: store.optionsBinding)
    }

    /// Hold-without-drag on the WAVE panel, or long-press the WAVE chip.
    @MainActor
    static func presentOptions(anchor: CGRect, assist: LiveAssistState) {
        assist.longPressAnchor = anchor
        assist.configureTool = .waveform
    }

    static func shouldPresentOptions(translation: CGSize) -> Bool {
        WaveformAxis.shouldPresentOptions(translation: translation)
    }

    /// Direct drag + L-corner resize wrapper (OpenZCine `MovablePanel`).
    /// A hold that does not drag opens ``presentOptions``.
    static func overlay<Content: View>(
        canvas: CGRect,
        feed: CGRect,
        chromeClearance: EdgeInsets = EdgeInsets(),
        onOpenOptions: ((CGRect) -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> WaveformMovablePanel<Content> {
        WaveformMovablePanel(
            canvas: canvas, feed: feed, chromeClearance: chromeClearance,
            onOpenOptions: onOpenOptions, content: content)
    }
}

@MainActor
@Observable
final class WaveformAssistStore {
    static let shared = WaveformAssistStore(options: load())
    private static let defaultsKey = "OpenInstaCine.WaveformAssist.v1"

    var options: WaveformAssist.Options {
        didSet { persist() }
    }
    /// Session centre in canvas space (OpenZCine `movablePanelCenters["wave"]`).
    var sessionCenter: CGPoint?
    var sessionCenterPortrait: CGPoint?

    var optionsBinding: Binding<WaveformAssist.Options> {
        Binding(
            get: { self.options },
            set: { self.options = $0 }
        )
    }

    init(options: WaveformAssist.Options = .default) {
        self.options = options
    }

    static func load() -> WaveformAssist.Options {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode(WaveformAssist.Options.self, from: data)
        else { return .default }
        return decoded
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(options) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    func setScale(_ scale: Double) {
        var next = options
        next.scale = WaveformAssist.Options.clampedScale(scale)
        next.hasCustomScale = true
        options = next
    }

    /// Plot, hit frame and resize origin all consume the same effective size.
    func presentationScale(
        in bounds: CGRect, tablet: Bool? = nil
    ) -> Double {
        guard bounds.width > 1, bounds.height > 1 else { return options.scale }
        return MonitorScopeSizing.scale(
            portrait: bounds.height > bounds.width,
            tablet: tablet ?? (UIDevice.current.userInterfaceIdiom == .pad),
            preferred: options.hasCustomScale ? options.scale : nil)
    }

    func sessionCenter(in bounds: CGRect) -> CGPoint? {
        ScopeCanvasSlot.pick(sessionCenter, sessionCenterPortrait, in: bounds)
    }

    func storedCenter(in bounds: CGRect) -> WaveformAssist.StoredCenter? {
        ScopeCanvasSlot.pick(options.storedCenter, options.storedCenterPortrait, in: bounds)
    }

    func beginDrag(center: CGPoint, in bounds: CGRect) {
        ScopeCanvasSlot.assign(&sessionCenter, &sessionCenterPortrait, in: bounds, center)
    }

    func drag(to center: CGPoint, in bounds: CGRect) {
        beginDrag(center: center, in: bounds)
    }

    func cancelDrag(bounds: CGRect) {
        ScopeCanvasSlot.assign(&sessionCenter, &sessionCenterPortrait, in: bounds, nil)
    }

    func endDrag(bounds: CGRect) {
        guard let center = sessionCenter(in: bounds) else { return }
        var next = options
        let stored = WaveformAssist.StoredCenter(center: center, in: bounds)
        if ScopeCanvasSlot.forBounds(bounds) == .portrait {
            next.storedCenterPortrait = stored
        } else {
            next.storedCenter = stored
        }
        options = next
    }
}

/// OpenZCine `AssistQuickSettingsContent.waveformRows`.
struct WaveformLongPressMenu: View {
    @Binding var options: WaveformAssist.Options
    var compact: Bool = false
    var body: some View {
        MonitorScopeTraceMenu(modes: WaveformAssist.Mode.allCases, mode: $options.mode,
            brightness: Binding(get: { options.brightness }, set: {
                let next = WaveformAssist.Options.clampedBrightness($0)
                guard next != options.brightness else { return }
                WaveformAssistHaptics.selection(); options.brightness = next
            }), guides: $options.guides, title: { $0.rawValue },
            brightnessHelp: WaveformAssist.brightnessHelp, brightnessRange: WaveformAssist.brightnessRange,
            compact: compact, modeFeedback: {
                OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
            }, guideFeedback: { WaveformAssistHaptics.selection() })
            .buttonStyle(.zcTapTarget)
    }
}

struct WaveformMovablePanel<Content: View>: View {
    let canvas: CGRect
    let feed: CGRect
    var chromeClearance: EdgeInsets = EdgeInsets()
    var onOpenOptions: ((CGRect) -> Void)? = nil
    @ViewBuilder var content: () -> Content
    @Environment(\.interfaceLocked) private var interfaceLocked
    private var store: WaveformAssistStore { WaveformAssist.store }
    var body: some View {
        let bounds = ScopePanelPlacement.bounds(in: canvas, clearance: chromeClearance)
        let scale = store.presentationScale(in: canvas)
        let preferred = WaveformAssist.panelSize(scale: scale)
        let size = ScopePanelPlacement.fittedSize(preferred, in: bounds)
        let fallback = WaveformAssist.defaultCenter(
            feed: feed, size: size, bounds: canvas, chromeClearance: chromeClearance)
        let center = WaveformAssist.resolvedCenter(session: store.sessionCenter(in: canvas),
            stored: store.storedCenter(in: canvas), defaultCenter: fallback, size: size, bounds: canvas)
        MonitorMovableScopePanel(layout: MonitorScopePanelLayout(baseSize: WaveformAssist.baseSize,
            preferredSize: preferred, center: center, scale: scale, canvas: canvas, movementBounds: bounds),
            enabled: !interfaceLocked, resizeLabel: "Resize waveform",
            onMove: { event in
                switch event {
                case .began(let center): store.beginDrag(center: center, in: canvas)
                case .changed(let center): store.drag(to: center, in: canvas)
                case .ended: store.endDrag(bounds: canvas)
                case .cancelled(let retiredCanvas): store.cancelDrag(bounds: retiredCanvas)
                }
            }, onResize: { store.setScale($0) },
            onOpenOptions: onOpenOptions, onConfirm: { WaveformAssistHaptics.confirm() }, content: content)
    }
}



/// OpenZCine `OperatorSettingsHaptics.selection`.
private enum WaveformAssistHaptics {
    @MainActor
    static func selection() {
        OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
    }

    @MainActor
    static func confirm() {
        guard OperatorPrefs.hapticsEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 1.0)
    }
}
