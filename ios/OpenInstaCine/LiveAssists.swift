import MonitorPresentation
import MonitorUI
import OpenPocketViewCore
import SwiftUI
import UIKit

/// Cinema live-monitor set. MAG is retired; PLAY stays off the video toolbar.
enum LiveAssistTool: String, CaseIterable, Identifiable {
    case lut = "LUT"
    case peaking = "PEAK"
    case falseColor = "FALSE"
    case zebra = "ZEBRA"
    case waveform = "WAVE"
    case parade = "PARADE"
    case histogram = "HISTO"
    case vectorscope = "VECTOR"
    case trafficLights = "LIGHTS"
    case ndMeter = "ND"
    case evMeter = "EV"
    case audioMeters = "AUDIO"
    case guides = "GUIDES"
    case grid = "GRID"
    case crosshair = "CROSS"
    case level = "LEVEL"
    case desqueeze = "DE-SQ"
    case mirror = "MIRROR"
    case instantReview = "PLAY"
    case magnification = "MAG"

    var id: String { rawValue }
    var sharedTool: MonitorAssistTool? { MonitorAssistTool(rawValue: rawValue) }

    var isRetired: Bool { self == .magnification }
    var isPhotographyOnly: Bool { self == .instantReview }

    /// Playback drops LEVEL (needs live camera attitude) and MAG (no on-feed key).
    /// AUDIO rides last, matching the live strip's trailing section.
    static var playbackToolbarCases: [LiveAssistTool] {
        toolbarCases.filter { $0 != .level && $0 != .magnification && $0 != .evMeter } + [
            .audioMeters
        ]
    }

    /// OpenZCine `activeCases` minus photography-only and AUDIO.
    /// AUDIO is appended as its own trailing section in `LiveAssistBar`.
    /// ND sits with the exposure meters (HISTO / VECTOR / LIGHTS).
    static var toolbarGroups: [[LiveAssistTool]] {
        [
            [.lut, .peaking, .falseColor],
            [.zebra, .waveform, .parade],
            [.histogram, .vectorscope, .trafficLights, .ndMeter, .evMeter],
            [.guides, .grid, .crosshair, .level],
            [.desqueeze, .mirror],
        ]
    }

    static var toolbarCases: [LiveAssistTool] { toolbarGroups.flatMap { $0 } }

    /// View Assist settings list — same cinema set as the bar, plus AUDIO.
    static var settingsCases: [LiveAssistTool] {
        toolbarCases + [.audioMeters]
    }

    /// Tools the operator can keep on DISP 2. Camera EV stays exclusive to DISP 1.
    static var cleanPinCases: [LiveAssistTool] { settingsCases.filter { $0 != .evMeter } }

    /// Compact label for the Display ▸ DISP 2 pin grid.
    var displaySettingsTitle: String { sharedTool?.displaySettingsTitle ?? title }

    var hasConfiguration: Bool { sharedTool?.hasConfiguration ?? false }

    /// The approved prototype owns these tool glyphs; app-only tools retain
    /// Lucide fallbacks without inventing a new visual language.
    var monitorIcon: MonitorAssistIcon? { sharedTool?.monitorIcon }

    /// Existing app-only assist glyphs use the shared Lucide catalog.
    var opcIcon: OpcIcon? { sharedTool?.fallbackIcon ?? (self == .instantReview ? .image : self == .magnification ? .zoomIn : nil) }

    var title: String { sharedTool?.title ?? (self == .instantReview ? "Instant Playback" : "Magnify") }
}

typealias GuideFamily = MonitorGuideFamily

typealias GuideAspect = MonitorGuideAspect

