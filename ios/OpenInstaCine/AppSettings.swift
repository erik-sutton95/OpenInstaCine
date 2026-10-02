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
/// OpenZCine `SettingsNumberField` (`settings-num`). Used by any assist
/// numeric editor (Zebra Highlight / Midtone today) so IME chrome is shared.
struct SettingsNumberField: View {
    @Binding var value: Int
    var maximum: Int = 100

    static let doneTitle = "Done"

    var body: some View {
        SettingsNumberPadInput(value: $value, maximum: maximum)
            .frame(width: 44, height: 30)
            .background(
                LiveDesign.background.opacity(0.5),
                in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                    .stroke(LiveDesign.hairline, lineWidth: 1)
            )
    }
}

/// Number pad has no Return. A UIKit accessory is the reliable Done control
/// outside a NavigationStack (live / playback assist overlays).
private struct SettingsNumberPadInput: UIViewRepresentable {
    @Binding var value: Int
    var maximum: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, maximum: maximum)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = .numberPad
        field.textAlignment = .center
        _ = MonitorTheme.font(12, weight: .semibold)
        field.font =
            UIFont(name: "Sora-SemiBold", size: 12)
            ?? UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        field.textColor = UIColor(LiveDesign.text)
        field.tintColor = UIColor(LiveDesign.accent)
        field.backgroundColor = .clear
        field.borderStyle = .none
        field.delegate = context.coordinator
        field.text = String(value)
        field.accessibilityValue = String(value)
        field.inputAccessoryView = context.coordinator.makeDoneBar()
        field.addTarget(
            context.coordinator, action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged)
        context.coordinator.field = field
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.value = $value
        context.coordinator.maximum = maximum
        if !field.isFirstResponder, field.text != String(value) {
            field.text = String(value)
            field.accessibilityValue = String(value)
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var value: Binding<Int>
        var maximum: Int
        weak var field: UITextField?

        init(value: Binding<Int>, maximum: Int) {
            self.value = value
            self.maximum = maximum
        }

        func makeDoneBar() -> UIToolbar {
            let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            bar.barStyle = .black
            bar.isTranslucent = true
            bar.tintColor = UIColor(LiveDesign.accent)
            bar.items = [
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                UIBarButtonItem(
                    title: SettingsNumberField.doneTitle,
                    style: .done,
                    target: self,
                    action: #selector(done)),
            ]
            bar.sizeToFit()
            return bar
        }

        @objc func editingChanged(_ field: UITextField) {
            field.accessibilityValue = field.text
        }

        @objc func done() {
            field?.resignFirstResponder()
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            commit(textField)
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            let current = textField.text ?? ""
            guard let swiftRange = Range(range, in: current) else { return false }
            let next = current.replacingCharacters(in: swiftRange, with: string)
            if next.isEmpty { return true }
            return next.allSatisfy(\.isNumber) && next.count <= 3
        }

        private func commit(_ textField: UITextField) {
            let parsed = Int(textField.text ?? "") ?? value.wrappedValue
            let clamped = min(max(parsed, 0), maximum)
            value.wrappedValue = clamped
            textField.text = String(clamped)
            textField.accessibilityValue = String(clamped)
        }
    }
}

struct SettingsActionPill: View {
    let title: String
    var icon: OpcIcon? = nil
    var tint: Color = LiveDesign.accent
    var background: Color = LiveDesign.accentDim
    var fillsHeight = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    icon.frame(width: 13, height: 13)
                }
                Text(title.uppercased())
                    .font(MonitorTheme.font(10.5, weight: .bold)).monospacedDigit()
                    .kerning(0.6)
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxHeight: fillsHeight ? .infinity : nil)
            .background(background, in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.zcTapTarget)
    }
}

typealias SettingsSwitchGraphic = MonitorSettingsSwitchGraphic

/// OpenZCine `DisplayToggleItem` — compact switch tile for the DISP 2 assist pin grid.
struct DisplayToggleItem: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                    .font(LiveType.ui(size: 11.5, weight: .semibold, design: .default))
                    .foregroundStyle(LiveDesign.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
                Spacer(minLength: 0)
                SettingsSwitchGraphic(isOn: isOn)
                    .scaleEffect(0.86)
            }
            .padding(.horizontal, 9)
            .frame(height: 46)
            .background(
                LiveDesign.background.opacity(0.38),
                in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
                    .stroke(LiveDesign.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.zcTapTarget)
    }
}

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

struct GimbalStickSensitivitySlider: View {
    @Binding var value: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 9) {
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: {
                        let next = GimbalStick.clampedSensitivity(Int($0.rounded()))
                        guard next != value else { return }
                        OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled)
                        value = next
                    }),
                in: 1...5,
                step: 1
            )
            .tint(LiveDesign.accent)
            .accessibilityLabel("Joystick sensitivity")
            .accessibilityValue("\(value)")
            Text("\(value)")
                .font(MonitorTheme.font(12, weight: .medium)).monospacedDigit()
                .foregroundStyle(LiveDesign.text)
                .frame(width: 24, alignment: .trailing)
                .monospacedDigit()
        }
    }
}

struct VirtualJoystickDeadzoneSlider: View {
    @Binding var value: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 9) {
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: {
                        let next = GimbalStick.clampedDeadzonePercent(Int($0.rounded()))
                        guard next != value else { return }
                        OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled)
                        value = next
                    }),
                in: Double(
                    GimbalStick.deadzonePercentRange.lowerBound)...Double(
                        GimbalStick.deadzonePercentRange.upperBound),
                step: 1
            )
            .tint(LiveDesign.accent)
            .accessibilityIdentifier("gimbal.virtual.deadzone")
            .accessibilityLabel("Dead zone")
            .accessibilityValue("\(value)%")
            Text("\(value)%")
                .font(MonitorTheme.font(12, weight: .medium)).monospacedDigit()
                .foregroundStyle(LiveDesign.text)
                .frame(width: 40, alignment: .trailing)
                .monospacedDigit()
        }
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

