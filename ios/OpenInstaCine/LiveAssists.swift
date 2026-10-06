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

typealias FeedAlignedAssists = FeedAssistMarks<AppModel>

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