@Observable
final class LiveAssistState {
    var peaking = false
    var zebra = false
    var falseColor = false
    var histogram = false
    var waveform = false
    var parade = false
    var vectorscope = false
    var trafficLights = false
    var ndMeter = false
    var evMeter = false
    var audioMeters = false
    var grid = false
    var crosshair = false
    var guides = false
    var level = false
    var desqueeze = false
    var mirror = false
    /// MIRROR axes. Tap toggles the tool; the options pick which axes it flips.
    var mirrorHorizontal = true
    var mirrorVertical = false
    var instantReview = false
    var guideAspect: GuideAspect = .cinema
    var guideFamily: GuideFamily = .film
    var selectedGuides: Set<GuideAspect> = [.cinema]
    var guideMask = false
    var gridThirds = true
    var gridPhi = false
    var gridDiagonal = false
    var peakingColor: PeakingPaint = .red
    var peakingSensitivity: PeakingSense = .medium
    var falseColorScale: FalseColorScaleKind = .sceneStops
    var falseColorReference = true
    /// Video / IRE read log through the official Rec.709 look (709) or the signal (LOG).
    /// Per assist state: renderers read it from the effects, never from a global.
    var falseColorRec709 = false
    var zebraHighlight = true
    var zebraMidtone = true
    var zebraHighlightIRE: Double = LiveZebra.highlightIRE
    var zebraMidtoneIRE: Double = LiveZebra.midtoneIRE
    var zebraHighlightColor: ZebraPaint = .white
    var zebraMidtoneColor: ZebraPaint = .amber
    var desqueezeFactor: Double = 1.33
    var desqueezeHorizontal = true
    var desqueezeCustom = false
    var desqueezeCustomFactor: Double = 1.33
    var splitComparison = false
    var splitVertical = true
    /// Input-referred LUT stops (−3…+3, half-stop). 0 is the cube as shipped.
    var lutExposureStops: Double = 0
    /// DISP 2. Chrome follows `PocketDispChrome`; assists follow `cleanViewPinnedTools`.
    var clean = false
    /// View-assist tools that stay on the picture in DISP 2. Filter only — never mutates `isOn`.
    var cleanViewPinnedTools: Set<LiveAssistTool> = LiveAssistState.cleanViewDefaultPinnedTools
    /// OpenZCine `playbackVisibleAssistTools` — independent of the live toolbar.
    var playbackVisibleTools: Set<LiveAssistTool> = []
    var showLUTPicker = false
    var configureTool: LiveAssistTool? {
        didSet { if configureTool != .lut { inspectorLUTCache = nil } }
    }
    /// Icon (or toolbar) frame in `LiveCanvasSpace` for the long-press options popup.
    var longPressAnchor: CGRect = .zero
    /// OpenZCine `scopes.crushClipCompensation` — shared by HISTO edge lights and LIGHTS.
    var crushClipCompensation = TrafficLightsAssist.defaultCompensation
    var trafficLightsScale = TrafficLightsAssist.defaultScale
    var trafficLightsPosition: TrafficLightsAssist.StoredCenter?
    /// First-launch default is on — DJI Auto applies the matching official cube.
    var lutEnabled = true
    var lutSelection: LUTSelection = .djiAuto
    var monitorColorMode: ColorMode?
    var monitorFamily: CameraBodyFamily = .pocket
    /// The camera reports no metered EV, so the EV meter reads the picture.
    var evMeterFromPicture = false
    /// The camera reports audio levels (AUDIO in the live rail and View Assist list).
    var cameraHasAudio = true
    var monitorCameraName: String?
    /// Media player is grading a clip (connected or not). LUT sheet must not
    /// restamp Auto from the live SET — disconnected has no `inPlayback` flag.
    var gradesClip = false
    /// Live Photo / Photo. Not persisted. Playback clears this so clip color wins.
    var liveIsPhoto = false
    /// Inspector-only sampling follows the active scene and its visible source.
    /// Picture effects keep their existing lifetime beneath operator pages.
    var inspectorSceneActive = true
    /// Settings or Media covers the live page. Scope taps and rasters have no
    /// viewer there; looks, Face AF, Watch and relay keep their demand, and the
    /// shared VT decoder stays up, so reveal needs no enable.
    var liveCovered = false

    private func showsScopes(_ tool: LiveAssistTool) -> Bool {
        !liveCovered && isVisible(tool)
    }

    @ObservationIgnored private var lutCube: CubeLUT?
    @ObservationIgnored private var lutDimension = 0
    @ObservationIgnored private var lutRGBA = Data()
    @ObservationIgnored private var lastSaved: Data?
    @ObservationIgnored private var inspectorLUTCache: InspectorLUTCache?

    var lutArmed: Bool { lutEnabled }

    var lutStatusLabel: String {
        if liveIsPhoto, lutEnabled, lutSelection == .auto || lutSelection == .djiAuto {
            return "Auto · Rec.709"
        }
        return LUTResolver.statusLabel(
            enabled: lutEnabled,
            selection: lutSelection,
            source: resolvedSource()
        )
    }

    func resolvedSource() -> LUTSource {
        LiveLUTResolver.resolve(
            selection: lutSelection,
            colorMode: monitorColorMode,
            family: monitorFamily,
            cameraName: monitorCameraName,
            hasCustomDLog: CustomLUTStore.hasCube(.dLog),
            hasCustomDLog2: CustomLUTStore.hasCube(.dLog2),
            hasCustomRec709: CustomLUTStore.hasCube(.rec709),
            customFileName: OperatorPrefs.selectedCustomFileName,
            isPhoto: liveIsPhoto
        )
    }

