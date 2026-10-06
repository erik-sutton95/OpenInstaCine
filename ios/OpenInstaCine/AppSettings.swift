import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineCameraControls
import OpenPocketViewCore
import SwiftUI
import UIKit

typealias PocketDispMode = MonitorDisplayMode
typealias PocketDispChrome = MonitorDisplayChrome

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
        .buttonStyle(.monitorTapTarget)
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

typealias OperatorSettingsHaptics = OpenCineCameraControls.OperatorSettingsHaptics

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

struct SettingsLinkHealthCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let bars = model.session.liveSignalBars
        let score = min(4, max(0, bars)) * 25
        MonitorLinkHealthScale(title: "Link Health", caption: caption, score: score)
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
                        .font(MonitorTheme.font(10, weight: .semibold))
                        .tracking(1.3)
                        .foregroundStyle(StartupColors.muted)
                    Text(title)
                        .font(MonitorTheme.font(17, weight: .bold))
                        .foregroundStyle(StartupColors.ink)
                }
                Spacer()
                Button("Done", action: onClose)
                    .font(MonitorTheme.font(16, weight: .semibold))
                    .foregroundStyle(StartupColors.darkText)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        StartupColors.accent,
                        in: RoundedRectangle(cornerRadius: MonitorTheme.radius)
                    )
                    .buttonStyle(.monitorTapTarget)
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
