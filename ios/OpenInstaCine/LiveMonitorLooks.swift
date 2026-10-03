import Foundation
import OpenPocketViewCore
import SwiftUI
import OpenCineApple

/// iOS look adapters on the committed core type. Cubes, zebra thresholds, and the
/// false-colour ruler call `LiveColorScience` — do not keep a second science file.

extension LiveColorScience {
    /// OpenZCine `Peaking.gateScale` — display-referred feeds read larger gradients than log.
    static func peakingGateScale(for transfer: MonitorTransfer) -> Double {
        switch transfer {
        case .rec709, .hdr:
            let gradient = 1.57
            return gradient * gradient
        case .dlog, .dlog2, .dlogm, .ilog:
            return 1
        }
    }
}

// MARK: - False colour cubes (core bands → CIColorCube)

/// Source look adaptation. The native cache belongs to this renderer instance.
final class PocketFalseColorMap: @unchecked Sendable {
    typealias OverlayMaps = OpenCineApple.MonitorFalseColorMapper.OverlayMaps
    private let native: OpenCineApple.MonitorFalseColorMapper
    init() {
        let transfers: [MonitorTransfer] = [.rec709, .hdr, .dlog, .dlogm, .dlog2, .ilog]
        let curves = Dictionary(uniqueKeysWithValues: transfers.compactMap { transfer in
            LiveColorScience.rec709LookCurve(transfer).map { (transfer, $0) }
        })
        native = .init(lookCurves: curves)
    }
    func reset() { native.reset() }
    func cube(scale: FalseColorScaleKind, transfer: MonitorTransfer,
        rec709: Bool, clipByte: Int) -> CubeLUT {
        native.cube(scale: scale.liveScale, transfer: transfer, rec709: rec709, clipByte: clipByte)
    }
    func overlayPaintCube(scale: FalseColorScaleKind, transfer: MonitorTransfer,
        rec709: Bool, clipByte: Int) -> CubeLUT {
        native.overlayPaintCube(scale: scale.liveScale, transfer: transfer, rec709: rec709, clipByte: clipByte)
    }
    func overlayWeightCube(scale: FalseColorScaleKind, transfer: MonitorTransfer,
        rec709: Bool, clipByte: Int) -> CubeLUT {
        native.overlayWeightCube(scale: scale.liveScale, transfer: transfer, rec709: rec709, clipByte: clipByte)
    }
    func bands(scale: FalseColorScaleKind, transfer: MonitorTransfer,
        rec709: Bool, clipByte: Int) -> [LiveFalseColorBand] {
        native.bands(scale: scale.liveScale, transfer: transfer, rec709: rec709, clipByte: clipByte)
    }
    func overlayPaintData(scale: FalseColorScaleKind, mode: ColorMode, rec709: Bool,
        clipByte: Int, managedRender: Bool = false) -> (Int, Data)? {
        native.overlayPaintData(scale: scale.liveScale, transfer: MonitorTransfer(mode), rec709: rec709,
            clipByte: clipByte, managedRender: managedRender)
    }
    func overlayWeightData(scale: FalseColorScaleKind, mode: ColorMode, rec709: Bool,
        clipByte: Int) -> (Int, Data)? {
        native.overlayWeightData(scale: scale.liveScale, transfer: MonitorTransfer(mode), rec709: rec709,
            clipByte: clipByte)
    }
    func fullPaintData(scale: FalseColorScaleKind, mode: ColorMode, rec709: Bool,
        clipByte: Int) -> (Int, Data)? {
        native.fullPaintData(scale: scale.liveScale, transfer: MonitorTransfer(mode), rec709: rec709,
            clipByte: clipByte)
    }
    func overlayPairData(scale: FalseColorScaleKind, mode: ColorMode, rec709: Bool,
        clipByte: Int, managedRender: Bool = false) -> OverlayMaps? {
        native.overlayPairData(scale: scale.liveScale, transfer: MonitorTransfer(mode), rec709: rec709,
            clipByte: clipByte, managedRender: managedRender)
    }
    func warm(scale: FalseColorScaleKind, mode: ColorMode, rec709: Bool,
        clipByte: Int?, hasLUT: Bool = false) {
        native.warm(scale: scale.liveScale, transfer: MonitorTransfer(mode), rec709: rec709,
            clipByte: clipByte, hasLUT: hasLUT)
    }
}

extension FalseColorScaleKind {
    var liveScale: LiveFalseColorScale {
        switch self {
        case .sceneStops: .sceneStops
        case .stops: .stops
        case .ire: .ire
        case .limits: .limits
        }
    }

    var transitionWidth: Double { liveScale.edgeSoftness }

    /// OpenZCine `FalseColorReference.scaleLabel`.
    var referenceScaleLabel: String {
        switch self {
        case .sceneStops: "CineStop"
        case .stops: "Video"
        case .ire: "IRE"
        case .limits: "Limits"
        }
    }

    /// OpenZCine `FalseColorScale.legendStops` — painted zones in operator order.
    /// Labels come from ``FalseColorAssist/legendLabels(scale:)`` so WAVE-axis
    /// copy can differ from ``LiveColorScience`` without rewriting the mapper.
    func legendStops(transfer: MonitorTransfer, rec709: Bool, clipByte: Int) -> [LiveFalseColorBand]
    {
        let clip = LiveColorScience.falseColorClip(
            scale: liveScale, transfer: transfer, rec709: rec709, clipByte: clipByte)
        let bands = LiveColorScience.falseColorBands(
            liveScale, transfer: clip.transfer, clipEncoded: clip.ceiling)
        // CineStop labels come from core: the clip band moves with the camera.
        guard !liveScale.usesSceneStops else { return bands }
        return zip(
            bands,
            FalseColorAssist.legendLabels(scale: self)
        ).map { band, label in
            LiveFalseColorBand(
                lowerBound: band.lowerBound,
                upperBound: band.upperBound,
                red: band.red,
                green: band.green,
                blue: band.blue,
                label: label
            )
        }
    }
}

/// OpenZCine `FalseColorReference` chrome — 264×52 glass ruler with sparse zone chips.
struct FalseColorReferenceChrome: View {
    var scale: FalseColorScaleKind
    var colorMode: ColorMode = .normal
    var rec709: Bool
    var clipByte: Int

    static let panelSize = FalseColorReference.panelSize

    var body: some View {
        FalseColorAssist.referenceDisplay(
            scale: scale, colorMode: colorMode, rec709: rec709, clipByte: clipByte)
    }
}
