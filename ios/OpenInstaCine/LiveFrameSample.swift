import CoreImage
import CoreVideo
import Foundation
import Observation
import OpenPocketViewCore
import OpenCineMedia
import OpenCineApple
import os

extension MonitorTransfer {
    /// Wire ColorMode that selected this transfer (`3F` / `3C` / `17` / `41`).
    var colorMode: ColorMode {
        switch self {
        case .rec709: .normal
        case .hdr: .hdr
        case .dlog: .dLog
        case .dlogm: .dLogM
        case .dlog2: .dLog2
        case .ilog: .iLog
        }
    }

    /// `CameraStatus.monitorTransfer`, else ColorMode, else the last known
    /// curve. Rec.709 only when nothing has been seen yet — falling back on a
    /// missing `@2` is the WAVE black shelf (D-Log2 paper black at ~8 IRE).
    static func resolved(
        _ status: MonitorTransfer?, colorMode: ColorMode?, previous: MonitorTransfer? = nil
    ) -> MonitorTransfer {
        status ?? colorMode.map(MonitorTransfer.init) ?? previous ?? .rec709
    }
}

// Native source adaptation stays beside its owning renderer until the runtime migration.
typealias ScopePoint = OpenCineMedia.ScopePoint
typealias ScopeSamples = OpenCineMedia.ScopeSamples
typealias ScopeHistogramDisplay = OpenCineMedia.ScopeHistogramDisplay
typealias ScopeAssistBundle = OpenCineMedia.ScopeAssistBundle
typealias PocketScopeSampler = OpenCineMedia.ScopeSampler

extension ScopeSampler {
    static func minInterval(
        activeScopeCount: Int,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    ) -> CFAbsoluteTime {
        let base =
            activeScopeCount > denseAssistThreshold ? denseMinInterval : baseMinInterval
        return base * thermalMultiplier(thermalState)
    }

    /// OpenZCine sheds the *interval*, never the sampling density.
    static func thermalMultiplier(_ state: ProcessInfo.ThermalState) -> Double {
        switch state {
        case .serious: 3
        case .critical: 5
        default: 1
        }
    }

    static func copyBGRA(_ buffer: CVPixelBuffer, maxWidth: Int) -> (
        bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int
    )? {
        LiveFrameTap.copyBGRA8(buffer, maxWidth: maxWidth)
    }

    /// Display cube for VECTOR when no operator LUT is armed.
    static func monitorCube(for transfer: MonitorTransfer, effects: LiveImageEffects) -> CubeLUT? {
        if let armed = ScopeMonitorLook.cube(from: effects) { return armed }
        switch transfer {
        case .ilog: return BundledLunaLUT.iLogToRec709
        case .rec709, .hdr, .dlog, .dlog2, .dlogm: return nil
        }
    }

}

/// Operator LUT (armed in effects) as a scope-side cube.
enum ScopeMonitorLook {
    static func cube(from effects: LiveImageEffects) -> CubeLUT? {
        let n = effects.lutDimension
        let expected = n * n * n * 4 * MemoryLayout<Float>.size
        guard n >= 2, effects.lutRGBA.count == expected else { return nil }
        let floats = effects.lutRGBA.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        var rgb = [Float]()
        rgb.reserveCapacity(n * n * n * 3)
        var index = 0
        while index + 2 < floats.count {
            rgb.append(floats[index])
            rgb.append(floats[index + 1])
            rgb.append(floats[index + 2])
            index += 4
        }
        return CubeLUT(size: n, rgb: rgb)
    }
}

typealias ScopeExposureCeiling = OpenPocketViewCore.ScopeExposureCeiling
typealias LiveFrameSampleBus = OpenCineApple.LiveFrameSampleBus

extension LiveFrameSampleBus {
    var colorMode: ColorMode? { reportedTransfer.map(\.colorMode) }

}

