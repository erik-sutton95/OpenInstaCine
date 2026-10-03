import MonitorUI
import OpenPocketViewCore
import OpenCineMedia
import SwiftUI

/// OpenZCine `ScopePalette` — additive trace colours shared by WAVE / PARADE / HISTO / VECTOR.
typealias ScopePalette = MonitorUI.MonitorScopePalette

/// Landscape and portrait keep independent stored centres.
enum ScopeCanvasSlot: String, Sendable {
    case landscape
    case portrait

    static func forBounds(_ bounds: CGRect) -> Self {
        bounds.height > bounds.width ? .portrait : .landscape
    }

    static func pick<T>(_ landscape: T?, _ portrait: T?, in bounds: CGRect) -> T? {
        switch forBounds(bounds) {
        case .portrait: portrait
        case .landscape: landscape
        }
    }

    static func assign<T>(
        _ landscape: inout T?, _ portrait: inout T?, in bounds: CGRect, _ value: T?
    ) {
        switch forBounds(bounds) {
        case .portrait: portrait = value
        case .landscape: landscape = value
        }
    }
}

enum ScopePanelSize {
    static let waveform = CGSize(width: 250, height: 153)
    static let parade = CGSize(width: 250, height: 153)
    static let histogram = CGSize(width: 250, height: 77)
    static let vectorscope = CGSize(width: 190, height: 190)
    static let trafficLights = CGSize(width: 74, height: 168)
    /// Compact HUD chip (ND number + stops), not a scope plate.
    static let ndMeter = CGSize(width: 84, height: 30)
}

/// Display level from `ScopeDisplayScale` → y inside `rect`.
///
/// Legacy 4% top/bottom stretch (`crushLevel`…`clipLevel`). WAVE / PARADE /
/// HISTO use ``WaveformAxis`` instead. LIGHTS still sits on this scale.
func scopeLevelY(_ level: Double, _ rect: CGRect) -> CGFloat {
    let lo = ScopeDisplayScale.crushLevel
    let hi = ScopeDisplayScale.clipLevel
    let t = (level - lo) / (hi - lo)
    return rect.maxY - CGFloat(0.04 + t * 0.92) * rect.height
}

/// WAVE plot: same IRE numbers as traffic lights / ``ScopeDisplayScale.monitorPercent``.
/// 0 = paper black, 100 = live-tap EI ceiling, 18% gray stays at paper IRE
/// (D-Log2 = 30.50) — not remapped to 50. The plot uses the full panel under
/// the title so 0 / 100 sit on the min / max edges (the old 8pt chrome pad
/// was the ~5% empty band under the floor).
typealias WaveformAxis = MonitorUI.MonitorWaveformAxis

/// Y of a 0…100 scale line (crush/clip anchors after the stretch).
func scopeScaleLineY(_ scaleIRE: Double, _ rect: CGRect) -> CGFloat {
    scopeLevelY(ScopeDisplayScale.level(scaleIRE: scaleIRE), rect)
}

/// WAVE / PARADE tick Y for one native tap byte (`byte/255` = encoded curve
/// fraction), placed through the transfer's anchored level table on the source's
/// `clipByte`. Hot loops hoist `ScopeDisplayScale.levelTable(for:clipByte:)` once and
/// call ``scopeLevelY``.
func scopeTraceLevelY(
    _ byte: UInt8, transfer: MonitorTransfer = .rec709, clipByte: Int, _ rect: CGRect
) -> CGFloat {
    scopeLevelY(
        Double(ScopeDisplayScale.levelTable(for: transfer, clipByte: clipByte)[Int(byte)]), rect)
}

func scopePlotRect(_ size: CGSize, top: CGFloat) -> CGRect {
    CGRect(x: 6, y: top, width: size.width - 12, height: size.height - top - 8)
}

/// OpenZCine `ScopeMini` vectorscope square — centred in `scopePlotRect(..., top: 26)`.
func vectorscopePlotSquare(in size: CGSize) -> CGRect {
    let plot = scopePlotRect(size, top: 26)
    let side = min(plot.width, plot.height)
    return CGRect(
        x: plot.midX - side / 2, y: plot.midY - side / 2, width: side, height: side)
}