    /// WAVE / PARADE / VECTOR / LIGHTS share one source-frame sample in `HevcDecoder`.
    /// Flags are what the monitor *shows* — DISP 2 applies the pin filter here.
    var effects: LiveImageEffects {
        LiveImageEffects(
            peaking: isVisible(.peaking),
            zebra: isVisible(.zebra),
            falseColor: isVisible(.falseColor),
            histogram: showsScopes(.histogram),
            waveform: showsScopes(.waveform),
            parade: showsScopes(.parade),
            vectorscope: showsScopes(.vectorscope),
            trafficLights: showsScopes(.trafficLights),
            ndMeter: showsScopes(.ndMeter),
            lutDimension: isVisible(.lut) ? lutDimension : 0,
            lutRGBA: isVisible(.lut) ? lutRGBA : Data(),
            peakingColor: peakingColor,
            peakingSensitivity: peakingSensitivity,
            falseColorScale: falseColorScale,
            falseColorRec709: falseColorRec709,
            zebraHighlight: zebraHighlight,
            zebraMidtone: zebraMidtone,
            zebraHighlightIRE: zebraHighlightIRE,
            zebraMidtoneIRE: zebraMidtoneIRE,
            zebraHighlightColor: zebraHighlightColor,
            zebraMidtoneColor: zebraMidtoneColor,
            colorMode: monitorColorMode ?? .normal,
            allowsTransferInference: !liveIsPhoto,
            splitComparison: splitComparison && isVisible(.lut),
            splitVertical: splitVertical,
            mirror: mirrorsHorizontally,
            mirrorVertical: flipsVertically,
            desqueezeFactor: isVisible(.desqueeze) ? desqueezeFactor : 1,
            desqueezeHorizontal: desqueezeHorizontal,
            trafficThreshold: crushClipCompensation.pixelFractionThreshold
        )
        .withEVMeter(evMeterFromPicture && isVisible(.evMeter))
        .withInspectorDemand(inspectorSceneActive && !gradesClip ? configureTool : nil)
    }

    /// Same graph as live, gated by playback-visible tools (OpenZCine `playbackImageEffects`).
    var playbackEffects: LiveImageEffects {
        var fx = effects
        fx.allowsTransferInference = true
        fx.inspectorSample = false
        fx.peaking = isPlaybackVisible(.peaking)
        fx.zebra = isPlaybackVisible(.zebra)
        fx.falseColor = isPlaybackVisible(.falseColor)
        fx.histogram = isPlaybackVisible(.histogram)
        fx.waveform = isPlaybackVisible(.waveform)
        fx.parade = isPlaybackVisible(.parade)
        fx.vectorscope = isPlaybackVisible(.vectorscope)
        fx.trafficLights = isPlaybackVisible(.trafficLights)
        fx.ndMeter = isPlaybackVisible(.ndMeter)
        fx.evMeter = false
        fx.lutDimension = isPlaybackVisible(.lut) ? lutDimension : 0
        fx.lutRGBA = isPlaybackVisible(.lut) ? lutRGBA : Data()
        fx.splitComparison = splitComparison && isPlaybackVisible(.lut)
        fx.mirror = isPlaybackVisible(.mirror) && mirrorHorizontal
        fx.mirrorVertical = isPlaybackVisible(.mirror) && mirrorVertical
        fx.desqueezeFactor = isPlaybackVisible(.desqueeze) ? desqueezeFactor : 1
        return fx.withInspectorDemand(inspectorSceneActive && gradesClip ? configureTool : nil)
    }

    init() {
        OperatorPrefs.load(into: self)
        cleanViewPinnedTools = OperatorPrefs.cleanViewPinnedTools
        playbackVisibleTools = OperatorPrefs.playbackVisibleAssistTools
        if monitorColorMode == nil {
            monitorColorMode = OperatorPrefs.lastMonitorColorMode
        }
        if lutEnabled { refreshLUTCube() }
        lastSaved = OperatorPrefs.encoded(self)
    }

    /// Picture corrections stay visible in DISP 2 unless the operator unpins them.
    static let cleanViewDefaultPinnedTools: Set<LiveAssistTool> = [
        .lut, .peaking, .desqueeze, .mirror,
    ]

    func isOn(_ tool: LiveAssistTool) -> Bool {
        switch tool {
        case .lut: lutArmed
        case .peaking: peaking
        case .zebra: zebra
        case .falseColor: falseColor
        case .waveform: waveform
        case .parade: parade
        case .histogram: histogram
        case .vectorscope: vectorscope
        case .trafficLights: trafficLights
        case .ndMeter: ndMeter
        case .evMeter: evMeter
        case .audioMeters: audioMeters
        case .guides: guides
        case .grid: grid
        case .crosshair: crosshair
        case .level: level
        case .desqueeze: desqueeze
        case .mirror: mirror
        case .instantReview: instantReview
        case .magnification: false
        }
    }

