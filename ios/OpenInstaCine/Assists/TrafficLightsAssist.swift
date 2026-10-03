import MonitorUI
import OpenPocketViewCore
import SwiftUI
import UIKit

/// OpenZCine Traffic Lights — `AssistQuickSettingsContent.trafficLightsRows` plus
/// `MovablePanel(id: "traffic-lights")` (direct drag + corner resize).
///
/// Long-press options are **only** Crush/Clip Compensation (0 / 0.25 / 0.5 / 0.75 / 1.0 stops).
/// That value is shared with the histogram's edge lights. The floating meter is the
/// RED-style RGB goal-post (`TrafficLightsMeterMini`): `TL` title, three centre-anchored
/// columns, clip lamps on top, crush lamps on the floor. Draggable immediately
/// and uniformly scalable 0.6…1.6 from the bottom-trailing grip.
enum TrafficLightsAssist {
    static let panelID = "traffic-lights"
    static let baseSize = CGSize(width: 74, height: 168)
    static let scaleRange: ClosedRange<Double> = 0.6...1.6
    static let defaultScale = 1.0
    static let defaultCompensation = CrushClipCompensation.zero
    static let compensationTitle = "Crush/Clip Compensation"
    static let compensationHelp =
        "Stops of crush/clip tolerance before a channel indicator glows. Shared with the histogram traffic lights."

    static let holdDuration: Double = 0.3
    static let positionGrid: CGFloat = 4
    static let hapticGrid: CGFloat = 22
    static let dragHitPadding: CGFloat = 10
    static let gripHitSize: CGFloat = 56
    static let gripVisualSize: CGFloat = 14
    static let gripExteriorGap: CGFloat = 2

    /// OpenZCine `TrafficLightsMeterMini` chrome — 74×168 landscape box.
    static let meterTitle = MonitorTrafficLightsGeometry.meterTitle
    static let accessibilityTitle = MonitorTrafficLightsGeometry.accessibilityTitle
    static let titleSize = MonitorTrafficLightsGeometry.titleSize
    static let titleSpacing = MonitorTrafficLightsGeometry.titleSpacing
    static let columnSpacing = MonitorTrafficLightsGeometry.columnSpacing
    static let postSpacing = MonitorTrafficLightsGeometry.postSpacing
    static let panelPad = MonitorTrafficLightsGeometry.panelPad
    static let trackWidth = MonitorTrafficLightsGeometry.trackWidth
    static let columnHeight = MonitorTrafficLightsGeometry.columnHeight
    static let indicatorSize = MonitorTrafficLightsGeometry.indicatorSize
    static let fillsWidthMaxColumn = MonitorTrafficLightsGeometry.fillsWidthMaxColumn
    static let trackCorner = MonitorTrafficLightsGeometry.trackCorner
    static let minBarHeight = MonitorTrafficLightsGeometry.minBarHeight
    static let centerLineFactor = MonitorTrafficLightsGeometry.centerLineFactor
    static let segmentMinWidth: CGFloat = 46
    static let segmentMinHeight: CGFloat = 34
    static let meterRedRGB = MonitorTrafficLightsGeometry.meterRedRGB
    static let meterGreenRGB = MonitorTrafficLightsGeometry.meterGreenRGB
    static let meterBlueRGB = MonitorTrafficLightsGeometry.meterBlueRGB
    static let leanBalanced = MonitorTrafficLightsGeometry.leanBalanced
    static let leanOver = MonitorTrafficLightsGeometry.leanOver
    static let leanUnder = MonitorTrafficLightsGeometry.leanUnder
    static let flagClip = MonitorTrafficLightsGeometry.flagClip
    static let flagCrush = MonitorTrafficLightsGeometry.flagCrush
    static let channelNames = MonitorTrafficLightsGeometry.channelNames

    /// OpenZCine `TrafficLightsMeter.balanceCenter` / `balanceDeadZone`.
    static let balanceCenter = MonitorTrafficLightsGeometry.balanceCenter
    static let balanceDeadZone = MonitorTrafficLightsGeometry.balanceDeadZone

