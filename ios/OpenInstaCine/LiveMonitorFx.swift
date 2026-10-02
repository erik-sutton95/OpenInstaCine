import CoreImage
import OpenCineApple
import Metal
import OpenPocketViewCore
import UIKit

/// Local GPU monitor tools. Peaking, false colour, and zebra measure **source
/// camera codes**: the same pre-LUT buffer WAVE / HISTO tap. Never the active LUT.
/// False colour Limits uses `ScopeDisplayScale.monitorPercent` for the active
/// `ColorMode`, as do Video / IRE; CineStop reads scene stops. LUT and de-squeeze are display-only CI ops. Mirror is a view-space
/// flip (`MirrorAssist.feedScale`) so it never lands in this graph.
struct LiveImageEffects: Equatable, Sendable {
    var peaking = false
    var zebra = false
    var falseColor = false
    var histogram = false
    var waveform = false
    var parade = false
    var vectorscope = false
    var trafficLights = false
    var ndMeter = false
    /// EV meter reading the picture: the scope tap must run.
    var evMeter = false
    var lutDimension = 0
    var lutRGBA = Data()

    var peakingColor: PeakingPaint = .red
    var peakingSensitivity: PeakingSense = .medium
    var falseColorScale: FalseColorScaleKind = .sceneStops
    /// Read: 709 (official Rec.709 look) or LOG (signal). Part of the effects so a
    /// change re-renders and rebakes the overlay.
    var falseColorRec709 = false
    var zebraHighlight = true
    var zebraMidtone = true
    var zebraHighlightIRE: Double = LiveZebra.highlightIRE
    var zebraMidtoneIRE: Double = LiveZebra.midtoneIRE
    var zebraHighlightColor: ZebraPaint = .white
    var zebraMidtoneColor: ZebraPaint = .amber
    /// Sibling / session stamps the camera color mode so D-Log2 IRE does not treat mid-grey as clip.
    var colorMode: ColorMode = .normal
    /// Live-tap clip byte of this source for `colorMode`'s curve, stamped next to it from the
    /// source's own ``ScopeExposureCeiling`` (never a process-wide one). Zebra and FALSE key it.
    /// `nil` until a source stamps it: the curve's reference ceiling (EI 1600, no ratchet).
    var clipByte: Int?
    /// Photo has an authoritative Rec.709 source; scene brightness cannot identify log.
    var allowsTransferInference = true
    var splitComparison = false
    var splitVertical = true
    /// Left-to-right monitor flip. Applied in `VideoView`, not this compositor.
    var mirror = false
    /// Top-to-bottom monitor flip (MIRROR Vertical). Same view-space path as `mirror`.
    var mirrorVertical = false
    /// Anamorphic display stretch. `1` is off. Anamorphic adapters squeeze the source;
    /// this preview-only correction never changes recordings or scope samples.
    var desqueezeFactor: Double = 1
    var desqueezeHorizontal = true
    /// Traffic-light pixel-fraction threshold (operator compensation, stops / 10).
    var trafficThreshold: Double = ScopeTrafficLights.defaultThreshold
    /// AF-C face box. Starts VT so Vision can see a `CVPixelBuffer`.
    var faceAF = false
    /// An open inspector requests the existing decoded-source tap. It never
    /// enables a main-picture effect or an additional decoder/display sink.
    var inspectorSample = false

    /// Peaking / false colour / zebra / LUT / display transforms — painted on the video frame.
    var needsGPUFeed: Bool {
        peaking || zebra || falseColor
            || lutDimension >= 2 || desqueezeFactor > 1.001
    }

    /// LUT / de-squeeze remake every pixel. Zebra, peaking, and false colour
    /// only paint — the identity HEVC / VT layer stays so contrast does not
    /// shift. A DeviceRGB bake of the Rec.709 picture is a visible
    /// Rec.709→sRGB re-encode. 50/50 is a LUT option, not its own replace
    /// path — split without a cube covered HEVC with an empty Metal plate.
    var replacesIdentityFeed: Bool {
        lutDimension >= 2
            || desqueezeFactor > 1.001
    }

    /// GPU 50/50 log-vs-LUT. Same gate as Android `FeedEffectsRenderPlan`.
    var appliesSplitComparison: Bool {
        FeedPresentPolicy.appliesSplitComparison(
            enabled: splitComparison,
            hasLUTCube: lutDimension >= 2 && !lutRGBA.isEmpty,
            falseColorPaintsFullFrame: falseColor && falseColorScale != .limits)
    }

    /// Transparent stripe / peaking overlay on top of the identity layer.
    var needsOverlayFeed: Bool {
        needsGPUFeed && !replacesIdentityFeed
    }