/// Off-main assist work. Latest-frame-wins so a slow peaking render cannot stall UDP ingest.
/// Pixel buffers are held as Swift properties — ARC retains/releases them. Do not call
/// `CVPixelBufferRetain` / `CVPixelBufferRelease` (unavailable under Swift ARC).
final class LiveAssistEngine: @unchecked Sendable {
    struct Result {
        var output: CIImage
        var identity: CIImage
        var source: CVPixelBuffer
        var needsGPU: Bool
        /// Transparent zebra / peaking paint. The identity layer stays the picture.
        var overlayOnly: Bool
        /// LUT cube product. False for identity fallbacks (NSNull of HEVC is black).
        var unmanagedBake: Bool
        var bundle: ScopeAssistBundle?
        var transfer: MonitorTransfer
        var colorMode: ColorMode
        /// False when this result is a late scope bundle. Present already happened.
        var shouldPresent: Bool
        /// Presentation time for skip-duplicate. `0` means unknown — never skip.
        var timeNs: Int64
    }

    private let queue = DispatchQueue(label: "opv.live-assist", qos: .userInitiated)
    private let log = Logger(subsystem: "com.opencapture.openinstacine", category: "scope-tap")
    private var pendingBuffer: CVPixelBuffer?
    private var pendingEffects = LiveImageEffects()
    private var pendingTransfer = MonitorTransfer.rec709
    private var pendingTimeNs: Int64 = 0
    private var pendingCompletion: (@Sendable (Result) -> Void)?
    private var busy = false
    private var nextScopeAt: CFAbsoluteTime = 0
    /// Rolling tap maximum for the 10 s `scope max:` journal cadence.
    private var ceilingLogMax: UInt8 = 0
    private var nextCeilingLogAt: CFAbsoluteTime = 0
    private var previousBundle = ScopeAssistBundle.empty
    /// The source's ceiling (its bus's, via ``adopt(exposureCeiling:)``). Queue-confined.
    private var exposureCeiling: OpenCineMedia.ScopeExposureCeiling = ScopeExposureCeiling()
    private var loggedTap = false
    private var tapWindowStart: CFAbsoluteTime = 0
    private var tapsInWindow = 0
    /// Shared tap: 25 Hz, 10 Hz with three or more scopes, shed further by
    /// thermal tier (×3 serious, ×5 critical). Deadline cannot catch up.

    init() {}

    /// Measure and ratchet `ceiling` from now on (the bus this engine publishes into).
    func adopt(exposureCeiling ceiling: OpenCineMedia.ScopeExposureCeiling) {
        queue.async { [self] in exposureCeiling = ceiling }
    }

    func updatePolicy(effects: LiveImageEffects, transfer: MonitorTransfer) {
        queue.async { [self] in
            var fx = effects
            fx.stamp(transfer: transfer, ceiling: exposureCeiling)
            pendingEffects = fx
            pendingTransfer = transfer
            if fx.falseColor {
                PocketFalseColorMap.warm(
                    scale: fx.falseColorScale, mode: fx.colorMode,
                    rec709: fx.falseColorRec709, clipByte: fx.resolvedClipByte,
                    hasLUT: fx.lutDimension >= 2)
            }
        }
    }

    func submit(
        _ buffer: CVPixelBuffer,
        effects: LiveImageEffects? = nil,
        transfer: MonitorTransfer? = nil,
        timeNs: Int64 = 0,
        completion: @escaping @Sendable (Result) -> Void
    ) {
        queue.async { [self] in
            pendingBuffer = FeedWorkingRaster.prepared(buffer)
            if let effects { pendingEffects = effects }
            if let transfer { pendingTransfer = transfer }
            pendingTimeNs = timeNs
            pendingCompletion = completion
            drain()
        }
    }

    func reset() {
        queue.async { [self] in
            pendingBuffer = nil
            pendingTimeNs = 0
            pendingCompletion = nil
            busy = false
            nextScopeAt = 0
            previousBundle = .empty
            loggedTap = false
            tapWindowStart = 0
            tapsInWindow = 0
            ceilingLogMax = 0
            nextCeilingLogAt = 0
            exposureCeiling.reset()
        }
    }

