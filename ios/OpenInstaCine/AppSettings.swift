import MonitorPresentation
import MonitorUI
import OpenPocketViewCore
import SwiftUI
import UIKit

/// DISP 1 Live / DISP 2 Clean. Command (DISP 3) is not in this build.
enum PocketDispMode: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case live
    case clean

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "Live"
        case .clean: "Clean"
        }
    }

    var settingsTitle: String {
        switch self {
        case .live: "DISP 1 · Live"
        case .clean: "DISP 2 · Clean"
        }
    }

    var settingsCaption: String {
        switch self {
        case .live:
            "The full monitor. Set what it shows in Edit view."
        case .clean:
            "A stripped-back image. Same elements as DISP 1 — status, tool and capture bars start off. Pin which view assists stay on."
        }
    }
}

/// Per-DISP chrome map for Pocket live / clean.
struct PocketDispChrome: Equatable, Codable, Sendable {
    /// Containers first, then rail / on-feed chrome, then status-bar cells last so
    /// Edit-view badges keep the big boxes' preferred corners.
    enum Section: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
        case statusBar
        case toolBar
        case cameraValues
        case lockButton
        case batteries
        case railRecord
        case railMedia
        case railSettings
        case zoomChip
        case gimbalStick
        case focusBox
        case recReadout
        case timecode
        case format
        case color
        case storage
        case fps

        var id: String { rawValue }

        var title: String {
            switch self {
            case .statusBar: "Status Bar"
            case .toolBar: "Tool Bar"
            case .cameraValues: "Camera Values"
            case .lockButton: "Lock Button"
            case .batteries: "Batteries"
            case .railRecord: "Record"
            case .railMedia: "Media"
            case .railSettings: "Settings"
            case .zoomChip: "Zoom Chip"
            case .gimbalStick: "Gimbal Stick"
            case .focusBox: "Face Box"
            case .recReadout: "REC"
            case .timecode: "Timecode"
            case .format: "Format"
            case .color: "Color"
            case .storage: "Storage"
            case .fps: "FPS"
            }
        }
    }

    var statusBar = true
    var toolBar = true
    var cameraValues = true
    var lockButton = true
    var batteries = true
    var recReadout = true
    var timecode = true
    var format = true
    var color = true
    var storage = true
    var fps = true
    var railRecord = true
    var railMedia = true
    var railSettings = true
    var zoomChip = true
    var gimbalStick = true
    var focusBox = true

    static let liveDefaults = PocketDispChrome()

    static let cleanDefaults = PocketDispChrome(
        statusBar: false,
        toolBar: false,
        cameraValues: false,
        lockButton: false,
        batteries: true,
        recReadout: true,
        timecode: true,
        format: true,
        color: true,
        storage: true,
        fps: true,
        railRecord: true,
        railMedia: true,
        railSettings: true,
        zoomChip: true,
        gimbalStick: true,
        focusBox: true
    )

    func isVisible(_ section: Section) -> Bool {
        switch section {
        case .statusBar: statusBar
        case .toolBar: toolBar
        case .cameraValues: cameraValues
        case .lockButton: lockButton
        case .batteries: batteries
        case .railRecord: railRecord
        case .railMedia: railMedia
        case .railSettings: railSettings
        case .zoomChip: zoomChip
        case .gimbalStick: gimbalStick
        case .focusBox: focusBox
        case .recReadout: recReadout
        case .timecode: timecode
        case .format: format
        case .color: color
        case .storage: storage
        case .fps: fps
        }
    }

    mutating func toggle(_ section: Section) {
        switch section {
        case .statusBar: statusBar.toggle()
        case .toolBar: toolBar.toggle()
        case .cameraValues: cameraValues.toggle()
        case .lockButton: lockButton.toggle()
        case .batteries: batteries.toggle()
        case .railRecord: railRecord.toggle()
        case .railMedia: railMedia.toggle()
        case .railSettings: railSettings.toggle()
        case .zoomChip: zoomChip.toggle()
        case .gimbalStick: gimbalStick.toggle()
        case .focusBox: focusBox.toggle()
        case .recReadout: recReadout.toggle()
        case .timecode: timecode.toggle()
        case .format: format.toggle()
        case .color: color.toggle()
        case .storage: storage.toggle()
        case .fps: fps.toggle()
        }
    }

    /// Live and clean offer the same list — clean is DISP 1 with different defaults.
    static func isConfigurable(_ section: Section, in mode: PocketDispMode) -> Bool {
        _ = section
        _ = mode
        return true
    }

    static func configurableSections(in mode: PocketDispMode) -> [Section] {
        Section.allCases.filter { isConfigurable($0, in: mode) }
    }
}