    /// Clip byte zebra and FALSE use for `colorMode`.
    var resolvedClipByte: Int {
        clipByte ?? ScopeExposureCeiling.referenceClipByte(transfer: MonitorTransfer(colorMode))
    }

    /// Stamp the source's curve and its live ceiling together.
    mutating func stamp(transfer: MonitorTransfer, ceiling: OpenCineMedia.ScopeExposureCeiling) {
        colorMode = transfer.colorMode
        clipByte = ceiling.clipByte(transfer: MonitorTransfer(colorMode))
    }

    /// WAVE / PARADE / HISTO / VECTOR / LIGHTS / ND share the source tap.
    var needsScopes: Bool {
        histogram || waveform || parade || vectorscope || trafficLights || ndMeter || evMeter
    }

    var needsScopePoints: Bool {
        waveform || parade || vectorscope
    }

    var activeScopeCount: Int {
        [histogram, waveform, parade, vectorscope, trafficLights, ndMeter].filter { $0 }
            .count
    }

    /// GPU feed, CPU scopes, or AF-C face detect. Any one starts VT for a pixel buffer.
    var needsSample: Bool {
        needsGPUFeed || needsScopes || faceAF || inspectorSample
    }

    var needsProcessedFeed: Bool { needsSample }

    func withEVMeter(_ on: Bool) -> LiveImageEffects {
        var fx = self
        fx.evMeter = on
        return fx
    }

    func withFaceAF(_ on: Bool) -> LiveImageEffects {
        var fx = self
        fx.faceAF = on
        return fx
    }
}

/// OpenZCine `Peaking.Color` — paint table lives on ``PeakingAssist/Color``.
typealias PeakingPaint = PeakingAssist.Color
/// OpenZCine `Peaking.Sensitivity` — detector steps live on ``PeakingAssist/Sensitivity``.
typealias PeakingSense = PeakingAssist.Sensitivity

/// Raw values are the persisted keys. `stops` is the scale now labeled Video;
/// its key stays "CineStop" so saved settings keep the scale they chose.
enum FalseColorScaleKind: String, CaseIterable, Codable, Sendable {
    case sceneStops = "SceneStops"
    case stops = "CineStop"
    case ire = "IRE"
    case limits = "Limits"
}

enum ZebraPaint: String, CaseIterable, Codable, Sendable {
    case white = "White"
    case amber = "Amber"
    case red = "Red"
    case cyan = "Cyan"
    case green = "Green"

    /// OpenZCine `ImageEffectsCompositor.zebraRGB`.
    var rgb: (Double, Double, Double) {
        switch self {
        case .white: (1, 1, 1)
        case .amber: (1, 0.72, 0.2)
        case .red: (1, 0.15, 0.15)
        case .cyan: (0, 0.85, 0.9)
        case .green: (0.2, 0.9, 0.35)
        }
    }
}

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
    var nativeImagePlan: OpenCineApple.MonitorImageEffects {
        let transfer = MonitorTransfer(colorMode)
        var result = OpenCineApple.MonitorImageEffects()
        result.peaking = peaking; result.zebra = zebra; result.falseColor = falseColor
        result.lutDimension = lutDimension; result.lutRGBA = lutRGBA
        result.peakingColor = OpenCineApple.MonitorRGB(peakingColor.rgb)
        result.peakingSensitivity = OpenCineApple.MonitorPeakingSensitivity(
            ratioThreshold: peakingSensitivity.ratioThreshold, noiseGate: peakingSensitivity.noiseGate)
        result.peakingGateScale = LiveColorScience.peakingGateScale(for: transfer)
        result.transfer = transfer; result.clipByte = resolvedClipByte
        result.zebraSpec = OpenCineApple.MonitorZebraSpec(
            highlightEnabled: zebraHighlight, highlightIRE: zebraHighlightIRE,
            highlightColor: OpenCineApple.MonitorRGB(zebraHighlightColor.rgb),
            midtoneEnabled: zebraMidtone, midtoneIRE: zebraMidtoneIRE,
            midtoneColor: OpenCineApple.MonitorRGB(zebraMidtoneColor.rgb))
        result.falseColorPaintsFullFrame = falseColor && falseColorScale != .limits
        result.splitComparison = splitComparison; result.splitVertical = splitVertical
        result.desqueezeFactor = desqueezeFactor; result.desqueezeHorizontal = desqueezeHorizontal
        return result
    }
}


