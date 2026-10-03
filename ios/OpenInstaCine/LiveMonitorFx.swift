import OpenCineMedia
import CoreImage
import OpenCineApple
import Metal
import OpenPocketViewCore
import UIKit

/// Compatibility names; picture and sample demand are owned by Media.
typealias LiveImageEffects = OpenCineMedia.MonitorFrameEffects

extension LiveImageEffects {
    var colorMode: ColorMode {
        get { transfer.colorMode }
        set {
            transfer = MonitorTransfer(newValue)
            referenceClipByte = ScopeExposureCeiling.referenceClipByte(transfer: transfer)
        }
    }
}

/// OpenZCine `Peaking.Color` — paint table lives on ``PeakingAssist/Color``.
typealias PeakingPaint = PeakingAssist.Color
/// OpenZCine `Peaking.Sensitivity` — detector steps live on ``PeakingAssist/Sensitivity``.
typealias PeakingSense = PeakingAssist.Sensitivity

/// Raw values are the persisted keys. `stops` is the scale now labeled Video;
/// its key stays "CineStop" so saved settings keep the scale they chose.
typealias FalseColorScaleKind = OpenCineMedia.MonitorFalseColorSelection

typealias ZebraPaint = MonitorZebraPaint

typealias LiveMonitorWorkingSpace = OpenCineApple.MonitorWorkingSpace

enum LiveMonitorCompositor {
    static var fusedPeakingAvailable: Bool { OpenCineApple.MonitorImageCompositor.fusedPeakingAvailable }
    static var fusedPeakingNote: String { OpenCineApple.MonitorImageCompositor.fusedPeakingNote }
    static func apply(to source: CIImage, effects: LiveImageEffects, display: CIImage? = nil, mapper: PocketFalseColorMap? = nil) -> CIImage {
        OpenCineApple.MonitorImageCompositor.apply(to: source, effects: effects.nativeImageEffects(using: mapper), display: display)
    }
    static func applyProduct(to source: CIImage, effects: LiveImageEffects, display: CIImage? = nil, mapper: PocketFalseColorMap? = nil)
        -> (image: CIImage, unmanagedBake: Bool) {
        OpenCineApple.MonitorImageCompositor.applyProduct(to: source, effects: effects.nativeImageEffects(using: mapper), display: display)
    }
    static func assistOverlay(from source: CIImage, effects: LiveImageEffects, mapper: PocketFalseColorMap? = nil) -> CIImage {
        OpenCineApple.MonitorImageCompositor.assistOverlay(from: source, effects: effects.nativeImageEffects(using: mapper))
    }
    static func place(_ overlay: CIImage, over base: CIImage) -> CIImage {
        OpenCineApple.MonitorImageCompositor.place(overlay, over: base)
    }
}

extension LiveImageEffects {
    func nativeImageEffects(using mapper: PocketFalseColorMap?) -> OpenCineApple.MonitorImageEffects {
        var result = nativeImagePlan
        if falseColor, let maps = mapper?.overlayPairData(
            scale: falseColorScale, mode: colorMode, rec709: falseColorRec709, clipByte: resolvedClipByte) {
            result.falseColorMaps = OpenCineApple.MonitorOverlayMaps(
                dimension: maps.dimension, paint: maps.paint, weight: maps.weight)
        }
        return result
    }

}


/// Compatibility name; the actual bake and retained texture pool are native-owned.
typealias FeedFrameBaker = OpenCineApple.MonitorFrameBaker

typealias FeedPresentationMetrics = OpenCineApple.MonitorPresentationMetrics
typealias FeedPresentOperations = OpenCineApple.MonitorPresentOperations

/// The app supplies operator choices; the stable native host owns rendering and presentation.
final class CIFeedView: OpenCineApple.MonitorPictureHost {
    init(frame: CGRect = .zero) {
        super.init(frame: frame, options: { screen in
            LiveHDRDisplay.refreshGain(screen: screen)
            return OpenCineApple.MonitorPresentationOptions(
                upscaler: FeedUpscaleSwitch.rendererReadsUpscaler,
                hdr: LiveHDRDisplay.isEnabled, hdrGain: LiveHDRDisplay.presentGain,
                previewSuperResolutionInput: FeedUpscaleSwitch.presentsSuperResolutionInput)
        }, logSubsystem: "com.opencapture.openinstacine")
        #if DEBUG
        onSuccessfulPresent = { FeedStressAutomation.notePresent() }
        #endif
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