enum OpenInstaCineLinks {
    static let source = URL(string: "https://github.com/erik-sutton95/OpenInstaCine")
    static let support = URL(
        string: "https://github.com/erik-sutton95/OpenInstaCine/discussions/categories/q-a")
    static let reportProblem = URL(
        string: "https://github.com/erik-sutton95/OpenInstaCine/issues/new?template=bug_report.yml"
    )
    static let featureRequest = URL(
        string: "https://github.com/erik-sutton95/OpenInstaCine/discussions/new?category=ideas")
    static let privacy = URL(string: "https://opencapture.org/openinstacine/privacy")
    static let terms = URL(string: "https://opencapture.org/openinstacine/terms")
}

/// Live chrome and home both present this. `onClose` lets the live monitor dismiss its own cover.
struct AppSettingsView: View {
    /// OpenZCine `OperatorSettingsPanel.safeArea` — processed landscape insets from the host.
    var safeArea: EdgeInsets = EdgeInsets()
    var onClose: (() -> Void)? = nil

    var body: some View {
        SettingsRootView(safeArea: safeArea, onClose: onClose)
    }
}

// MARK: - Shared Operator Setup / Media chrome

struct CloseButton: View {
    var action: () -> Void
    var size: CGFloat = 34

    var body: some View {
        Button(action: action) {
            OpcIcon.x
                .frame(width: size * 0.38, height: size * 0.38)
                .foregroundStyle(LiveDesign.text)
                .frame(width: size, height: size)
                .glassCircle(interactive: true)
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel("Close")
    }
}

typealias HelpBadge = MonitorSettingsHelpBadge
typealias SettingsInlineRow<Trailing: View> = MonitorSettingsInlineRow<Trailing>
typealias SettingsValueText = MonitorSettingsValueText

/// Compact mono value field with a number pad and a Done accessory.
typealias SettingsNumberField = MonitorSettingsNumberField
typealias SettingsActionPill = MonitorSettingsActionPill

typealias SettingsSwitchGraphic = MonitorSettingsSwitchGraphic

typealias DisplayToggleItem = MonitorSettingsDisplayToggle

struct SettingsSwitchInlineRow: View {
    let title: String
    var help: String? = nil
    var showTopDivider = true
    var stacked = false
    let isOn: Bool
    var identifier: String? = nil
    let action: () -> Void

    var body: some View {
        MonitorSettingsSwitchInlineRow(
            title: title, help: help, showTopDivider: showTopDivider, stacked: stacked,
            isOn: isOn, identifier: identifier,
            feedback: { OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled) },
            action: action)
    }
}

struct SettingsSegmented: View {
    let options: [String]
    let selected: String
    var compact: Bool = false
    var stacked: Bool = false
    let onSelect: (String) -> Void

    var body: some View {
        MonitorSegmentedControl(
            options: options, selection: Binding(get: { selected }, set: onSelect),
            compact: compact, stacked: stacked, title: { $0 },
            onSelectionFeedback: {
                OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
            }
        )
        .buttonStyle(.zcTapTarget)
    }
}

struct SettingsResetButton: View {
    @Environment(AppModel.self) private var model
    let action: () -> Void
    var body: some View {
        MonitorSettingsResetButton(
            feedback: { OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled) },
            action: action)
    }
}

enum OperatorSettingsHaptics {
    @MainActor
    static func selection(enabled: Bool) {
        guard enabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
}

struct SettingsRowCard<Content: View>: View {
    @Environment(AppModel.self) private var model
    let title: String?
    let onReset: (() -> Void)?
    let content: Content
    init(title: String? = nil, onReset: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.onReset = onReset; self.content = content()
    }
    var body: some View {
        MonitorSettingsRowCard(
            title: title, onReset: onReset,
            feedback: { OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled) }
        ) { content }
    }
}

typealias SettingsTabScrollArea<Content: View> = MonitorSettingsTabScrollArea<Content>

typealias SettingsDashScale = MonitorLinkHealthScale

