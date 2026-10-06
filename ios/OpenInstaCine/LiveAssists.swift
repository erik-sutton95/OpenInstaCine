import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineCameraControls
import OpenCineMedia
import Observation
import OpenPocketViewCore
import SwiftUI
import UIKit

/// Cinema live-monitor set. MAG is retired; PLAY stays off the video toolbar.
typealias LiveAssistTool = MonitorAssistSelection

extension MonitorAssistSelection {
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

/// Catalog and camera source interpretation belong to the app; shared state receives media values.
@MainActor @Observable
final class AppMonitorLooks: MonitorLookProvider {
    var lutSelection: LUTSelection = .djiAuto
    var monitorColorMode: ColorMode?
    var monitorFamily: CameraBodyFamily = .pocket
    var monitorCameraName: String?
    var liveIsPhoto = false
    var referenceClipByte: Int { ScopeExposureCeiling.referenceClipByte(transfer: transfer) }
    func lutExposureTransfer(for transfer: MonitorTransfer) -> MonitorTransfer { transfer.lutExposureTransfer }
    var selection: LUTSelection { lutSelection }
    var transfer: MonitorTransfer { MonitorTransfer(monitorColorMode ?? .normal) }
    func statusLabel(enabled: Bool) -> String {
        if liveIsPhoto, enabled, lutSelection == .auto || lutSelection == .djiAuto {
            return "Auto · Rec.709"
        }
        return LUTResolver.statusLabel(enabled: enabled, selection: lutSelection, source: resolvedSource())
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

    var cube: CubeLUT? {
        switch resolvedSource() {
        case .official, .dji:
            // No Pocket or DJI cube ships with this app.
            return nil
        case .iLogRec709:
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

}

typealias LiveAssistState = MonitorAssistState<AppMonitorLooks>

extension MonitorAssistState where Looks == AppMonitorLooks {
    convenience init() {
        self.init(looks: AppMonitorLooks(), storage: .standard, keys: .init(
            assist: "OpenInstaCine.Assist.v1", cleanPins: "OpenInstaCine.CleanViewPins.v1",
            playback: "OpenInstaCine.PlaybackAssists.v1"),
            cleanPinCases: LiveAssistTool.cleanPinCases)
        OperatorPrefs.load(into: self)
        if monitorColorMode == nil { monitorColorMode = OperatorPrefs.lastMonitorColorMode }
        refreshLUTCube()
    }
    var lutSelection: LUTSelection {
        get { looks.lutSelection }
        set { looks.lutSelection = newValue }
    }
    var monitorColorMode: ColorMode? {
        get { looks.monitorColorMode }
        set { looks.monitorColorMode = newValue }
    }
    var monitorFamily: CameraBodyFamily {
        get { looks.monitorFamily }
        set { looks.monitorFamily = newValue }
    }
    var monitorCameraName: String? {
        get { looks.monitorCameraName }
        set { looks.monitorCameraName = newValue }
    }
    var liveIsPhoto: Bool {
        get { looks.liveIsPhoto }
        set { looks.liveIsPhoto = newValue; allowsTransferInference = !newValue }
    }
    var lutStatusLabel: String { looks.statusLabel(enabled: lutEnabled) }
    func resolvedSource() -> LUTSource { looks.resolvedSource() }
    var longPressAnchor: CGRect {
        get { CGRect(x: longPressAnchorRect.x, y: longPressAnchorRect.y,
            width: longPressAnchorRect.width, height: longPressAnchorRect.height) }
        set { longPressAnchorRect = MonitorRect(newValue) }
    }
    /// Picking a look turns LUT on. Auto stays Auto until the operator picks something else.
    func selectLUT(_ selection: LUTSelection) {
        lutSelection = selection
        lutEnabled = true
        OperatorPrefs.lutSelection = selection
        refreshLUTCube()
        persist()
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

    /// Import adds a custom cube. Auto rows keep following color; otherwise this file arms.
    func importCustom(fileName: String) {
        OperatorPrefs.selectedCustomFileName = fileName
        if lutSelection != .auto, lutSelection != .djiAuto {
            lutSelection = .customFile
            OperatorPrefs.lutSelection = .customFile
        }
        lutEnabled = true
        refreshLUTCube()
        persist()
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
        persist()
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
        persist()
    }

    func exportLUTCube(bakeExposure: Bool) -> CubeLUT? {
        let color = PlaybackLUTColor.resolve(clip: monitorColorMode, live: monitorColorMode,
            last: OperatorPrefs.lastMonitorColorMode)
        return exportCube(bakeExposure: bakeExposure, transfer: MonitorTransfer(color ?? .normal))
    }
}

struct FeedAlignedAssists: View {
    var grid: Bool
    var crosshair: Bool
    var guides: Bool
    var guideAspect: MonitorGuideAspect
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
                    MonitorFeedGrid(
                        feed: feed,
                        thirds: assist.gridThirds,
                        phi: assist.gridPhi,
                        diagonal: assist.gridDiagonal
                    )
                }
                if crosshair { MonitorFeedCrosshair(feed: feed) }
                if assist.splitComparison, assist.isVisible(.lut) {
                    MonitorFeedComparisonMarks(vertical: assist.splitVertical, feed: feed)
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
@MainActor func overlayFeedRect(
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
                    .buttonStyle(.monitorTapTarget)
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