    /// OpenZCine `MonitorChromePolicy.isToolVisible`. Pins filter DISP 2; they never flip `isOn`.
    func isVisible(_ tool: LiveAssistTool) -> Bool {
        guard isOn(tool) else { return false }
        if clean { return tool != .evMeter && cleanViewPinnedTools.contains(tool) }
        return true
    }

    /// Live picture flips as shown. The tool on with an axis off leaves that axis alone.
    var mirrorsHorizontally: Bool { isVisible(.mirror) && mirrorHorizontal }
    var flipsVertically: Bool { isVisible(.mirror) && mirrorVertical }

    func toggleCleanViewPin(_ tool: LiveAssistTool) {
        guard LiveAssistTool.cleanPinCases.contains(tool) else { return }
        var pins = cleanViewPinnedTools
        if pins.contains(tool) {
            pins.remove(tool)
        } else {
            pins.insert(tool)
        }
        cleanViewPinnedTools = pins
        OperatorPrefs.cleanViewPinnedTools = pins
    }

    func isPlaybackVisible(_ tool: LiveAssistTool) -> Bool {
        tool != .evMeter && playbackVisibleTools.contains(tool)
    }

    func togglePlayback(_ tool: LiveAssistTool) {
        guard tool != .evMeter else { return }
        if playbackVisibleTools.contains(tool) {
            playbackVisibleTools.remove(tool)
        } else {
            playbackVisibleTools.insert(tool)
        }
        OperatorPrefs.playbackVisibleAssistTools = playbackVisibleTools

    }

    func toggle(_ tool: LiveAssistTool) {
        switch tool {
        case .lut:
            if lutEnabled {
                lutEnabled = false
                refreshLUTCube()
            } else {
                armLastLUT()
            }
        case .peaking: peaking.toggle()
        case .zebra: zebra.toggle()
        case .falseColor:
            falseColor.toggle()

        case .waveform: waveform.toggle()
        case .parade: parade.toggle()
        case .histogram: histogram.toggle()
        case .vectorscope: vectorscope.toggle()
        case .trafficLights: trafficLights.toggle()
        case .ndMeter: ndMeter.toggle()
        case .evMeter: evMeter.toggle()
        case .audioMeters: audioMeters.toggle()
        case .guides:
            guides.toggle()
            if guides, selectedGuides.isEmpty { selectedGuides = [guideAspect] }
        case .grid: grid.toggle()
        case .crosshair: crosshair.toggle()
        case .level: level.toggle()
        case .desqueeze: desqueeze.toggle()
        case .mirror: mirror.toggle()
        case .instantReview: instantReview.toggle()
        case .magnification: break
        }
        OperatorPrefs.save(self)
    }

    /// Picking a look turns LUT on. Auto stays Auto until the operator picks something else.
    func selectLUT(_ selection: LUTSelection) {
        lutSelection = selection
        lutEnabled = true
        OperatorPrefs.lutSelection = selection
        refreshLUTCube()
        OperatorPrefs.save(self)
    }

    /// Re-arms the last selection. The bar chip is the only off.
    func armLastLUT() {
        lutEnabled = true
        refreshLUTCube()
        OperatorPrefs.save(self)
    }

    func nudgeLUTExposure(_ delta: Double) {
        let next = LUTExposureCompensation.stepped(lutExposureStops, by: delta)
        guard next != lutExposureStops else { return }
        lutExposureStops = next
        refreshLUTCube()
        OperatorPrefs.save(self)
    }

    /// Color / zoom / body changes only swap the cube while an Auto row is selected.
    /// Photo does not persist Rec.709 over last live log, and does not rewrite LUT prefs.
    func syncLUT(
        to colorMode: ColorMode?,
        family: CameraBodyFamily = .pocket,
        cameraName: String? = nil,
        isPhoto: Bool = false,
        persistLast: Bool = true
    ) {
        liveIsPhoto = isPhoto && !gradesClip
        monitorColorMode = LiveMonitorColorScience.colorMode(
            isPhoto: liveIsPhoto, colorMode: colorMode)
        monitorFamily = family
        if let cameraName { monitorCameraName = cameraName }
        if persistLast, let colorMode, !liveIsPhoto {
            OperatorPrefs.lastMonitorColorMode = colorMode
        }
        refreshLUTCube()
    }