struct SettingsDashScale: View {
    let title: String
    let caption: String
    let score: Int

    private var band: MonitorLinkHealthBand { .init(score: score) }

    private var bandColor: Color {
        MonitorTheme.linkHealthColor(band)
    }
    private var bandName: String {
        switch band {
        case .poor: "POOR"
        case .watch: "WATCH"
        case .stable: "STABLE"
        }
    }
    private var litCount: Int {
        switch band {
        case .poor: 4
        case .watch: 8
        case .stable: 12
        }
    }
    private var bandSlot: Int {
        switch band {
        case .poor: 0
        case .watch: 1
        case .stable: 2
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(LiveType.ui(size: 13, weight: .semibold))
                .foregroundStyle(LiveDesign.text)
            Text(caption)
                .font(MonitorTheme.font(11.5, weight: .medium)).monospacedDigit()
                .foregroundStyle(LiveDesign.muted)
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { slot in
                    ZStack {
                        if slot == bandSlot { marker }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 19)
            HStack(spacing: 3) {
                ForEach(0..<12, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(dashColor(index))
                        .frame(height: 6)
                }
            }
            HStack(spacing: 0) {
                legend("Poor", "<50").frame(maxWidth: .infinity, alignment: .leading)
                legend("Watch", "50-79").frame(maxWidth: .infinity, alignment: .center)
                legend("Stable", "80+").frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous))
    }

    private var marker: some View {
        Text(bandName)
            .font(MonitorTheme.font(9.5, weight: .bold)).monospacedDigit()
            .kerning(0.5)
            .foregroundStyle(bandColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(bandColor.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(bandColor, lineWidth: 1))
    }

    private func dashColor(_ index: Int) -> Color {
        guard index < litCount else { return LiveDesign.hairlineStrong }
        if index < 4 { return MonitorTheme.linkHealthColor(.poor).opacity(0.8) }
        if index < 8 { return MonitorTheme.linkHealthColor(.watch).opacity(0.85) }
        return MonitorTheme.linkHealthColor(.stable).opacity(0.9)
    }

    private func legend(_ name: String, _ sub: String) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(LiveType.ui(size: 10, weight: .semibold))
                .foregroundStyle(LiveDesign.muted)
            Text(sub)
                .font(MonitorTheme.font(9, weight: .regular)).monospacedDigit()
                .foregroundStyle(LiveDesign.faint)
        }
    }
}

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

struct SettingsLiveTile: View {
    @Environment(AppModel.self) private var model
    @State private var displayedFPS = "—"
    @State private var lastFPSCommit: CFAbsoluteTime = 0

    private var isLinked: Bool { model.isLive }

    private var tint: Color {
        guard isLinked else { return LiveDesign.faint }
        switch model.session.liveSignalBars {
        case 3...: return LiveDesign.good
        case 2: return LiveDesign.accent
        case 1: return LiveDesign.rec
        default: return model.session.hasVideoFormat ? LiveDesign.accent : LiveDesign.faint
        }
    }

    private var litBars: Int {
        guard isLinked else { return 0 }
        if model.session.liveSignalBars > 0 { return model.session.liveSignalBars }
        return model.session.hasVideoFormat ? 2 : 1
    }

    private var detail: String {
        let name =
            model.session.connectedCamera?.name
            ?? model.savedCameras.first?.displayName
            ?? "Luna"
        let transport = isLinked ? "BLE + Wi-Fi" : "—"
        return "\(name) · \(transport) · \(displayedFPS) FPS"
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .shadow(color: tint.opacity(0.7), radius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(isLinked ? "Active Link" : "No Link")
                    .font(LiveType.ui(size: 12, weight: .semibold))
                    .foregroundStyle(LiveDesign.text)
                    .lineLimit(1)
                    .fixedSize()
                Text(isLinked ? detail : model.session.phase.label)
                    .font(MonitorTheme.font(10.5, weight: .medium)).monospacedDigit()
                    .foregroundStyle(LiveDesign.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(
                            index < litBars
                                ? tint.opacity(0.52 + Double(index) * 0.12)
                                : LiveDesign.hairline
                        )
                        .frame(width: 3, height: CGFloat(6 + index * 3))
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: litBars)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LiveDesign.surface,
            in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
                .stroke(LiveDesign.hairline, lineWidth: 1)
        )
        .onAppear { commitFPS(model.session.liveFPS) }
        .onChange(of: model.session.liveFPS) { _, next in
            commitFPS(next)
        }
    }

    private func commitFPS(_ incoming: String) {
        let compact = incoming.hasSuffix(".00") ? String(incoming.dropLast(3)) : incoming
        let now = CFAbsoluteTimeGetCurrent()
        if lastFPSCommit == 0 || now - lastFPSCommit >= 0.5
            || compact != displayedFPS
                && (Double(compact) == nil || Double(displayedFPS) == nil)
        {
            displayedFPS = compact.isEmpty ? "—" : compact
            lastFPSCommit = now
            return
        }
        guard now - lastFPSCommit >= 0.5 else { return }
        displayedFPS = compact.isEmpty ? "—" : compact
        lastFPSCommit = now
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