/// OpenZCine `MetalFeedFrameBaker`: evaluate the look graph at feed/panel size off-main.
/// `CIFeedView` only scales the published texture into the drawable — no `createCGImage`.
final class FeedFrameBaker: @unchecked Sendable {
    /// Texture and source metadata are acquired together under the pool lock.
    struct Frame: @unchecked Sendable {
        let texture: MTLTexture
        let drawableSize: CGSize
        let pixelFormat: MTLPixelFormat
        let id: UInt64
        let generation: Int
        let timeNs: Int64
        let unmanaged: Bool
        let overlay: Bool
    }
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let lutContext: CIContext
    private let displayContext: CIContext
    private let workQueue = DispatchQueue(label: "opv.metal-feed-bake", qos: .userInitiated)
    private let lock = NSLock()
    private var pending:
        (
            image: CIImage, drawableSize: CGSize, pixelFormat: MTLPixelFormat, unmanaged: Bool,
            overlay: Bool, id: UInt64, generation: Int, timeNs: Int64
        )?
    private var pendingDone: (@Sendable () -> Void)?
    private var busy = false
    private var textures: [MTLTexture] = []
    private var nextTexture = 0
    private var retained: [ObjectIdentifier: Int] = [:]
    private var baking: Set<ObjectIdentifier> = []
    private var published: Frame?
    private var nextFrameID: UInt64 = 0
    private static let depth = 3

    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.lutContext = CIContext(
            mtlCommandQueue: commandQueue,
            options: LiveMonitorWorkingSpace.contextOptions)
        self.displayContext = CIContext(
            mtlCommandQueue: commandQueue,
            options: LiveMonitorWorkingSpace.displayContextOptions)
    }

    func scheduleBake(
        image: CIImage, drawableSize: CGSize, pixelFormat: MTLPixelFormat,
        unmanaged: Bool = true, overlay: Bool = false,
        generation: Int = 0, timeNs: Int64 = 0,
        onComplete: @escaping @Sendable () -> Void
    ) {
        guard drawableSize.width > 0, drawableSize.height > 0 else { return }
        lock.lock()
        nextFrameID &+= 1
        pending = (
            image, drawableSize, pixelFormat, unmanaged, overlay, nextFrameID, generation, timeNs
        )
        pendingDone = onComplete
        let start = !busy
        if start { busy = true }
        lock.unlock()
        if start { workQueue.async { [self] in run() } }
    }

    func bakedTexture(for drawableSize: CGSize, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        acquireFrame(for: drawableSize, pixelFormat: pixelFormat)?.texture
    }

    func acquireFrame(for drawableSize: CGSize, pixelFormat: MTLPixelFormat) -> Frame? {
        lock.lock()
        defer { lock.unlock() }
        guard let published,
            published.drawableSize == drawableSize,
            published.pixelFormat == pixelFormat
        else { return nil }
        retained[ObjectIdentifier(published.texture), default: 0] += 1
        return published
    }

    func releaseBakedTexture(_ texture: MTLTexture) {
        let key = ObjectIdentifier(texture)
        lock.lock()
        defer { lock.unlock() }
        guard let count = retained[key] else { return }
        if count <= 1 {
            retained[key] = nil
        } else {
            retained[key] = count - 1
        }
    }

    /// CI bottom-left → Metal/MPS origin. Same four multiplies as OpenZCine's baker.
    static func metalOriginTransform(extent: CGRect, bakeWidth: Int, bakeHeight: Int)
        -> CGAffineTransform
    {
        let sx = CGFloat(bakeWidth) / max(extent.width, 1)
        let sy = CGFloat(bakeHeight) / max(extent.height, 1)
        var transform = CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
        transform = transform.concatenating(CGAffineTransform(scaleX: sx, y: sy))
        transform = transform.concatenating(CGAffineTransform(scaleX: 1, y: -1))
        transform = transform.concatenating(
            CGAffineTransform(translationX: 0, y: CGFloat(bakeHeight)))
        return transform
    }

    /// Source resolution, downscale-bounded by the drawable. OpenZCine `bakeSize`.
    static func bakeSize(source: CGSize, drawable: CGSize) -> CGSize {
        guard source.width.isFinite, source.height.isFinite,
            source.width > 0, source.height > 0,
            source.width <= 16_384, source.height <= 16_384,
            drawable.width > 0, drawable.height > 0
        else { return drawable }
        let scale = min(drawable.width / source.width, drawable.height / source.height, 1)
        let fitted = CGSize(width: source.width * scale, height: source.height * scale)
        guard fitted.width >= 1, fitted.height >= 1 else { return drawable }
        return fitted
    }

    private func run() {
        lock.lock()
        guard let request = pending else {
            busy = false
            lock.unlock()
            return
        }
        pending = nil
        let done = pendingDone
        pendingDone = nil
        lock.unlock()

        let started = bake(
            request.image, drawableSize: request.drawableSize, pixelFormat: request.pixelFormat,
            unmanaged: request.unmanaged, overlay: request.overlay,
            id: request.id, generation: request.generation, timeNs: request.timeNs
        ) {
            done?()
        }
        if started {
            // Overlap the next cube while this one is still on the GPU.
            workQueue.async { [self] in run() }
            return
        }
        lock.lock()
        if pending == nil {
            pending = request
            pendingDone = done
        }
        let waitingGPU = !baking.isEmpty
        if !waitingGPU { busy = false }
        lock.unlock()
    }

    @discardableResult
    private func bake(
        _ source: CIImage, drawableSize: CGSize, pixelFormat: MTLPixelFormat,
        unmanaged: Bool, overlay: Bool, id: UInt64, generation: Int, timeNs: Int64,
        finished: @escaping () -> Void
    ) -> Bool {
        let extent = source.extent
        let size = Self.bakeSize(source: extent.size, drawable: drawableSize)
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        // Same origin flip as OpenZCine `MetalFeedFrameBaker`: CI is bottom-left,
        // MPS / Metal treat y=0 as the bottom of the picture. CAMetalLayer blit
        // of an unflipped bake is upright; Fast/Quality go through MPS, so the
        // bake must match that kernel or the picture lands upside down.
        let prepared =
            source
            .transformed(
                by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
            )
            .transformed(
                by: CGAffineTransform(
                    scaleX: CGFloat(width) / max(extent.width, 1),
                    y: CGFloat(height) / max(extent.height, 1))
            )
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(height)))
        guard
            let target = renderTexture(width: width, height: height, pixelFormat: pixelFormat),
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return false
        }
        let context = unmanaged ? lutContext : displayContext
        let token = ObjectIdentifier(target)
        lock.lock()
        baking.insert(token)
        lock.unlock()
        context.render(
            prepared, to: target, commandBuffer: commandBuffer,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: LiveMonitorWorkingSpace.metalDestination)
        commandBuffer.addCompletedHandler { [self] command in
            lock.lock()
            baking.remove(token)
            if command.status == .completed, id > (published?.id ?? 0) {
                published = Frame(
                    texture: target, drawableSize: drawableSize, pixelFormat: pixelFormat,
                    id: id, generation: generation, timeNs: timeNs,
                    unmanaged: unmanaged, overlay: overlay)
            }
            lock.unlock()
            finished()
            workQueue.async { [self] in run() }
        }
        commandBuffer.commit()
        return true
    }

    private func renderTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat) -> MTLTexture?
    {
        lock.lock()
        defer { lock.unlock() }
        let matches =
            textures.count == Self.depth
            && textures.allSatisfy {
                $0.width == width && $0.height == height && $0.pixelFormat == pixelFormat
            }
        if !matches {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
            descriptor.storageMode = .private
            let built = (0..<Self.depth).compactMap { _ in
                device.makeTexture(descriptor: descriptor)
            }
            guard built.count == Self.depth else { return nil }
            textures = built
            nextTexture = 0
            retained = retained.filter { key, _ in
                textures.contains { ObjectIdentifier($0) == key }
            }
        }
        for offset in 0..<textures.count {
            let index = (nextTexture + offset) % textures.count
            let texture = textures[index]
            let id = ObjectIdentifier(texture)
            if retained[id] == nil, !baking.contains(id), published?.texture !== texture {
                nextTexture = index + 1
                return texture
            }
        }
        return nil
    }
}