/// Full plot plus 2pt so origin-anchored 1–2px ticks on the 0 / 100 lines
/// are not scissored off the line (OpenZCine Metal has no scissor).
func scopeTraceClipRect(_ plot: CGRect) -> CGRect {
    plot.insetBy(dx: 0, dy: -2)
}

extension MonitorTransfer {
    /// Scope panel chip label (OpenZCine `ScopeMini` chrome).
    var scopeChip: String {
        switch self {
        case .rec709: "709"
        case .hdr: "HLG"
        case .dlog: "DLOG"
        case .dlogm: "DLM ≈"
        case .dlog2: "DL2"
        case .ilog: "ILOG"
        }
    }
}

/// BT.709 chroma used by BOTH the vectorscope trace binning and the graticule
/// targets — one function so plot and targets can never disagree.
/// OpenZCine `VectorscopeSampler.chroma` / `VectorscopeColor.traceTint`.
typealias ScopeChroma = OpenCineMedia.ScopeChroma

/// OpenZCine `drawVectorscopeGraticule` constants — outer ring, crosshair,
/// I-phase skin line at 123°, six 75% SMPTE boxes. Always on (no popup toggle).
typealias VectorscopeGraticule = MonitorVectorscopeGraticule

// MARK: - WAVE

struct WaveformOverlay: View {
    @Environment(AppModel.self) private var model
    var canvas: CGRect = .zero
    var feed: CGRect = .zero
    var chromeClearance: EdgeInsets = EdgeInsets()

    var body: some View {
        let options = WaveformAssist.store.options
        let size = ScopePanelPlacement.size(
            WaveformAssist.panelSize(scale: WaveformAssist.store.presentationScale(in: canvas)),
            canvas: canvas, clearance: chromeClearance)
        let intensity = WaveformAssist.intensity(options.brightness)
        let plot = ScopeMiniChrome(
            title: "Wave", chip: options.mode.rawValue.uppercased(),
            size: size
        ) {
            ScopeBundleScope { assist in
                // Transfer rides the bundle — reading session.status here re-rendered
                // every scope on 5 Hz telemetry pushes (DESIGN §2.3).
                let transfer = assist.transfer
                // Traces first; 0 / 100 and the dotted 5 / 95 buffers sit on top.
                MonitorWaveformScopePlot(samples: assist.samples, trail: assist.trailSamples,
                    mode: .waveform(options.mode), transfer: transfer, clipByte: assist.clipByte,
                    revision: assist.revision, intensity: intensity,
                    guides: MonitorScopeGuides(clip: options.guides.clip, crush: options.guides.crush,
                        middle: options.guides.middle), size: size, configureDisplay: scopeDisplay)
            }
        }
        .accessibilityLabel(options.mode == .rgb ? "RGB waveform" : "Luma waveform")
        if canvas.width > 1, canvas.height > 1 {
            WaveformAssist.overlay(
                canvas: canvas, feed: feed, chromeClearance: chromeClearance,
                onOpenOptions: { frame in
                    WaveformAssist.presentOptions(anchor: frame, assist: model.assist)
                }, content: { plot })
        } else {
            plot
        }
    }
}

/// Solid 0 / 100 on the plot edges. Dotted 5 / 95 safe borders. Solid middle
/// gray at the log paper IRE (not 50).


// MARK: - PARADE

struct ParadeOverlay: View {
    @Environment(AppModel.self) private var model
    var canvas: CGRect = .zero
    var feed: CGRect = .zero
    var chromeClearance: EdgeInsets = EdgeInsets()