    /// Playback Auto follows the clip's ColorGammaSxS. Do not persist Rec.709
    /// from a Normal take over last live D-Log / D-Log2.
    func adoptPlaybackColor(
        _ colorMode: ColorMode,
        family: CameraBodyFamily = .pocket,
        cameraName: String? = nil
    ) {
        liveIsPhoto = false
        monitorColorMode = colorMode
        monitorFamily = family
        if let cameraName { monitorCameraName = cameraName }
        refreshLUTCube()
    }

    /// LUT sheet appear. Live SET must not replace the clip's Auto cube —
    /// including disconnected library playback (`gradesClip`, no camera SET).
    /// Watcher isolation: do not restamp from the camera session.
    func bindLUTPicker(
        live: ColorMode?,
        inPlayback: Bool,
        family: CameraBodyFamily = .pocket,
        cameraName: String? = nil,
        isPhoto: Bool = false,
        isWatching: Bool = false
    ) {
        if inPlayback || gradesClip {
            liveIsPhoto = false
            refreshLUTCube()
            return
        }
        if isWatching {
            refreshLUTCube()
            return
        }
        syncLUT(to: live, family: family, cameraName: cameraName, isPhoto: isPhoto)
    }

    func refreshLUTCube() {
        inspectorLUTCache = nil
        guard lutEnabled, let cube = resolvedLUTCube() else {
            lutCube = nil
            lutDimension = 0
            lutRGBA = Data()
            return
        }
        cache(cube)
    }

    /// Resolves the same selected look for the main picture and a forced-on
    /// inspector. Calling this never changes enablement or preferences.
    private func resolvedLUTCube() -> CubeLUT? {
        switch resolvedSource() {
        case .official(let id):
            return BundledPocketLUT.cube(id)
        case .dji(let id):
            return BundledOfficialDJILUT.cube(id)
        case .lunaILog:
            return BundledLunaLUT.iLogToRec709
        case .creative(let look):
            return look.cube()
        case .custom(let slot):
            return CustomLUTStore.cube(slot)
        case .file(let name):
            return CustomLUTStore.cube(fileName: name)
        case .off:
            return nil
        }
    }

    func inspectorLUT(transfer: MonitorTransfer) -> (dimension: Int, rgba: Data) {
        if let cached = inspectorLUTCache,
            cached.selection == lutSelection, cached.transfer == transfer,
            cached.stops == lutExposureStops
        {
            return (cached.dimension, cached.rgba)
        }
        guard let cube = resolvedLUTCube() else { return (0, Data()) }
        let gpu = cube.colorCube.compensatingExposure(
            stops: lutExposureStops, transfer: transfer.lutExposureTransfer)
        let rgba = gpu.rgbaComponents.withUnsafeBytes { Data($0) }
        inspectorLUTCache = InspectorLUTCache(
            selection: lutSelection, stops: lutExposureStops, transfer: transfer,
            dimension: gpu.size, rgba: rgba)
        return (gpu.size, rgba)
    }

    private struct InspectorLUTCache {
        var selection: LUTSelection
        var stops: Double
        var transfer: MonitorTransfer
        var dimension: Int
        var rgba: Data
    }

    /// Import adds a custom cube. Auto rows keep following color; otherwise this file arms.
    func importCustom(fileName: String) {
        OperatorPrefs.selectedCustomFileName = fileName
        if lutSelection != .auto, lutSelection != .djiAuto {
            lutSelection = .customFile
            OperatorPrefs.lutSelection = .customFile
        }
        lutEnabled = true
        refreshLUTCube()
        OperatorPrefs.save(self)
    }

    func importCustom(slot: CustomLUTSlot, fileName: String) {
        OperatorPrefs.setCustomFileName(fileName, for: slot)
        importCustom(fileName: fileName)
    }

    func clearCustomSlot(_ slot: CustomLUTSlot) {
        if lutSelection == slot.selection
            || OperatorPrefs.selectedCustomFileName == OperatorPrefs.customFileName(for: slot)
        {
            lutSelection = .auto
            OperatorPrefs.lutSelection = .auto
            OperatorPrefs.selectedCustomFileName = nil
        }
        refreshLUTCube()
        OperatorPrefs.save(self)
    }

    func selectCustomFile(_ fileName: String) {
        OperatorPrefs.selectedCustomFileName = fileName
        selectLUT(.customFile)
    }

    func clearCustomFile(_ fileName: String) {
        if OperatorPrefs.selectedCustomFileName == fileName || lutSelection == .customFile {
            lutSelection = .auto
            OperatorPrefs.lutSelection = .auto
            OperatorPrefs.selectedCustomFileName = nil
        }
        for slot in CustomLUTSlot.allCases where OperatorPrefs.customFileName(for: slot) == fileName
        {
            OperatorPrefs.setCustomFileName(nil, for: slot)
        }
        try? CustomLUTStore.remove(StoredCustomLUT(fileName: fileName))
        refreshLUTCube()
        OperatorPrefs.save(self)
    }