private struct FeedPresentBox<Value>: @unchecked Sendable {
    let value: Value
}

/// Injectable Metal boundary: acquisition may block, submission completes asynchronously.
struct FeedPresentOperations: @unchecked Sendable {
    var acquire: @Sendable (CAMetalLayer) -> CAMetalDrawable? = { $0.nextDrawable() }
    var encode: (@Sendable (FeedFrameBaker.Frame, MTLTexture, MTLCommandBuffer) -> Bool)?
    var submit:
        @Sendable (
            MTLCommandBuffer, CAMetalDrawable, @escaping @Sendable (Bool) -> Void
        ) -> Void = { command, drawable, completed in
            command.addCompletedHandler { completed($0.status == .completed) }
            command.present(drawable)
            command.commit()
        }
}

/// Measurement boundary for journal windows; renderer scheduling is independent.
struct FeedPresentationMetrics {
    struct Window {
        let gpuFramesPerSecond: Double
        let maximumGapMilliseconds: Double
        let maximumAcquireMilliseconds: Double
        let maximumGPUCompletionMilliseconds: Double
    }

    private var cadence: DeliveryCadence
    private var maximumAcquireMilliseconds = 0.0
    private var maximumGPUCompletionMilliseconds = 0.0

    init(startedAt: TimeInterval) { cadence = DeliveryCadence(startedAt: startedAt) }

    mutating func notePresented(at now: TimeInterval) { cadence.note(at: now) }

    mutating func noteAcquire(milliseconds: Double) {
        maximumAcquireMilliseconds = max(maximumAcquireMilliseconds, milliseconds)
    }