    var body: some View {
        let options = ParadeAssist.store.options
        let size = ScopePanelPlacement.size(
            ParadeAssist.panelSize(scale: ParadeAssist.store.presentationScale(in: canvas)),
            canvas: canvas, clearance: chromeClearance)
        let intensity = ParadeAssist.intensity(options.brightness)
        let plot = ScopeMiniChrome(
            title: "Parade",
            chip: ParadeAssist.chip(options.mode),
            size: size
        ) {
            ScopeBundleScope { assist in
                let transfer = assist.transfer
                MonitorWaveformScopePlot(samples: assist.samples, trail: assist.trailSamples,
                    mode: .parade(options.mode), transfer: transfer, clipByte: assist.clipByte,
                    revision: assist.revision, intensity: intensity,
                    guides: MonitorScopeGuides(clip: options.guides.clip, crush: options.guides.crush,
                        middle: options.guides.middle), size: size, configureDisplay: scopeDisplay)
            }
        }
        .accessibilityLabel(ParadeAssist.accessibilityLabel(options.mode))
        if canvas.width > 1, canvas.height > 1 {
            ParadeAssist.overlay(
                canvas: canvas, feed: feed, chromeClearance: chromeClearance
            ) {
                plot
            }
        } else {
            plot
        }
    }
}

// MARK: - HISTO

struct HistogramOverlay: View {
    @Environment(AppModel.self) private var model
    var canvas: CGRect = .zero
    var feed: CGRect = .zero
    var chromeClearance: EdgeInsets = EdgeInsets()

    var body: some View {
        let options = HistogramAssist.store.options
        let size = ScopePanelPlacement.size(
            HistogramAssist.panelSize(scale: HistogramAssist.store.presentationScale(in: canvas)),
            canvas: canvas, clearance: chromeClearance)
        let plot = ScopeMiniChrome(
            title: HistogramAssist.panelTitle, chip: HistogramAssist.chip,
            size: size
        ) {
            // Draw-only body: curves arrive remapped / blended / smoothed and
            // the traffic reading pre-metered (DESIGN §3.2) — no math on main.
            ScopeBundleScope { assist in
                HistogramScopePlot(
                    display: assist.histogramDisplay,
                    traffic: assist.traffic,
                    showTrafficLights: options.trafficLights)
            }
        }
        .accessibilityLabel("RGB histogram, scale 0 to 100")
        if canvas.width > 1, canvas.height > 1 {
            HistogramAssist.overlay(
                canvas: canvas, feed: feed, chromeClearance: chromeClearance
            ) {
                plot
            }
        } else {
            plot
        }
    }
}

private typealias HistogramScopePlot = MonitorUI.MonitorHistogramScopePlot

// MARK: - VECTOR

struct VectorscopeOverlay: View {
    @Environment(AppModel.self) private var model
    var canvas: CGRect = .zero
    var feed: CGRect = .zero
    var chromeClearance: EdgeInsets = EdgeInsets()

    var body: some View {
        let options = VectorscopeAssist.store.options
        let plot = ScopeMiniChrome(
            title: "Vector",
            chip: VectorscopeAssist.chip(zoom: options.zoom),
            size: ScopePanelPlacement.size(
                VectorscopeAssist.panelSize(
                    scale: VectorscopeAssist.store.presentationScale(in: canvas)),
                canvas: canvas, clearance: chromeClearance)
        ) {
            ScopeBundleScope { assist in
                MonitorVectorscopeScopePlot(points: assist.vectorscopePoints,
                    trail: assist.trailVectorscopePoints, zoom: options.zoom,
                    brightness: options.brightness, revision: assist.revision,
                    configureDisplay: scopeDisplay)
            }
        }
        .accessibilityLabel("Vectorscope")
        if canvas.width > 1, canvas.height > 1 {
            VectorscopeAssist.overlay(
                canvas: canvas, feed: feed, chromeClearance: chromeClearance
            ) {
                plot
            }
        } else {
            plot
        }
    }
}

/// Shared CbCr density raster for VECTOR. Points are already monitor-domain
/// (through the operator LUT or the official DJI display cube) — the only math
/// here is ``ScopeChroma`` and the density ramp. One binning path feeds both
/// the Metal texture and the Canvas fallback so they can never disagree.
typealias VectorscopeRaster = OpenCineMedia.VectorscopeRaster