    func cycleGuide() {
        let all = GuideAspect.ratios(for: guideFamily)
        guard let idx = all.firstIndex(of: guideAspect) else {
            guideAspect = all.first ?? .cinema
            selectedGuides = [guideAspect]
            guides = true
            OperatorPrefs.save(self)
            return
        }
        guideAspect = all[(idx + 1) % all.count]
        selectedGuides = [guideAspect]
        guides = true
        OperatorPrefs.save(self)
    }

    func toggleGuide(_ aspect: GuideAspect) {
        if selectedGuides.contains(aspect) {
            selectedGuides.remove(aspect)
        } else {
            selectedGuides.insert(aspect)
        }
        guideAspect = aspect
        guides = !selectedGuides.isEmpty
        OperatorPrefs.save(self)
    }

    func persist() {
        persistIfNeeded(force: true)
    }

    private func persistIfNeeded(force: Bool = false) {
        let data = OperatorPrefs.encoded(self)
        if !force, data == lastSaved { return }
        lastSaved = data
        OperatorPrefs.write(data)
    }

    /// Cube for share / export. Does not use the GPU `lutRGBA` table so
    /// Bake exposure can stay off while the monitor still shows the pull.
    func exportLUTCube(bakeExposure: Bool) -> CubeLUT? {
        guard lutEnabled, let cube = lutCube else { return nil }
        let color = PlaybackLUTColor.resolve(
            clip: monitorColorMode,
            live: monitorColorMode,
            last: OperatorPrefs.lastMonitorColorMode)
        return cube.preparedForExport(
            bakeExposure: bakeExposure,
            stops: lutExposureStops,
            transfer: MonitorTransfer(color ?? .normal).lutExposureTransfer)
    }

    private func cache(_ cube: CubeLUT) {
        lutCube = cube
        let transfer = MonitorTransfer(monitorColorMode ?? .normal)
        let gpu = cube.colorCube.compensatingExposure(
            stops: lutExposureStops, transfer: transfer.lutExposureTransfer)
        lutDimension = gpu.size
        lutRGBA = gpu.rgbaComponents.withUnsafeBytes { Data($0) }
    }
}

struct FeedAlignedAssists: View {
    var grid: Bool
    var crosshair: Bool
    var guides: Bool
    var guideAspect: GuideAspect
    var focusPoint: CGPoint
    var overlay: FocusOverlay = .focus
    var sceneFaces: [TrackingBox] = []
    var showFocusChrome = true
    var showTapFocusBox = true
    /// AE lock: the focus / metering box turns yellow with an `AE-L` tag.
    var aeLocked = false
    /// Long-press lock on the tap-focus box: a lock tag at its lower corner.
    var focusLocked = false
    /// When set (letterboxed clip playback), framing overlays align to this rect
    /// instead of the full geometry — OpenZCine `FeedAlignedAssists(feed:)`.
    var feed: CGRect? = nil
    /// Decoded raster aspect before the optical correction.
    var sourceAspect: CGFloat? = nil
    /// Recorded frame width/height. Live 1:1 sits as a square inside a 16:9 well.
    var pictureAspect: CGFloat? = nil
    /// Live 180 / MIRROR compose. Nil uses the assist chip only (playback).
    var pictureMirrored: Bool? = nil
    /// MIRROR Vertical. Nil uses the assist chip only.
    var pictureFlippedVertically: Bool? = nil
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            let assist = model.assist
            let mirrored = pictureMirrored ?? assist.mirrorsHorizontally
            let flippedV = pictureFlippedVertically ?? assist.flipsVertically
            let shown = { (box: TrackingBox) in
                box.flipped(horizontal: mirrored, vertical: flippedV)
            }
            let shownFocus = CGPoint(
                x: mirrored ? 1 - focusPoint.x : focusPoint.x,
                y: flippedV ? 1 - focusPoint.y : focusPoint.y)
            // Live: framing aids sit on the de-squeezed picture. Playback already
            // letterboxes the raster (`feed`); do not re-apply live desqueeze there.
            let feed =
                self.feed
                ?? overlayFeedRect(
                    CGRect(origin: .zero, size: proxy.size), assist, pictureAspect: pictureAspect,
                    sourceAspect: sourceAspect)
            let focusFeed =
                self.feed
                ?? DesqueezeAssist.presentationRect(
                    sourceSize: sourceAspect.map { CGSize(width: $0, height: 1) } ?? proxy.size,
                    in: CGRect(origin: .zero, size: proxy.size), effects: assist.effects)
            let marks = trackingMarks(shown: shown, focus: shownFocus)
            ZStack {
                if guides {
                    GuidesAssist.overlay(feed: feed, assist: assist, fallback: guideAspect)
                }
                if grid {
                    FeedGridView(
                        feed: feed,
                        thirds: assist.gridThirds,
                        phi: assist.gridPhi,
                        diagonal: assist.gridDiagonal
                    )
                }
                if crosshair { FeedCrosshairView(feed: feed) }
                if assist.splitComparison, assist.isVisible(.lut) {
                    FeedSplitComparisonMarks(vertical: assist.splitVertical, feed: feed)
                }
                MonitorTrackingLayer(brackets: marks.brackets, focus: marks.focus, feed: focusFeed)
            }
        }
        .allowsHitTesting(false)
    }

    private func trackingMarks(shown: (TrackingBox) -> TrackingBox, focus: CGPoint) ->
        (brackets: [MonitorTrackingBracketValue], focus: MonitorFocusMark?) {
        func bracket(_ box: TrackingBox, _ color: Color, _ width: CGFloat) -> MonitorTrackingBracketValue {
            let drawn = shown(box)
            return .init(normalizedRect: CGRect(x: drawn.x, y: drawn.y, width: drawn.width, height: drawn.height),
                color: color, lineWidth: width)
        }
        var brackets = sceneFaces.map { bracket($0, LiveDesign.text.opacity(SceneFacePolicy.dimOpacity), 1.6) }
        var focusMark: MonitorFocusMark?
        if showFocusChrome {
            switch overlay {
            case .search(let box):
                brackets.append(bracket(box, LiveDesign.text.opacity(0.88), 1.5))
                focusMark = .init(point: focus, color: aeLocked ? LiveDesign.aeLock : LiveDesign.accent, aeLocked: aeLocked)
            case .subject(let box): brackets.append(bracket(box, LiveDesign.good, 2))
            case .face(let box): brackets.append(bracket(box, LiveDesign.text.opacity(0.92), 1.6))
            case .focus:
                if showTapFocusBox || aeLocked {
                    focusMark = .init(point: focus, color: aeLocked ? LiveDesign.aeLock : LiveDesign.accent,
                        aeLocked: aeLocked, focusLocked: focusLocked)
                }
            }
        }
        return (brackets, focusMark)
    }

}