    /// OpenZCine `AssistConfiguration.CrushClipCompensation`.
    enum CrushClipCompensation: Int, CaseIterable, Codable, Equatable, Sendable, Identifiable {
        case zero = 0
        case quarter = 2
        case half = 5
        case threeQuarter = 7
        case one = 10

        var id: Int { rawValue }

        /// Operator-facing label in stops (OpenZCine `label`).
        var label: String {
            switch self {
            case .zero: "0"
            case .quarter: "0.25"
            case .half: "0.5"
            case .threeQuarter: "0.75"
            case .one: "1.0"
            }
        }

        /// In-app compact glyphs (OpenZCine `compactLabel`).
        var compactLabel: String {
            switch self {
            case .zero: "0"
            case .quarter: "¼"
            case .half: "½"
            case .threeQuarter: "¾"
            case .one: "1"
            }
        }

        var stops: Double {
            switch self {
            case .zero: 0
            case .quarter: 0.25
            case .half: 0.5
            case .threeQuarter: 0.75
            case .one: 1.0
            }
        }

        /// Fraction of channel energy in the crush/clip band required to light a lamp.
        /// Each quarter-stop adds 2.5 percentage points (0 → 0%, 1.0 → 10%).
        var pixelFractionThreshold: Double { stops / 10.0 }

        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(Int.self)
            self = CrushClipCompensation(rawValue: raw) ?? (raw > 10 ? .one : .zero)
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(rawValue)
        }
    }

    /// OpenZCine `TrafficLightsBarSide` — which half of a goal-post shows fill.
    typealias BarSide = MonitorTrafficLightsGeometry.BarSide

    /// OpenZCine `TrafficLightsChannelDisplay` — display transform only (not IRE).
    typealias ChannelDisplay = MonitorTrafficLightsGeometry.ChannelDisplay

    /// OpenZCine `TrafficLightsMeter.channelDisplay` — centre-anchored single-sided fill.
    static func channelDisplay(
        for channel: ScopeChannelLight,
        balanceCenter center: Double = balanceCenter,
        deadZone: Double = balanceDeadZone
    ) -> ChannelDisplay {
        MonitorTrafficLightsGeometry.channelDisplay(for: channel, balanceCenter: center, deadZone: deadZone)
    }

    static func channelDisplay(
        level: Double,
        balanceCenter center: Double = balanceCenter,
        deadZone: Double = balanceDeadZone
    ) -> ChannelDisplay {
        MonitorTrafficLightsGeometry.channelDisplay(level: level, balanceCenter: center, deadZone: deadZone)
    }

    /// OpenZCine `TrafficLightsMeterMini` column width — 11pt locked, or spread when `fillsWidth`.
    static func columnWidth(fillsWidth: Bool, panelWidth: CGFloat, uiScale: CGFloat) -> CGFloat {
        MonitorTrafficLightsGeometry.columnWidth(fillsWidth: fillsWidth, panelWidth: panelWidth, uiScale: uiScale)
    }

    static func meterColor(_ rgb: (Double, Double, Double)) -> Color {
        MonitorTrafficLightsGeometry.meterColor(rgb)
    }

    /// OpenZCine `trafficLightsAccessibilityValue`.
    static func accessibilityValue(for reading: ScopeTrafficLightsReading) -> String {
        MonitorTrafficLightsGeometry.accessibilityValue(for: reading)
    }

    /// Normalized centre — OpenZCine `MovablePanelStoredCenter`.
    typealias StoredCenter = MonitorScopeStoredCenter

    static func clampedScale(_ value: Double) -> Double {
        min(max(value, scaleRange.lowerBound), scaleRange.upperBound)
    }

    static func panelSize(scale: Double) -> CGSize {
        let clamped = clampedScale(scale)
        return CGSize(
            width: (baseSize.width * clamped).rounded(),
            height: (baseSize.height * clamped).rounded())
    }

    /// Unplaced tools start at the canvas center; saved/session centers win later.
    static func defaultCenter(
        feed _: CGRect,
        size: CGSize,
        bounds: CGRect,
        chromeClearance _: EdgeInsets,
        gap _: CGFloat = 10
    ) -> CGPoint {
        clamp(
            CGPoint(x: bounds.midX, y: bounds.midY), size: size, in: bounds)
    }

    static func clamp(_ point: CGPoint, size: CGSize, in bounds: CGRect) -> CGPoint {
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
        session: CGPoint? = nil,
        stored: StoredCenter?,
        defaultCenter: CGPoint,
        size: CGSize,
        bounds: CGRect
    ) -> CGPoint {
        if let session { return clamp(session, size: size, in: bounds) }
        let raw = stored?.center(in: bounds) ?? defaultCenter
        return clamp(raw, size: size, in: bounds)
    }

    /// OpenZCine keeps one `scopes.crushClipCompensation` for histogram + goal-post.
    @MainActor
    static var store: TrafficLightsAssistStore { TrafficLightsAssistStore.shared }

    @MainActor
    static func sharedCompensation() -> CrushClipCompensation {
        CrushClipCompensation(
            rawValue: HistogramAssist.store.options.crushClipCompensation.rawValue)
            ?? store.compensation
    }

    @MainActor
    static func setSharedCompensation(_ value: CrushClipCompensation) {
        store.compensation = value
        if let histo = HistogramAssist.CrushClipCompensation(rawValue: value.rawValue) {
            HistogramAssist.store.options.crushClipCompensation = histo
        }
    }

    @MainActor
    static func longPressMenu(assist: LiveAssistState, compact: Bool = false)
        -> TrafficLightsLongPressMenu
    {
        TrafficLightsLongPressMenu(assist: assist, compact: compact)
    }

    @MainActor
    static func longPressMenu(_ assist: LiveAssistState) -> TrafficLightsLongPressMenu {
        longPressMenu(assist: assist)
    }

    fileprivate struct Snapshot: Codable {
        var compensation: CrushClipCompensation
        var scale: Double
        var position: StoredCenter?
        var positionPortrait: StoredCenter?
    }
}