// MARK: - LIGHTS

struct TrafficLightsOverlay: View {
    @Environment(AppModel.self) private var model
    var bounds: CGRect
    var feed: CGRect
    var chromeClearance: EdgeInsets

    var body: some View {
        let store = TrafficLightsAssist.store
        let size = ScopePanelPlacement.size(
            TrafficLightsAssist.panelSize(scale: store.scale),
            canvas: bounds, clearance: chromeClearance)
        TrafficLightsMovablePanel(
            store: store,
            size: size,
            defaultCenter: TrafficLightsAssist.defaultCenter(
                feed: feed, size: size, bounds: bounds, chromeClearance: chromeClearance),
            bounds: bounds,
            placementBounds: ScopePanelPlacement.bounds(in: bounds, clearance: chromeClearance)
        ) {
            // Metered once in the sampler with the operator threshold riding
            // `LiveImageEffects.trafficThreshold` — render the bundle directly.
            ScopeBundleScope { _ in
                TrafficLightsMeterMini(reading: model.monitorSamples.bundle.traffic)
            }
        }
    }
}

/// OpenZCine `TrafficLightsMeterMini` — RED-style RGB goal posts, clip lamps on
/// top, crush lamps on the floor, `TL` title. `fillsWidth` is the portrait
/// full-bleed stack; the landscape floating panel stays the 74-box.
struct TrafficLightsMeterMini: View {
    let reading: ScopeTrafficLightsReading
    var fillsWidth: Bool = false