    private func logTapOnce(
        buffer: CVPixelBuffer,
        packed: (bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int)?,
        points: Int
    ) {
        guard !loggedTap else { return }
        loggedTap = true
        let fourCC = LiveFrameTap.fourCC(buffer)
        let srcW = CVPixelBufferGetWidth(buffer)
        let srcH = CVPixelBufferGetHeight(buffer)
        let planes = CVPixelBufferGetPlaneCount(buffer)
        let ioSurface = LiveFrameTap.isIOSurfaceBacked(buffer)
        if let packed {
            let maxLuma = LiveFrameTap.maxRGB(packed.bytes)
            log.info(
                "scope tap \(fourCC, privacy: .public) \(srcW)x\(srcH) planes=\(planes) ioSurface=\(ioSurface) -> \(packed.width)x\(packed.height) max=\(maxLuma) points=\(points)"
            )
            ControlLiveLog.line(
                "scope tap format: \(fourCC) \(srcW)x\(srcH) planes=\(planes) -> \(packed.width)x\(packed.height)")
        } else {
            log.error(
                "scope tap FAILED \(fourCC, privacy: .public) \(srcW)x\(srcH) planes=\(planes) ioSurface=\(ioSurface)"
            )
        }
    }

    private func drain() {
        if busy { return }
        guard let buffer = pendingBuffer, let completion = pendingCompletion else { return }
        pendingBuffer = nil
        var fx = pendingEffects
        var transfer = pendingTransfer
        let timeNs = pendingTimeNs
        fx.stamp(transfer: transfer, ceiling: exposureCeiling)
        busy = true

        // Copy CPU planes before Core Image attaches. WAVE/HISTO read the source
        // buffer; wrapping 10-bit x420 / IOSurface in CIImage first can unmap
        // those planes so the later tap returns nil and scopes stay empty.
        // The histogram walk still runs after present so it cannot hold 25 fps.
        var packed: (bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int)?
        if fx.needsScopes {
            let now = CFAbsoluteTimeGetCurrent()
            let interval = PocketScopeSampler.minInterval(activeScopeCount: fx.activeScopeCount)
            if now >= nextScopeAt {
                nextScopeAt = now + interval
                packed = PocketScopeSampler.copyBGRA(
                    buffer, maxWidth: PocketScopeSampler.maxWidth)
                if packed == nil {
                    logTapOnce(buffer: buffer, packed: nil, points: 0)
                }
            }
        }

        // Identity keeps Rec.709 / HLG attachments. NSNull is cube-only —
        // AVSampleBufferDisplayLayer and color-managed CI both go black without them.
        // Scopes-only present uses the pixel buffer, not this image, so skip the wrap.
        let identity: CIImage
        let output: CIImage
        let overlayOnly: Bool
        let unmanagedBake: Bool
        if fx.needsGPUFeed {
            identity = CIImage(cvPixelBuffer: buffer)
            let cameraCodes = CIImage(
                cvPixelBuffer: buffer, options: LiveMonitorWorkingSpace.imageOptions)
            // LUT / false colour cubes read encoded camera codes (WAVE/HISTO buffer).
            // Passing identity here when LUT was off made FALSE sample Rec.709-linearized
            // HEVC, so toggling the cube look moved the painted regions.
            let measure = (fx.lutDimension >= 2 || fx.falseColor) ? cameraCodes : identity
            if fx.needsOverlayFeed {
                // Measure the same codes WAVE uses; paint only. The picture stays
                // on the identity layer so zebra cannot Rec.709→sRGB the feed.
                output = LiveMonitorCompositor.assistOverlay(from: cameraCodes, effects: fx)
                overlayOnly = true
                unmanagedBake = false
            } else {
                let product = LiveMonitorCompositor.applyProduct(
                    to: measure, effects: fx, display: identity)
                output = product.image
                overlayOnly = false
                unmanagedBake = product.unmanagedBake
            }
        } else {
            identity = CIImage.empty()
            output = identity
            overlayOnly = false
            unmanagedBake = false
        }

        completion(
            Result(
                output: output,
                identity: identity,
                source: buffer,
                needsGPU: fx.needsGPUFeed,
                overlayOnly: overlayOnly,
                unmanagedBake: unmanagedBake,
                bundle: nil,
                transfer: transfer,
                colorMode: transfer.colorMode,
                shouldPresent: true,
                timeNs: timeNs))

        if let packed {
            let tapMin = LiveFrameTap.minRGB(packed.bytes)
            let tapMax = LiveFrameTap.maxRGB(packed.bytes)
            let inferred = fx.allowsTransferInference
                ? MonitorTransfer.inferred(minByte: tapMin, maxByte: tapMax, fallback: transfer)
                : transfer
            if inferred != transfer {
                transfer = inferred
                pendingTransfer = inferred
                fx.stamp(transfer: inferred, ceiling: exposureCeiling)
                ControlLiveLog.line(
                    "scope transfer: inferred \(inferred.rawValue) min=\(tapMin) max=\(tapMax)"
                )
            }
            var sampled = PocketScopeSampler.sample(
                bytes: packed.bytes, width: packed.width, height: packed.height,
                bytesPerRow: packed.bytesPerRow, transfer: transfer,
                clipByte: exposureCeiling.clipByte(transfer: transfer),
                includePoints: fx.waveform || fx.parade,
                includeVectorPoints: fx.vectorscope,
                look: fx.vectorscope
                    ? PocketScopeSampler.monitorCube(for: transfer, effects: fx) : nil,
                trafficThreshold: fx.trafficThreshold,
                previous: previousBundle)
            let observed = exposureCeiling.observeTapMax(tapMax, transfer: transfer)
            // Views draw this bundle on the ceiling now in force (after this tap's ratchet).
            sampled.clipByte = Int(observed.clip)
            previousBundle = sampled
            logTapOnce(buffer: buffer, packed: packed, points: sampled.samples.points.count)
            let tapNow = CFAbsoluteTimeGetCurrent()
            let interval = PocketScopeSampler.minInterval(activeScopeCount: fx.activeScopeCount)
            tapsInWindow += 1
            if tapWindowStart == 0 { tapWindowStart = tapNow }
            let elapsed = tapNow - tapWindowStart
            if elapsed >= 2 {
                let hz = Double(tapsInWindow) / elapsed
                let budget = 1.0 / interval
                ControlLiveLog.line(
                    String(
                        format: "scope tap: %.1fHz budget=%.0fHz scopes=%d", hz, budget,
                        fx.activeScopeCount))
                tapsInWindow = 0
                tapWindowStart = tapNow
            }
            // Ceiling calibration breadcrumb: rolling 10 s tap maximum
            // into the pullable journal (tools/pull-control-log.sh).
            // Point the lens at a blown lamp at each ISO and read the
            // saturation byte straight off these lines.
            ceilingLogMax = max(ceilingLogMax, tapMax)
            let now = CFAbsoluteTimeGetCurrent()
            if now >= nextCeilingLogAt {
                nextCeilingLogAt = now + 10
                ControlLiveLog.line(
                    "scope max: byte=\(ceilingLogMax) clip=\(observed.clip) transfer=\(transfer.rawValue) ei=\(exposureCeiling.resolvedISO())"
                )
                ceilingLogMax = 0
            }
            completion(
                Result(
                    output: output,
                    identity: identity,
                    source: buffer,
                    needsGPU: false,
                    overlayOnly: false,
                    unmanagedBake: false,
                    bundle: sampled,
                    transfer: transfer,
                    colorMode: transfer.colorMode,
                    shouldPresent: false,
                    timeNs: timeNs))
        }

        queue.async { [self] in
            busy = false
            drain()
        }
    }
}