struct SettingsLinkHealthCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let bars = model.session.liveSignalBars
        let score = min(4, max(0, bars)) * 25
        SettingsDashScale(title: "Link Health", caption: caption, score: score)
    }

    private var caption: String {
        if !model.isLive { return "No live path." }
        let bars = model.session.liveSignalBars
        guard bars > 0 else { return "Waiting for the link." }
        switch MonitorLinkHealthBand(bars: bars) {
        case .stable: return "Link is clean. · Stable"
        case .watch: return "Some loss on the link. · Watch"
        case .poor: return "Link is weak. · Poor"
        }
    }
}

enum OperatorPanelMetrics {
    static let closeSize: CGFloat = 37
    static let closeLeading: CGFloat = 16
    static let topStackWidth: CGFloat = 560

    static func topPadding(safeArea: EdgeInsets) -> CGFloat {
        max(safeArea.top + 6, 16)
    }

    /// OpenZCine `OperatorSettingsPanel` top floor is 14, not the shared 16 used by Media/Legal.
    static func settingsTopPadding(safeArea: EdgeInsets) -> CGFloat {
        max(safeArea.top + 6, 14)
    }

    static func closeTopPadding(safeArea: EdgeInsets) -> CGFloat {
        max(safeArea.top + 6, 22)
    }

    static func leadingPadding(safeArea: EdgeInsets, floor: CGFloat = 16) -> CGFloat {
        max(safeArea.leading + 6, floor)
    }

    static func trailingPadding(safeArea: EdgeInsets) -> CGFloat {
        max(safeArea.trailing + 6, 16)
    }

    static func bottomPadding(safeArea: EdgeInsets) -> CGFloat {
        max(safeArea.bottom + 4, 12)
    }

    /// Extra leading inset so a landscape title clears the floating close button.
    static func closeButtonClearance(safeArea: EdgeInsets) -> CGFloat {
        max(0, (closeLeading + closeSize + 8) - leadingPadding(safeArea: safeArea))
    }

    /// OpenZCine `MonitorFullScreenPanelOverlay.fullScreenPanelSafeArea`.
    /// Landscape zeros the clean short edge so the surface hugs that bezel while clearing
    /// the Dynamic Island on the side it sits. Portrait passes the insets through.
    static func fullScreenPanelSafeArea(
        from insets: EdgeInsets,
        isPortrait: Bool,
        mirrored: Bool
    ) -> EdgeInsets {
        guard !isPortrait else { return insets }
        return EdgeInsets(
            top: insets.top,
            leading: mirrored ? 0 : insets.leading,
            bottom: insets.bottom,
            trailing: mirrored ? insets.trailing : 0
        )
    }

    /// OpenZCine standalone Operator Setup host (`NativeAppRoot` ~13136).
    /// iOS reports the landscape island lane on both short edges; zero the smaller side.
    static func standalonePanelSafeArea(from insets: EdgeInsets) -> EdgeInsets {
        let islandOnLeading = insets.leading >= insets.trailing
        return EdgeInsets(
            top: insets.top,
            leading: islandOnLeading ? insets.leading : 0,
            bottom: insets.bottom,
            trailing: islandOnLeading ? 0 : insets.trailing
        )
    }

    /// Merge the host's layout clearance with an observed physical window snapshot.
    /// Never query UIKit here: its getter can reenter SwiftUI layout on iOS 26.
    static func resolvedDeviceSafeArea(
        _ proposed: EdgeInsets, window: EdgeInsets
    ) -> EdgeInsets {
        // A full-screen overlay may erase all SwiftUI safe insets. Resolve each
        // edge so portrait camera islands and home indicators receive the same
        // protection as the landscape camera cutout.
        return EdgeInsets(
            top: max(proposed.top, window.top),
            leading: max(proposed.leading, window.leading),
            bottom: max(proposed.bottom, window.bottom),
            trailing: max(proposed.trailing, window.trailing))
    }
}

struct AppPanelChrome<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("OPENINSTACINE")
                        .font(LiveType.ui(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.3)
                        .foregroundStyle(StartupColors.muted)
                    Text(title)
                        .font(LiveType.ui(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(StartupColors.ink)
                }
                Spacer()
                Button("Done", action: onClose)
                    .font(LiveType.ui(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(StartupColors.darkText)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        StartupColors.accent,
                        in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                    )
                    .buttonStyle(.zcTapTarget)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView {
                content
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
            }
            .monitorScrollFade()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StartupColors.backdrop.ignoresSafeArea())
        .foregroundStyle(StartupColors.ink)
        .preferredColorScheme(.dark)
    }
}
