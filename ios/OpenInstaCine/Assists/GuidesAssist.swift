import MonitorUI
import SwiftUI

/// OpenZCine `AssistPanel` `.guides` body + `AspectGuideFrameView`.
///
/// Long-press options (no title-safe / action-safe — OpenZCine does not offer those):
/// - Film / Social family tabs
/// - Multi-select aspect chips for the active tab
/// - "Mask outside frame" (darkens the inverse of the union)
enum GuidesAssist {
    @MainActor
    @ViewBuilder
    static func longPressMenu(assist: LiveAssistState) -> some View {
        GuidesLongPressMenu(assist: assist)
    }

    @MainActor
    @ViewBuilder
    static func longPressMenu(_ assist: LiveAssistState) -> some View {
        GuidesLongPressMenu(assist: assist)
    }

    @MainActor
    @ViewBuilder
    static func overlay(feed: CGRect, assist: LiveAssistState, fallback: GuideAspect) -> some View {
        AspectGuideFrameView(
            selectedRatios: assist.selectedGuides.isEmpty ? [fallback] : assist.selectedGuides,
            maskEnabled: assist.guideMask,
            feed: feed
        )
    }

    /// OpenZCine `AssistConfiguration.Guides.summaryLabel`.
    static func summaryLabel(for selected: Set<GuideAspect>) -> String {
        if selected.count == 1 { return selected.first?.rawValue ?? "—" }
        return selected.isEmpty ? "—" : "\(selected.count) ratios"
    }

    /// Centered guide geometry comes from the common monitor UI.
    static func rectForRatio(_ feed: CGRect, _ ratio: CGFloat) -> CGRect {
        MonitorGuideGeometry.rectForRatio(feed, ratio)
    }
}

/// OpenZCine `AssistPanel` `case .guides` — family tabs, 5-column chips, mask row.
private struct GuidesLongPressMenu: View {
    @Bindable var assist: LiveAssistState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsInlineRow(title: "Family", showTopDivider: false) {
                MonitorCaptureTabs(
                    options: GuideFamily.allCases.map(\.rawValue),
                    selection: assist.guideFamily.rawValue, title: { $0 }
                ) { value in
                    guard let family = GuideFamily(rawValue: value), family != assist.guideFamily
                    else { return }
                    OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
                    assist.guideFamily = family
                    assist.persist()
                }
            }
            SettingsInlineRow(title: "Ratios", stacked: true) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 6)], spacing: 6) {
                    MonitorSnapshotRows(GuideAspect.ratios(for: assist.guideFamily)) { ratio in
                        Button {
                            OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
                            assist.toggleGuide(ratio)
                        } label: {
                            GuidesGlassChoice(
                                title: ratio.rawValue,
                                isSelected: assist.selectedGuides.contains(ratio))
                        }
                        .buttonStyle(.zcTapTarget)
                        .accessibilityAddTraits(
                            assist.selectedGuides.contains(ratio) ? .isSelected : [])
                    }
                }
            }
            SettingsSwitchInlineRow(title: "Mask outside frame", isOn: assist.guideMask) {
                OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
                assist.guideMask.toggle()
                assist.persist()
            }
        }
    }
}

/// Native guide rendering and the union mask belong to the common monitor UI.
typealias AspectGuideFrameView = MonitorAspectGuideFrames

/// OpenZCine `GlassChoice`.
private struct GuidesGlassChoice: View {
    let title: String
    var isSelected = false

    var body: some View {
        Text(title)
            .font(MonitorTheme.font(11, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .allowsTightening(true)
            .foregroundStyle(
                isSelected ? Color(red: 8 / 255, green: 25 / 255, blue: 31 / 255) : LiveDesign.text
            )
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 36)
            .background(
                isSelected ? LiveDesign.accent : LiveDesign.glassBright,
                in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
                    .stroke(isSelected ? LiveDesign.accentDim : LiveDesign.hairline, lineWidth: 1)
            )
    }
}
