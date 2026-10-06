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

/// This app's LUT looks: its official cubes, saved choices and custom LUT folder.
extension MonitorLUTLooks {
    convenience init() {
        self.init(official: .app, preferences: .app, customLUTs: .app)
    }
}

typealias LiveAssistState = MonitorAssistState<MonitorLUTLooks>

extension MonitorAssistState where Looks == MonitorLUTLooks {
    convenience init() {
        self.init(looks: MonitorLUTLooks(), storage: .standard, keys: .init(
            assist: "OpenInstaCine.Assist.v1", cleanPins: "OpenInstaCine.CleanViewPins.v1",
            playback: "OpenInstaCine.PlaybackAssists.v1"),
            cleanPinCases: LiveAssistTool.cleanPinCases)
        OperatorPrefs.load(into: self)
        if monitorColorMode == nil { monitorColorMode = LUTPreferences.app.lastMonitorColorMode }
        refreshLUTCube()
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
            scale: scale, colorMode: colorMode, rec709: rec709, clipByte: clipByte,
            looks: .app
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
        } else if let icon = tool.lucideIcon {
            icon.frame(width: size, height: size)
        }
    }
}