@MainActor
@Observable
final class TrafficLightsAssistStore {
    static let shared = TrafficLightsAssistStore()
    fileprivate static let prefsKey = "OpenInstaCine.Assist.trafficLights.v1"

    var compensation: TrafficLightsAssist.CrushClipCompensation
    var scale: Double
    var position: TrafficLightsAssist.StoredCenter?
    var positionPortrait: TrafficLightsAssist.StoredCenter?
    var sessionCenter: CGPoint?
    var sessionCenterPortrait: CGPoint?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.prefsKey),
            let snap = try? JSONDecoder().decode(TrafficLightsAssist.Snapshot.self, from: data)
        {
            compensation = snap.compensation
            scale = TrafficLightsAssist.clampedScale(snap.scale)
            position = snap.position
            positionPortrait = snap.positionPortrait
        } else if let shared = TrafficLightsAssist.CrushClipCompensation(
            rawValue: HistogramAssist.store.options.crushClipCompensation.rawValue)
        {
            compensation = shared
            scale = TrafficLightsAssist.defaultScale
            position = nil
            positionPortrait = nil
        } else {
            compensation = TrafficLightsAssist.defaultCompensation
            scale = TrafficLightsAssist.defaultScale
            position = nil
            positionPortrait = nil
        }
        if let histo = HistogramAssist.CrushClipCompensation(rawValue: compensation.rawValue) {
            HistogramAssist.store.options.crushClipCompensation = histo
        }
    }

    func persist() {
        let snap = TrafficLightsAssist.Snapshot(
            compensation: compensation,
            scale: TrafficLightsAssist.clampedScale(scale),
            position: position,
            positionPortrait: positionPortrait)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        UserDefaults.standard.set(data, forKey: Self.prefsKey)
    }
}

// MARK: - Long-press rows

struct TrafficLightsLongPressMenu: View {
    var assist: LiveAssistState
    var compact: Bool = false