    var body: some View {
        GeometryReader { proxy in
            let uiScale = min(
                proxy.size.width / TrafficLightsAssist.baseSize.width,
                proxy.size.height / TrafficLightsAssist.baseSize.height)
            let columnWidth = TrafficLightsAssist.columnWidth(
                fillsWidth: fillsWidth, panelWidth: proxy.size.width, uiScale: uiScale)
            VStack(spacing: TrafficLightsAssist.titleSpacing * uiScale) {
                Text(TrafficLightsAssist.meterTitle)
                    .font(
                        .system(
                            size: TrafficLightsAssist.titleSize * uiScale, weight: .bold,
                            design: .monospaced)
                    )
                    .foregroundStyle(LiveDesign.text.opacity(0.58))
                    .lineLimit(1)
                HStack(alignment: .bottom, spacing: TrafficLightsAssist.columnSpacing * uiScale) {
                    goalPost(
                        color: TrafficLightsAssist.meterColor(TrafficLightsAssist.meterRedRGB),
                        channel: reading.red, uiScale: uiScale, columnWidth: columnWidth)
                    goalPost(
                        color: TrafficLightsAssist.meterColor(TrafficLightsAssist.meterGreenRGB),
                        channel: reading.green, uiScale: uiScale, columnWidth: columnWidth)
                    goalPost(
                        color: TrafficLightsAssist.meterColor(TrafficLightsAssist.meterBlueRGB),
                        channel: reading.blue, uiScale: uiScale, columnWidth: columnWidth)
                }
                .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
            .padding(.horizontal, TrafficLightsAssist.panelPad * uiScale)
            .padding(.vertical, TrafficLightsAssist.panelPad * uiScale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .monitorGlass(
            in: RoundedRectangle(cornerRadius: 10, style: .continuous), density: .scope
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.34), radius: 11, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TrafficLightsAssist.accessibilityTitle)
        .accessibilityValue(TrafficLightsAssist.accessibilityValue(for: reading))
    }

    private func goalPost(
        color: Color, channel: ScopeChannelLight, uiScale: CGFloat, columnWidth: CGFloat
    ) -> some View {
        let columnHeight = TrafficLightsAssist.columnHeight * uiScale
        let indicatorSize = TrafficLightsAssist.indicatorSize * uiScale
        let shown = TrafficLightsAssist.channelDisplay(for: channel)
        return VStack(spacing: TrafficLightsAssist.postSpacing * uiScale) {
            trafficIndicator(
                color: color, active: channel.clip, size: indicatorSize, uiScale: uiScale)
            GeometryReader { proxy in
                let height = proxy.size.height
                let centerLineHeight = max(1, uiScale * TrafficLightsAssist.centerLineFactor)
                let halfHeight = (height - centerLineHeight) / 2
                let barHeight = halfHeight * CGFloat(shown.barFill)
                let track = RoundedRectangle(
                    cornerRadius: TrafficLightsAssist.trackCorner * uiScale, style: .continuous
                )
                .fill(LiveDesign.text.opacity(0.08))
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        track
                        if shown.side == .over, barHeight > 0 {
                            goalPostFill(
                                color: color,
                                height: max(TrafficLightsAssist.minBarHeight * uiScale, barHeight),
                                uiScale: uiScale, towardClip: true)
                        }
                    }
                    .frame(height: halfHeight)
                    .clipped()
                    Rectangle()
                        .fill(LiveDesign.text.opacity(0.14))
                        .frame(height: centerLineHeight)
                    ZStack(alignment: .top) {
                        track
                        if shown.side == .under, barHeight > 0 {
                            goalPostFill(
                                color: color,
                                height: max(TrafficLightsAssist.minBarHeight * uiScale, barHeight),
                                uiScale: uiScale, towardClip: false)
                        }
                    }
                    .frame(height: halfHeight)
                    .clipped()
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: TrafficLightsAssist.trackCorner * uiScale, style: .continuous)
                )
                .animation(.easeOut(duration: 0.12), value: shown.barFill)
                .animation(.easeOut(duration: 0.12), value: shown.side)
            }
            .frame(width: columnWidth, height: columnHeight)
            trafficIndicator(
                color: color, active: channel.crush, size: indicatorSize, uiScale: uiScale)
        }
        .frame(maxWidth: .infinity)
    }

    private func goalPostFill(
        color: Color, height: CGFloat, uiScale: CGFloat, towardClip: Bool
    ) -> some View {
        RoundedRectangle(
            cornerRadius: TrafficLightsAssist.trackCorner * uiScale, style: .continuous
        )
        .fill(
            LinearGradient(
                colors: [color.opacity(0.35), color.opacity(0.92)],
                startPoint: towardClip ? .bottom : .top,
                endPoint: towardClip ? .top : .bottom)
        )
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func trafficIndicator(color: Color, active: Bool, size: CGFloat, uiScale: CGFloat)
        -> some View
    {
        Circle()
            .fill(active ? color : Color.clear)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .strokeBorder(
                        color.opacity(active ? 1 : 0.75), lineWidth: max(1, 1.5 * uiScale))
            )
            .shadow(color: active ? color.opacity(0.45) : .clear, radius: active ? 4 * uiScale : 0)
            .animation(.easeOut(duration: 0.15), value: active)
    }
}

// MARK: - Chrome + drawing

/// Reads the scope bundle in its own observation scope. Read in an overlay
/// body, every bundle (up to 25 Hz) re-evaluated the movable panel wrapper
/// (gestures, shadow, placement) around the plot as well.
private struct ScopeBundleScope<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder let content: (ScopeAssistBundle) -> Content

    var body: some View { content(model.monitorSamples.displayBundle) }
}

private struct ScopeMiniChrome<Content: View>: View {
    let title: String
    let chip: String
    let size: CGSize
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            content()
            HStack(spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(LiveDesign.text.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 2)
                Text(chip)
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(MonitorTheme.accent.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .padding(.horizontal, 7)
            .padding(.top, 5)
            .padding(.bottom, 2)
        }
        .frame(width: size.width, height: size.height)
        .compositingGroup()
        .monitorGlass(
            in: RoundedRectangle(cornerRadius: 10, style: .continuous), density: .scope
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.34), radius: 11, y: 8)
        .allowsHitTesting(false)
    }
}

/// OpenZCine `drawVectorscopeGraticule` — ring, crosshair, dashed I-phase
/// skin line, 75% boxes. Geometry lives on ``VectorscopeGraticule`` so the
/// Metal overlay and Canvas fallback cannot drift.