/// OpenZCine `desqueezedRect` — framing aids sit on the visible (shrunk) picture, not the full frame.
func overlayFeedRect(
    _ full: CGRect, _ assist: LiveAssistState, pictureAspect: CGFloat?,
    sourceAspect: CGFloat? = nil
) -> CGRect {
    let effects = assist.effects
    let raster = DesqueezeAssist.presentationRect(
        sourceSize: sourceAspect.map { CGSize(width: $0, height: 1) } ?? full.size,
        in: full, effects: effects)
    guard let pictureAspect, pictureAspect > 0 else { return raster }
    // The recorded picture may be letterboxed inside the camera's live raster.
    return DesqueezeAssist.presentationRect(
        sourceSize: CGSize(width: pictureAspect, height: 1), in: raster, effects: effects)
}

private func feedRect(_ box: TrackingBox, in feed: CGRect) -> CGRect {
    CGRect(
        x: feed.minX + box.x * feed.width,
        y: feed.minY + box.y * feed.height,
        width: max(1, box.width * feed.width),
        height: max(1, box.height * feed.height)
    )
}

enum LiveTrackingChrome {
    static let cancelSize = MonitorTrackingGeometry.cancelSize
    static let cancelHitSize = MonitorTrackingGeometry.cancelHitSize
    static func cornerRadius(for rect: CGRect) -> CGFloat { MonitorTrackingGeometry.cornerRadius(for: rect) }
    static func cancelRect(box: TrackingBox, feed: CGRect, mirrored: Bool, flippedVertically: Bool = false) -> CGRect {
        MonitorTrackingGeometry.cancelRect(for: feedRect(box.flipped(horizontal: mirrored, vertical: flippedVertically), in: feed))
    }
    static func bracketArm(along length: CGFloat) -> CGFloat { MonitorTrackingGeometry.bracketArm(along: length) }
    static func bracketPath(in size: CGSize) -> Path { MonitorTrackingGeometry.bracketPath(in: size) }
}

typealias FeedGridView = MonitorFeedGrid

typealias FeedCrosshairView = MonitorFeedCrosshair

typealias FeedSplitComparisonMarks = MonitorFeedComparisonMarks

/// Camera attitude sampling stays in the source adapter; shared UI receives resolved values.
enum LevelAssist {
    static let refresh: TimeInterval = 0.1
    static let rollLiftLandscape = MonitorLevelGeometry.rollLiftLandscape
    static let rollLiftPortrait = MonitorLevelGeometry.rollLiftPortrait