    mutating func noteGPUCompletion(milliseconds: Double) {
        maximumGPUCompletionMilliseconds = max(maximumGPUCompletionMilliseconds, milliseconds)
    }

    mutating func drain(at now: TimeInterval) -> Window? {
        guard let timing = cadence.takeWindow(at: now) else { return nil }
        let window = Window(
            gpuFramesPerSecond: timing.hertz,
            maximumGapMilliseconds: timing.maximumGapMilliseconds,
            maximumAcquireMilliseconds: maximumAcquireMilliseconds,
            maximumGPUCompletionMilliseconds: maximumGPUCompletionMilliseconds)
        maximumAcquireMilliseconds = 0
        maximumGPUCompletionMilliseconds = 0
        return window
    }
}

/// Metal-backed presenter. Baking, scaling and model preparation run off-main.
final class CIFeedView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    private let device: MTLDevice?
    private let renderer: FeedPresentRenderer
    private let baker: FeedFrameBaker?
    /// Presents commit here and complete on the GPU — never a synchronous render on main.
    private let presentQueue: MTLCommandQueue?
    /// First successful present. Until then the VT layer must stay visible —
    /// this view is opaque black and `display` returns before the bake lands.
    private(set) var hasPresentedFrame = false
    /// Last successful present was transparent zebra / peaking / false colour.
    /// LUT must not treat that as replace-ownership.
    private(set) var lastPresentWasOverlay = false
    /// Offscreen / scrolling-off views skip Metal. Same contract as LiveKit `VideoView.isEnabled`.
    var isEnabled = true
    /// Playback (and live LUT replace) adopt the metal picture after this fires.
    var onPresented: (() -> Void)?
    private(set) var lastPresentedTimeNs: Int64 = 0
    private var lastPresentedBakeID: UInt64 = 0
    private let drawableQueue = DispatchQueue(label: "opv.feed-drawable", qos: .userInitiated)
    private var presentGeneration = 0
    private var inFlightPresents = 0
    private var pendingPresent = false
    var presentOperations = FeedPresentOperations()
    private(set) var lastPresentedAt: Date?
    private(set) var presentedFrames = 0
    private(set) var skippedDuplicates = 0
    private(set) var skippedDisabled = 0
    private(set) var skippedDrawableBusy = 0
    private(set) var failedPresents = 0
    private var presentationMetrics = FeedPresentationMetrics(
        startedAt: ProcessInfo.processInfo.systemUptime)
    /// View bounds in pixels. The drawable can be smaller; see ``presentDrawableSize``.
    private var panelPixelSize = CGSize.zero
    private var lastSourceSize = CGSize.zero

    var isRendering: Bool {
        !FeedPresentPolicy.isFrozen(
            secondsSinceLastPresent: lastPresentedAt.map { Date().timeIntervalSince($0) })
            && hasPresentedFrame
    }

    var debugLine: String {
        let timing = presentationMetrics.drain(at: ProcessInfo.processInfo.systemUptime)
        let rate = String(format: "%.1f", timing?.gpuFramesPerSecond ?? 0)
        return "feed present gpuFPS=\(rate) gpuGapMs=\(Int(timing?.maximumGapMilliseconds ?? 0)) "
            + "first=\(hasPresentedFrame ? 1 : 0) frozen=\(isRendering ? 0 : 1) overlay=\(lastPresentWasOverlay ? 1 : 0) "
            + "skipDup=\(skippedDuplicates) skipOff=\(skippedDisabled) skipBusy=\(skippedDrawableBusy) failed=\(failedPresents) "
            + "acquireMaxMs=\(Int(timing?.maximumAcquireMilliseconds ?? 0)) "
            + "gpuMaxMs=\(Int(timing?.maximumGPUCompletionMilliseconds ?? 0))"
    }

    override init(frame: CGRect) {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        self.renderer = FeedPresentRenderer(device: device)
        self.baker = device.map { FeedFrameBaker(device: $0) }
        self.presentQueue = device?.makeCommandQueue()
        super.init(frame: frame)
        isOpaque = true
        isHidden = true
        backgroundColor = .black
        metalLayer.device = device
        metalLayer.pixelFormat = LiveHDRDisplay.bakePixelFormat
        metalLayer.framebufferOnly = false
        metalLayer.contentsScale = UIScreen.main.scale
        // Timeout can still wait one second. Acquisition runs on drawableQueue,
        // with one reservation covering both acquisition and GPU completion.
        metalLayer.allowsNextDrawableTimeout = true
        // A source-sized drawable is aspect-fitted by the compositor, like the
        // identity layer. A panel-sized drawable has the bounds' aspect, so this is a no-op there.
        metalLayer.contentsGravity = .resizeAspect
        LiveHDRDisplay.configure(metalLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        syncHDRDisplay()
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let size = bounds.size
        if size.width > 1, size.height > 1 {
            let next = CGSize(width: size.width * scale, height: size.height * scale)
            if panelPixelSize != next {
                invalidatePendingPresents()
                resetPresentDedup()
                panelPixelSize = next
            }
            applyDrawableSize()
        }
    }

    /// Bilinear (Off / Fast) SDR presents at bake size: the compositor already
    /// scales this layer while compositing, so a panel-sized MPS bilinear pass and
    /// clear only added memory traffic for the same filter. Quality / AI need panel
    /// pixels to enlarge into, and HDR keeps its gain pass at panel size.
    static func presentDrawableSize(
        source: CGSize, panel: CGSize, upscaler: FeedUpscaler, hdr: Bool
    ) -> CGSize {
        guard !hdr, upscaler == .off || upscaler == .lanczos,
            source.width > 1, source.height > 1
        else { return panel }
        let fitted = FeedFrameBaker.bakeSize(source: source, drawable: panel)
        return CGSize(width: fitted.width.rounded(), height: fitted.height.rounded())
    }

    private func applyDrawableSize() {
        guard panelPixelSize.width > 1, panelPixelSize.height > 1 else { return }
        let next = Self.presentDrawableSize(
            source: lastSourceSize, panel: panelPixelSize,
            upscaler: FeedUpscaleSwitch.rendererReadsUpscaler, hdr: LiveHDRDisplay.isEnabled)
        guard next.width > 1, next.height > 1, metalLayer.drawableSize != next else { return }
        invalidatePendingPresents()
        resetPresentDedup()
        metalLayer.drawableSize = next
    }

    func setOverlayChrome(_ overlay: Bool) {
        isOpaque = !overlay
        backgroundColor = overlay ? .clear : .black
        metalLayer.isOpaque = !overlay
    }

    func syncHDRDisplay() {
        let format = LiveHDRDisplay.drawablePixelFormat()
        if metalLayer.pixelFormat != format
            || metalLayer.wantsExtendedDynamicRangeContent
                != LiveHDRDisplay.isEnabled
        {
            invalidatePendingPresents()
            resetPresentDedup()
        }
        LiveHDRDisplay.configure(metalLayer, screen: window?.screen)
    }

    func resetPresentDedup() {
        lastPresentedTimeNs = 0
    }

    /// Next clip / new look. Stale `hasPresentedFrame` would hide the new
    /// identity under the previous LUT until the chip is cycled.
    func resetPresentation() {
        invalidatePendingPresents()
        resetPresentDedup()
        hideForLayerPlan()
    }

    /// Hide the metal plate without dropping an in-flight bake. SwiftUI
    /// `attach` runs every pass — bumping `presentGeneration` here cancels the
    /// LUT cube that `present` just scheduled, then unhides an empty layer.
    func hideForLayerPlan() {
        hasPresentedFrame = false
        lastPresentWasOverlay = false
        lastPresentedAt = nil
        setOverlayChrome(false)
        isHidden = true
    }

    var debugPresentGeneration: Int { presentGeneration }

    /// Drop in-flight bakes (LUT off, feed detached). A late replace present
    /// must not unhide an opaque plate over identity.
    func invalidatePendingPresents() {
        presentGeneration += 1
        pendingPresent = false
    }

    @discardableResult
    func display(
        _ image: CIImage, unmanaged: Bool = true, overlay: Bool = false, timeNs: Int64 = 0
    ) -> Bool {
        if FeedPresentPolicy.isDuplicateFrameTime(timeNs, lastPresentedNs: lastPresentedTimeNs) {
            skippedDuplicates += 1
            return hasPresentedFrame
        }
        syncHDRDisplay()
        if isEnabled, image.extent.width > 1, image.extent.height > 1 {
            lastSourceSize = image.extent.size
            applyDrawableSize()
        }
        let size = metalLayer.drawableSize
        let hasDrawable = size.width > 1 && size.height > 1
        guard
            FeedPresentPolicy.shouldScheduleBake(enabled: isEnabled, hasDrawable: hasDrawable)
        else {
            skippedDisabled += 1
            return false
        }
        guard image.extent.width > 1, image.extent.height > 1 else { return false }
        let generation = presentGeneration
        if let baker {
            baker.scheduleBake(
                image: image, drawableSize: size, pixelFormat: LiveHDRDisplay.bakePixelFormat,
                unmanaged: unmanaged, overlay: overlay, generation: generation, timeNs: timeNs
            ) { [weak self] in
                DispatchQueue.main.async { self?.presentLatestBake(generation: generation) }
            }
            return true
        }
        return false
    }

    /// Acquisition may wait for Core Animation; MainActor remains free to ingest
    /// video and handle lifecycle changes. Only one acquisition/GPU flight exists.
    private func presentLatestBake(generation: Int) {
        guard generation == presentGeneration, isEnabled, let baker else { return }
        guard inFlightPresents == 0 else {
            skippedDrawableBusy += 1
            pendingPresent = true
            return
        }
        let size = metalLayer.drawableSize
        guard let frame = baker.acquireFrame(for: size, pixelFormat: LiveHDRDisplay.bakePixelFormat)
        else { return }
        guard frame.generation == generation, frame.id > lastPresentedBakeID,
            !FeedPresentPolicy.isDuplicateFrameTime(
                frame.timeNs, lastPresentedNs: lastPresentedTimeNs)
        else {
            skippedDuplicates += 1
            baker.releaseBakedTexture(frame.texture)
            return
        }
        if FeedPresentPolicy.unhideMetalBeforeBake(overlay: frame.overlay) {
            // Keep identity visible while the first drawable is being acquired.
            if !hasPresentedFrame { alpha = 0 }
            isHidden = false
        }
        inFlightPresents = 1
        let operations = presentOperations
        let layer = FeedPresentBox(value: metalLayer)
        drawableQueue.async { [weak self] in
            let started = ProcessInfo.processInfo.systemUptime
            let drawable = FeedPresentBox(value: operations.acquire(layer.value))
            let acquireMs = (ProcessInfo.processInfo.systemUptime - started) * 1_000
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    baker.releaseBakedTexture(frame.texture)
                    return
                }
                self.presentationMetrics.noteAcquire(milliseconds: acquireMs)
                self.submitAcquiredFrame(
                    frame, drawable: drawable.value, operations: operations, baker: baker)
            }
        }
    }

    private func submitAcquiredFrame(
        _ frame: FeedFrameBaker.Frame, drawable: CAMetalDrawable?,
        operations: FeedPresentOperations, baker: FeedFrameBaker
    ) {
        guard frame.generation == presentGeneration, isEnabled,
            frame.drawableSize == metalLayer.drawableSize, let drawable,
            let commandBuffer = presentQueue?.makeCommandBuffer()
        else {
            baker.releaseBakedTexture(frame.texture)
            failedPresents += 1
            if frame.generation == presentGeneration, !hasPresentedFrame {
                isHidden = true
                alpha = 1
            }
            finishPresentFlight()
            return
        }
        let renderer = self.renderer
        let resources = FeedPresentBox(value: (drawable, commandBuffer))
        drawableQueue.async { [weak self] in
            let (drawable, commandBuffer) = resources.value
            let encoded =
                operations.encode?(frame, drawable.texture, commandBuffer)
                ?? renderer.encode(frame, to: drawable.texture, commandBuffer: commandBuffer)
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    baker.releaseBakedTexture(frame.texture)
                    return
                }
                self.submitPreparedFrame(
                    frame, resources: resources, encoded: encoded,
                    operations: operations, baker: baker)
            }
        }
    }

    private func submitPreparedFrame(
        _ frame: FeedFrameBaker.Frame,
        resources: FeedPresentBox<(CAMetalDrawable, MTLCommandBuffer)>, encoded: Bool,
        operations: FeedPresentOperations, baker: FeedFrameBaker
    ) {
        // Rotation, coverage or recovery can invalidate the frame while a
        // native upscaler is preparing. Never submit that retired drawable.
        guard encoded, frame.generation == presentGeneration, isEnabled,
            frame.drawableSize == metalLayer.drawableSize
        else {
            baker.releaseBakedTexture(frame.texture)
            failedPresents += 1
            finishPresentFlight()
            return
        }
        let (drawable, commandBuffer) = resources.value
        let submittedAt = ProcessInfo.processInfo.systemUptime
        operations.submit(commandBuffer, drawable) { [weak self] success in
            // GPU has finished reading the pool slot, on success or failure.
            baker.releaseBakedTexture(frame.texture)
            let completedAt = Date()
            let gpuMs = (ProcessInfo.processInfo.systemUptime - submittedAt) * 1_000
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.presentationMetrics.noteGPUCompletion(milliseconds: gpuMs)
                if frame.generation == self.presentGeneration, self.isEnabled,
                    frame.drawableSize == self.metalLayer.drawableSize
                {
                    if success {
                        #if DEBUG
                            FeedStressAutomation.notePresent()
                        #endif
                        self.notePresented(frame, at: completedAt)
                        self.onPresented?()
                    } else {
                        self.failedPresents += 1
                        if !self.hasPresentedFrame { self.isHidden = true }
                    }
                }
                self.finishPresentFlight()
            }
        }
    }

    private func finishPresentFlight() {
        inFlightPresents = 0
        guard pendingPresent else { return }
        pendingPresent = false
        presentLatestBake(generation: presentGeneration)
    }

    private func notePresented(_ frame: FeedFrameBaker.Frame, at completedAt: Date) {
        let overlay = frame.overlay
        setOverlayChrome(overlay)
        lastPresentedBakeID = frame.id
        alpha = 1
        hasPresentedFrame = true
        lastPresentWasOverlay = overlay
        lastPresentedTimeNs = frame.timeNs
        lastPresentedAt = completedAt
        presentedFrames += 1
        presentationMetrics.notePresented(at: ProcessInfo.processInfo.systemUptime)
        // Overlay only: identity stays on the HEVC / VT layer. Unhiding an
        // opaque identity bake here is a black plate over a working picture.
        if overlay {
            isHidden = false
        }
    }
}