    var body: some View {
        SettingsInlineRow(
            title: TrafficLightsAssist.compensationTitle,
            help: TrafficLightsAssist.compensationHelp,
            showTopDivider: false,
            stacked: compact
        ) {
            TrafficLightsCrushClipSegmented(
                selected: TrafficLightsAssist.sharedCompensation(),
                compact: compact
            ) { match in
                guard match != TrafficLightsAssist.sharedCompensation() else { return }
                TrafficLightsAssistHaptics.selection()
                TrafficLightsAssist.setSharedCompensation(match)
                assist.crushClipCompensation = match
                assist.persist()
                TrafficLightsAssist.store.persist()
            }
        }
    }
}

/// OpenZCine `SettingsCrushClipSegmented` — fraction glyphs, 46×34 floor, full stop in VoiceOver.
private struct TrafficLightsCrushClipSegmented: View {
    let selected: TrafficLightsAssist.CrushClipCompensation
    var compact: Bool = false
    let onSelect: (TrafficLightsAssist.CrushClipCompensation) -> Void

    var body: some View {
        HStack(spacing: 4) {
            MonitorSnapshotRows(TrafficLightsAssist.CrushClipCompensation.allCases) { option in
                let active = option == selected
                Button {
                    onSelect(option)
                } label: {
                    Text(option.compactLabel)
                        .font(
                            LiveType.ui(
                                size: compact ? 12 : 11, weight: active ? .semibold : .medium)
                        )
                        .foregroundStyle(active ? LiveDesign.text : LiveDesign.muted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(
                            minWidth: TrafficLightsAssist.segmentMinWidth,
                            minHeight: TrafficLightsAssist.segmentMinHeight
                        )
                        .background(
                            active ? LiveDesign.surface : Color.clear,
                            in: RoundedRectangle(
                                cornerRadius: DesignTokens.cornerRadius, style: .continuous))
                }
                .buttonStyle(.zcTapTarget)
                .accessibilityLabel(option.label)
            }
        }
        .padding(4)
        .background(
            LiveDesign.background.opacity(0.5),
            in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                .stroke(LiveDesign.hairline, lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
    }
}

private enum TrafficLightsAssistHaptics {
    @MainActor
    static func selection() {
        OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
    }
}

// MARK: - Movable panel (OpenZCine `MovablePanel`)

/// Drag to reposition; drag the corner grip to scale.
struct TrafficLightsMovablePanel<Content: View>: View {
    @Bindable var store: TrafficLightsAssistStore
    let size: CGSize
    let defaultCenter: CGPoint
    let bounds: CGRect
    var placementBounds: CGRect? = nil
    @ViewBuilder var content: () -> Content
    @State private var sessionCenter: CGPoint?
    @State private var sessionCenterPortrait: CGPoint?
    var body: some View {
        let movement = placementBounds ?? ScopePanelPlacement.bounds(in: bounds)
        let center = TrafficLightsAssist.resolvedCenter(
            session: ScopeCanvasSlot.pick(sessionCenter, sessionCenterPortrait, in: bounds),
            stored: ScopeCanvasSlot.pick(store.position, store.positionPortrait, in: bounds),
            defaultCenter: defaultCenter, size: size, bounds: bounds)
        MonitorMovableScopePanel(layout: MonitorScopePanelLayout(baseSize: TrafficLightsAssist.baseSize,
            preferredSize: size, center: center, scale: store.scale, canvas: bounds, movementBounds: movement),
            resizeLabel: "Resize traffic lights",
            onMove: { event in
                switch event {
                case .began: break
                case .cancelled(let retiredCanvas):
                    ScopeCanvasSlot.assign(&sessionCenter, &sessionCenterPortrait, in: retiredCanvas, nil)
                case .changed(let center):
                    ScopeCanvasSlot.assign(&sessionCenter, &sessionCenterPortrait, in: bounds, center)
                case .ended:
                    guard let center = ScopeCanvasSlot.pick(sessionCenter, sessionCenterPortrait, in: bounds) else { return }
                    let stored = TrafficLightsAssist.StoredCenter(center: center, in: bounds)
                    if ScopeCanvasSlot.forBounds(bounds) == .portrait { store.positionPortrait = stored }
                    else { store.position = stored }
                    store.persist()
                }
            }, onResize: { store.scale = TrafficLightsAssist.clampedScale($0) },
            onResizeEnded: { store.persist() }, content: content)
    }
}