    @MainActor static func frames(feed: CGRect, viewport: CGRect, portrait: Bool) -> (roll: CGRect, tilt: CGRect) {
        MonitorLevelGeometry.frames(feed: feed, viewport: viewport, portrait: portrait)
    }

    static func display(_ mode: LevelReading.Mode) -> MonitorLevelDisplay {
        switch mode {
        case .unavailable: .unavailable
        case .gauges(let roll, let tilt): .gauges(rollDeg: roll, tiltDeg: tilt)
        case .bubble(let x, let y): .bubble(xDeg: x, yDeg: y)
        }
    }

    static func accessibilityValue(_ mode: LevelReading.Mode) -> String {
        MonitorLevelGeometry.accessibilityValue(display(mode), noDataLabel: WorldLevelSnap.noLevelData)
    }
}

struct FeedLevelView: View {
    let feed: CGRect
    let viewport: CGRect
    let portrait: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: LevelAssist.refresh)) { _ in
            let mode = model.session.levelReading.mode(
                now: ProcessInfo.processInfo.systemUptime,
                // Picture-relative like the stick: TT180 mirrors the shown
                // picture in both Selfie Flip states. Either flip axis reverses
                // the on-screen roll; both (180°) restores it.
                viewFlip: GimbalStick.liveInvertPan(
                    poseInvert: model.session.gimbalPoseInvertPan,
                    assistMirror: model.assist.mirrorsHorizontally)
                    != model.assist.flipsVertically)
            MonitorLevelOverlay(display: LevelAssist.display(mode), feed: feed, viewport: viewport,
                portrait: portrait, noDataLabel: WorldLevelSnap.noLevelData)
        }
        .allowsHitTesting(false)
    }
}

/// WAVE / PARADE / HISTO / VECTOR / LIGHTS live in `LiveScopes.swift`.
/// AUDIO meters live in `Assists/AudioAssist.swift` (`AudioMetersPanelMini`).

/// OpenZCine `FalseColorReference` on the live feed.
struct FalseColorLegend: View {
    var scale: FalseColorScaleKind
    var colorMode: ColorMode = .normal
    var rec709: Bool
    var clipByte: Int

    var body: some View {
        FalseColorAssist.referenceDisplay(
            scale: scale, colorMode: colorMode, rec709: rec709, clipByte: clipByte
        )
        .allowsHitTesting(false)
    }
}

struct AssistToolRow: View {
    @Bindable var assist: LiveAssistState
    var isLocked = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LiveAssistTool.settingsCases.filter { $0 != .audioMeters || assist.cameraHasAudio }) { tool in
                    Button {
                        guard !isLocked else { return }
                        assist.toggle(tool)
                    } label: {
                        AssistToolChip(tool: tool, isOn: assist.isOn(tool))
                    }
                    .buttonStyle(.zcTapTarget)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.25).onEnded { _ in
                            guard !isLocked, tool.hasConfiguration else { return }
                            assist.configureTool = tool
                            if tool == .lut { assist.showLUTPicker = false }
                        }
                    )
                }
            }
            .padding(.horizontal, 2)
        }
        .monitorScrollFade(.horizontal)
        .allowsHitTesting(!isLocked)
    }
}

struct AssistToolChip: View {
    let tool: LiveAssistTool
    let isOn: Bool
    var compact = false

    var body: some View {
        VStack(spacing: 3) {
            AssistToolIcon(tool: tool, size: 19)
                .frame(height: 23)
            Text(tool.rawValue)
                .font(MonitorTheme.font(9, weight: .medium)).monospacedDigit()
                .tracking(0.9)
                .lineLimit(1)
        }
        .foregroundStyle(isOn ? LiveDesign.accent : LiveDesign.muted)
        .padding(.vertical, 5)
        .padding(.horizontal, compact ? 5 : 8)
        .frame(minWidth: compact ? 48 : 52)
        .background {
            RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous)
                .fill(isOn ? LiveDesign.accentDim : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous)
                .strokeBorder(isOn ? LiveDesign.accent : Color.clear, lineWidth: 1)
        }
    }
}

struct AssistToolIcon: View {
    let tool: LiveAssistTool
    /// Shared palettes supply their own size; legacy standalone chips keep 19 points.
    var size: CGFloat? = 19

    var body: some View {
        if let shared = tool.sharedTool {
            MonitorAssistToolGlyph(tool: shared, size: size)
        } else if let icon = tool.opcIcon {
            icon.frame(width: size, height: size)
        }
    }
}