/// Confined to the presenter's serial drawable worker. It owns no UIKit state.
private final class FeedPresentRenderer: @unchecked Sendable {
    private let lutContext: CIContext
    private let displayContext: CIContext
    private let presentScaler: FeedPresentScaler?

    init(device: MTLDevice?) {
        let lutOptions = LiveMonitorWorkingSpace.contextOptions
        let displayOptions = LiveMonitorWorkingSpace.displayContextOptions
        lutContext =
            device.map { CIContext(mtlDevice: $0, options: lutOptions) }
            ?? CIContext(options: lutOptions)
        displayContext =
            device.map { CIContext(mtlDevice: $0, options: displayOptions) }
            ?? CIContext(options: displayOptions)
        presentScaler = device.map { FeedPresentScaler(device: $0) }
    }

    /// Bake is source-sized (`bakeSize` never enlarges). Off / Fast / Quality / AI enlarge
    /// it to the drawable the same way OpenZCine `MetalLiveView` does.
    func encode(
        _ frame: FeedFrameBaker.Frame, to target: MTLTexture, commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let baked = frame.texture
        let overlay = frame.overlay
        if let presentScaler,
            presentScaler.encode(
                from: baked, to: target, commandBuffer: commandBuffer, overlay: overlay)
        {
            return true
        }
        if baked.pixelFormat == target.pixelFormat,
            baked.width <= target.width, baked.height <= target.height,
            baked.width == target.width || baked.height == target.height
        {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(
                red: 0, green: 0, blue: 0, alpha: overlay ? 0 : 1)
            guard let clear = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
            else { return false }
            clear.endEncoding()
            guard let blit = commandBuffer.makeBlitCommandEncoder() else { return false }
            blit.copy(
                from: baked, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: baked.width, height: baked.height, depth: 1),
                to: target, destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(
                    x: (target.width - baked.width) / 2,
                    y: (target.height - baked.height) / 2,
                    z: 0))
            blit.endEncoding()
            return true
        }
        let unmanaged = frame.unmanaged
        let options =
            unmanaged
            ? LiveMonitorWorkingSpace.imageOptions
            : LiveMonitorWorkingSpace.displayImageOptions
        guard let image = CIImage(mtlTexture: baked, options: options) else { return false }
        let dest = CGRect(
            origin: .zero, size: CGSize(width: target.width, height: target.height))
        let fitted = Self.aspectFit(image, in: dest)
        let backdrop = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: overlay ? 0 : 1))
            .cropped(to: dest)
        let context = unmanaged ? lutContext : displayContext
        context.render(
            fitted.composited(over: backdrop), to: target, commandBuffer: commandBuffer,
            bounds: dest, colorSpace: LiveMonitorWorkingSpace.metalDestination)
        return true
    }

    private static func aspectFit(_ image: CIImage, in dest: CGRect) -> CIImage {
        let src = image.extent
        guard src.width > 0, src.height > 0 else { return image }
        let scale = min(dest.width / src.width, dest.height / src.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let e = scaled.extent
        let dx = dest.midX - e.midX
        let dy = dest.midY - e.midY
        return scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy))
    }
}

extension LiveImageEffects {
    var nativeAssistPolicy: OpenCineApple.MonitorAssistPolicy {
        var result = OpenCineApple.MonitorAssistPolicy()
        result.image = nativeImagePlan
        result.histogram = histogram; result.waveform = waveform; result.parade = parade
        result.vectorscope = vectorscope; result.trafficLights = trafficLights
        result.ndMeter = ndMeter; result.evMeter = evMeter
        result.trafficThreshold = trafficThreshold
        result.allowsTransferInference = allowsTransferInference
        switch falseColorScale {
        case .sceneStops: result.falseColorScale = .sceneStops
        case .stops: result.falseColorScale = .stops
        case .ire: result.falseColorScale = .ire
        case .limits: result.falseColorScale = .limits
        }
        result.falseColorRec709 = falseColorRec709
        return result
    }
}
