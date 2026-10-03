import MonitorPresentation
import MonitorUI
import OpenPocketViewCore
import SwiftUI
import UIKit

/// Operator Setup rail tabs: Luna subset of OpenZCine `OperatorSettingsTab`.
/// Operator-facing Settings help. Never name a sister app or another camera brand.
enum SettingsHelpCopy {
    static let currentTransport =
        "Luna uses Bluetooth to pair, then the camera's own 5 GHz Wi-Fi for HEVC. USB-C, hotspot, and HDMI capture are not in this build."
    static let stream =
        "The Luna sends 720p HEVC over the camera access point. Stream quality presets are not on this body."
    static let shareFeed =
        "Watching devices join this camera’s Wi-Fi, then receive the shared picture from this phone."
    static let editView =
        "Opens the monitor with an eye on each element you can show or hide."
    static let frameIO =
        "Sign in to upload clips from the share popup. Frame.io needs the internet, so the phone hops off the camera Wi‑Fi for the upload."
    static let shareThisFeed =
        "Watching devices join this camera’s Wi-Fi, then receive the shared picture from this phone."
    static let broadcastPriority =
        "Steadier picture uses more delay when the radio is busy."
    static let watcherPasscode =
        "Watchers enter this once. Leave empty for an open feed."
    static let controlRequests =
        "A watcher can ask to record, focus, and change exposure. You grant or deny on this phone."
    static let watchAFeed =
        "Watch a feed"
    static let recordConfirmation =
        "Ask before starting or stopping recording to prevent mistaps."
    static let haptics =
        "Short confirmation pulses for switches, settings, and gimbal limits. A connected controller also rumbles at a stop."
    static let headTracking =
        "Experimental. The compass above the joystick on the right is Calibrate Head Lock: that AirPods pose and that gimbal pose are shared forward. Head turns set matching pan and tilt angles within the gimbal’s range. Roll is shown only. Needs AirPods with motion (Pro, 3, Max, or later) in your ears. Off by default. The same control becomes STOP and clears the lock. On-screen stick, a game controller, and Motion Control takes priority."
    static let joystickSensitivity =
        "How far a stick throw moves the gimbal — on-screen and a connected game controller. Small throws crawl; full throw is fastest. 4 is the captured feel. 5 reaches full speed sooner; 1 is the slowest."
    static let virtualJoystickSize =
        "How large the on-screen stick is. Medium is the default. Large is easier to grab; Small keeps more of the picture clear."
    static let virtualJoystickInvertPan =
        "Reverse left and right on the on-screen stick. Off is the default. A game controller is unchanged."
    static let virtualJoystickInvertTilt =
        "Reverse up and down on the on-screen stick. Off is the default. A game controller is unchanged."
    static let virtualJoystickDeadzone =
        "Ignore small movements near the center. The default is 8%. Increase it to make the center less sensitive."
    static let virtualJoystickResponse =
        "Standard keeps the current feel. Linear responds evenly. Fine makes small movements gentler."
    static let gimbalJoystick =
        "Which analog stick pans and tilts. Left is the default. The other stick does not move the gimbal."
    static let gamepad =
        "A connected game controller. The selected gimbal joystick pans and tilts. Cross/A records. Circle/B recenters. Square/X is rotate-180. Triangle/Y tracks a face. L1/R1 jump zoom out/in. L2/R2 hold-to-zoom (deeper is faster). D-pad up/down ISO, left/right shutter. Unplug rests the stick. On-screen stick wins while you hold it."
    static let keepScreenAwake =
        "Prevents auto-lock while OpenInstaCine is open. A monitor should stay lit. iOS may still dim when the device overheats."
    static let hdrDisplay =
        "Outdoor panel brightness, not a grade. WAVE, HISTO, PARADE, VECTOR, zebras and false color still read the decoded camera signal, so judge exposure there, not from how bright the picture looks. Screen recording and AirPlay drop back to a normal SDR picture so the file is not HDR-boosted. This is not the camera's Dolby Vision color mode. Off by default."
    static let themeHelp =
        "Charcoal field-monitor chrome with yellow accents, tuned for low reflection on set."
    static let sourceHelp =
        "View the OpenInstaCine project on GitHub. Opening this may leave the camera Wi-Fi if that is the only network."
    static let linkHealth =
        "How healthy the camera link is right now — delivery, not radio RSSI."
    static let clearCache =
        "Removes downloaded clip files from this phone. The clip list stays so you can cache them again from the camera."
    static let cacheFullResolution =
        "Download the original camera file when you open a clip. Off keeps only the 720p proxy to save space. Share needs the original — connect the camera if it is not cached."
    static let shareDiagnostics =
        "Saves a report with connection events, warnings, and crashes. No name, location, or Wi-Fi password. Take a screenshot for TestFlight and paste the copied text into the feedback."
    static let reliabilityReports =
        "Optional: send crash, hang, live-feed reports and session health counts to OpenCapture through Sentry. Off by default. Turn off anytime without losing app features. Uploads wait until you leave camera Wi-Fi. No footage or GPS location. Sentry receives the connection IP; stored event IP and derived geography are removed. See Reporting Privacy below."
    static let reliabilityUnavailable =
        "This build cannot send automatic reports. You can still share or delete reports stored on this phone."
    static let deleteStoredIncidents =
        "Remove local copies of saved freeze reports. Turn off Automatic error reports to clear pending uploads. Reports already sent cannot be removed here."
}

typealias OperatorSettingsTab = MonitorSettingsTab

/// OpenZCine `OperatorSettingsPanel` chrome. Live chrome presents this; home uses `AppPanelHost`.
///
/// `safeArea` is the host-processed inset (OpenZCine `fullScreenPanelSafeArea` / standalone
/// cover): landscape zeros the clean short edge. Do not read `GeometryReader.safeAreaInsets`
/// here — this surface `ignoresSafeArea()`, so SwiftUI reports 0 and the island/trailing
/// card get only the 16pt floor.
struct SettingsRootView: View {
    /// Real device insets after the host zeros the clean landscape edge.
    var safeArea: EdgeInsets = EdgeInsets()
    var onClose: (() -> Void)? = nil

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var legalKind: LegalDocumentView.Kind?
    @State private var showLUTPicker = false
    @State private var showWatcherWiFiCode = false
    @State private var confirmClearCache = false
    @State private var cacheBytes: UInt64?
    private struct CacheSizeRequest: Equatable {
        var cameraID: String
        var revision: UInt64
    }
    private var cacheSizeRequest: CacheSizeRequest {
        CacheSizeRequest(
            cameraID: model.session.mediaCameraID, revision: model.session.mediaCacheRevision)
    }
    @State private var clearingCache = false
    @State private var cacheClearFailed = false
    @State private var diagnosticsShare: DiagnosticSharePayload?
    @State private var showProblemReport = false
    @State private var showDiagnosticOptions = false
    @State private var supportError = false
    @State private var reliabilityOptIn = ReliabilityReporting.isOptedIn
    @State private var gimbalGamepadStick = OperatorPrefs.gimbalGamepadStick

    var body: some View {
        MonitorSettingsPage(
            safeArea: safeArea, brand: "OpenInstaCine",
            selection: Bindable(model).operatorSettingsTab,
            isLive: model.isLive, phaseLabel: model.session.phase.label,
            sharingSubtitle: "Share this feed with OpenInstaCine devices on the same camera Wi-Fi.",
            feedback: { OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled) },
            onClose: dismiss, disconnect: model.disconnect
        ) { _ in
            settingsRows
        }
        .overlay {
            if let legalKind {
                LegalDocumentView(kind: legalKind, onClose: { self.legalKind = nil })
            }
        }
        .sheet(isPresented: $showWatcherWiFiCode) {
            WatcherWiFiCodeView().environment(model)
        }
        .sheet(isPresented: $showLUTPicker) {
            LUTPicker(assist: model.assist)
        }
        .sheet(isPresented: $showProblemReport) {
            ProblemReportView().environment(model)
        }
        .alert("Report unavailable", isPresented: $supportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "Email support@opencapture.org. You can save a report under Diagnostic options.")
        }
        .sheet(item: $diagnosticsShare) { payload in
            DiagnosticActivityShareView(items: [payload.url])
        }
    }

    private func dismiss() {
        if let onClose {
            onClose()
        } else {
            model.shell.dismissCover()
        }
    }

    @ViewBuilder private var settingsRows: some View {
        switch model.operatorSettingsTab {
        case .link: linkRows
        case .sharing: sharingRows
        case .assist: assistRows
        case .controls: controlsRows
        case .display: displayRows
        case .storage: storageRows
        case .system: systemRows
        }
    }

    // MARK: - Link

    @ViewBuilder private var linkRows: some View {
        SettingsLinkHealthCard().monitorFullWidthCard()

        SettingsRowCard(title: "Connection") {
            SettingsInlineRow(
                title: "Current Transport",
                help: SettingsHelpCopy.currentTransport,
                showTopDivider: false
            ) {
                SettingsValueText(value: model.isLive ? "BLE + Wi-Fi active" : "Not connected")
            }
            SettingsInlineRow(
                title: "Phase",
                help: "Where the BLE → Wi-Fi → datalink handshake is right now."
            ) {
                SettingsValueText(value: model.session.phase.label)
            }
            if let ssid = model.session.joinedSSID, !ssid.isEmpty {
                SettingsInlineRow(
                    title: "Camera Wi-Fi",
                    help:
                        "SSID joined for this session. The password stays in the iOS Keychain on this phone."
                ) {
                    SettingsValueText(value: ssid)
                }
            }
        }

        if FeedUpscaler.supportedOnThisDevice.count > 1 {
            SettingsRowCard(title: "Processing") {
                SettingsInlineRow(
                    title: "Feed Upscaler",
                    help: SettingsHelpCopy.feedUpscaler,
                    showTopDivider: false
                ) {
                    SettingsSegmented(
                        options: FeedUpscaler.supportedOnThisDevice.map(\.rawValue),
                        selected: FeedUpscaleSwitch.shared.upscaler.rawValue,
                        compact: true
                    ) { value in
                        guard let choice = FeedUpscaler(rawValue: value) else { return }
                        FeedUpscaleSwitch.shared.upscaler = choice
                    }
                }
            }
        }

        SettingsRowCard(title: "Your cameras") {
            if model.savedCameras.isEmpty {
                SettingsInlineRow(
                    title: "Saved",
                    help:
                        "Pair from the home list. Settings does not start a new pair — that stays on Your cameras.",
                    showTopDivider: false
                ) {
                    SettingsValueText(value: "None")
                }
            } else {
                ForEach(Array(model.savedCameras.enumerated()), id: \.element.id) { index, camera in
                    let network = camera.routes.first { $0.kind == .cameraAccessPoint }?.network
                    SettingsInlineRow(
                        title: camera.displayName,
                        help: camera.model + (network.map { " · \($0)" } ?? ""),
                        showTopDivider: index > 0
                    ) {
                        SettingsValueText(value: network ?? "Saved")
                    }
                }
            }
        }
    }

    // MARK: - Sharing

    @ViewBuilder private var sharingRows: some View {
        if model.session.isMultiviewBorrowed {
            SettingsRowCard {
                SettingsInlineRow(
                    title: "Sharing unavailable in Multiview",
                    help:
                        "Connect to one camera from Your cameras to share its feed with watchers.",
                    showTopDivider: false
                ) {
                    EmptyView()
                }
            }
        } else if model.isLive {
            SettingsRowCard {
                SettingsSwitchInlineRow(
                    title: "Share this feed",
                    help: SettingsHelpCopy.shareThisFeed,
                    showTopDivider: false,
                    isOn: model.shareThisFeed
                ) {
                    model.setShareThisFeed(!model.shareThisFeed)
                }
                SettingsInlineRow(
                    title: "Join camera Wi-Fi",
                    help:
                        "On the watching device, scan this code with Camera, join the Wi-Fi, then open Watch a feed."
                ) {
                    Button("Show Wi-Fi code") { showWatcherWiFiCode = true }
                        .font(LiveType.ui(size: 13, weight: .medium))
                }
                SettingsInlineRow(
                    title: "Watcher passcode",
                    help: SettingsHelpCopy.watcherPasscode
                ) {
                    SecureField("Optional", text: Bindable(model).sharePasscode)
                        .font(LiveType.ui(size: 13, weight: .medium))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .onChange(of: model.sharePasscode) { _, value in
                            WatcherRelayKeychain.hostPasscode = value
                        }
                }
                SettingsSwitchInlineRow(
                    title: "Control requests",
                    help: SettingsHelpCopy.controlRequests,
                    isOn: model.controlRequestsAllowed
                ) {
                    model.controlRequestsAllowed.toggle()
                }
                SettingsInlineRow(
                    title: "Broadcast priority",
                    help: SettingsHelpCopy.broadcastPriority,
                    stacked: true
                ) {
                    SettingsSegmented(
                        options: ["Quality", "High", "Medium", "Steady"],
                        selected: ["Quality", "High", "Medium", "Steady"][
                            min(model.broadcastPriority, 3)],
                        compact: true
                    ) { option in
                        let order = ["Quality", "High", "Medium", "Steady"]
                        if let i = order.firstIndex(of: option) {
                            model.broadcastPriority = i
                        }
                    }
                }
            }
        } else {
            SettingsRowCard {
                SettingsInlineRow(
                    title: SettingsHelpCopy.watchAFeed,
                    help: SettingsHelpCopy.shareFeed,
                    showTopDivider: false
                ) {
                    SettingsActionPill(title: "Browse") { model.openWatcherBrowse() }
                }
            }
        }
    }

    // MARK: - View Assist

    @ViewBuilder private var assistRows: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 8) {
                    assistToolCard("False Color", reset: resetFalseColor) {
                        FalseColorAssist.longPressMenu(assist: model.assist, compact: true)
                    }
                    assistToolCard("Waveform", reset: resetWaveform) {
                        WaveformAssist.longPressMenu(assist: model.assist, compact: true)
                    }
                    assistToolCard("Histogram", reset: resetHistogram) {
                        HistogramAssist.longPressMenu(assist: model.assist, compact: true)
                    }
                    assistToolCard("Peaking", reset: resetPeaking) {
                        PeakingAssist.longPressMenu(assist: model.assist, compact: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                VStack(spacing: 8) {
                    assistToolCard("Zebra", reset: resetZebra) {
                        ZebraAssist.longPressMenu(assist: model.assist, compact: true)
                    }
                    assistToolCard("Parade", reset: resetParade) {
                        ParadeAssist.longPressMenu(assist: model.assist, compact: true)
                    }
                    assistToolCard("Vectorscope", reset: resetVectorscope) {
                        VectorscopeAssist.longPressMenu(assist: model.assist, compact: true)
                    }
                    assistToolCard("Traffic Lights", reset: resetTrafficLights) {
                        TrafficLightsAssist.longPressMenu(assist: model.assist, compact: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            VStack(spacing: 8) {
                assistToolCard("False Color", reset: resetFalseColor) {
                    FalseColorAssist.longPressMenu(assist: model.assist, compact: true)
                }
                assistToolCard("Zebra", reset: resetZebra) {
                    ZebraAssist.longPressMenu(assist: model.assist, compact: true)
                }
                assistToolCard("Waveform", reset: resetWaveform) {
                    WaveformAssist.longPressMenu(assist: model.assist, compact: true)
                }
                assistToolCard("Parade", reset: resetParade) {
                    ParadeAssist.longPressMenu(assist: model.assist, compact: true)
                }
                assistToolCard("Histogram", reset: resetHistogram) {
                    HistogramAssist.longPressMenu(assist: model.assist, compact: true)
                }
                assistToolCard("Vectorscope", reset: resetVectorscope) {
                    VectorscopeAssist.longPressMenu(assist: model.assist, compact: true)
                }
                assistToolCard("Peaking", reset: resetPeaking) {
                    PeakingAssist.longPressMenu(assist: model.assist, compact: true)
                }
                assistToolCard("Traffic Lights", reset: resetTrafficLights) {
                    TrafficLightsAssist.longPressMenu(assist: model.assist, compact: true)
                }
            }
        }

        SettingsRowCard(title: "EV Meter") {
            SettingsSwitchInlineRow(
                title: "Enabled",
                help:
                    "Show the exposure meter at the picture's left edge in DISP 1. It reads the camera's metered EV, or meters the picture when the camera reports none. It never changes exposure settings.",
                showTopDivider: false, isOn: model.assist.evMeter
            ) { model.assist.toggle(.evMeter) }
        }

        SettingsRowCard(title: "LUT") {
            SettingsInlineRow(
                title: "Look",
                help: "Looks apply on this phone. The file on the camera is unchanged.",
                showTopDivider: false
            ) {
                SettingsValueText(value: lutLabel)
            }
            SettingsInlineRow(title: "Choose look") {
                SettingsActionPill(title: "Open") { showLUTPicker = true }
            }
        }
    }

    @ViewBuilder
    private func assistToolCard<Content: View>(
        _ title: String, reset: @escaping () -> Void, @ViewBuilder content: () -> Content
    ) -> some View {
        SettingsRowCard(title: title, onReset: reset) { content() }
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func resetFalseColor() {
        model.assist.falseColorScale = FalseColorAssist.Options.default.scale
        model.assist.falseColorReference = FalseColorAssist.Options.default.referenceEnabled
        model.assist.persist()
    }

    private func resetZebra() {
        model.assist.zebraOptions = .default
        model.assist.persist()
    }

    private func resetWaveform() {
        WaveformAssist.store.options = .default
    }

    private func resetParade() {
        ParadeAssist.store.options = .default
    }

    private func resetHistogram() {
        HistogramAssist.store.options = .default
    }

    private func resetVectorscope() {
        VectorscopeAssist.store.options = .default
    }

    private func resetPeaking() {
        PeakingAssist.reset(model.assist)
    }

    private func resetTrafficLights() {
        model.assist.crushClipCompensation = TrafficLightsAssist.defaultCompensation
        model.assist.persist()
    }

    private var lutLabel: String {
        model.assist.lutStatusLabel
    }

    // MARK: - Controls

    @ViewBuilder private var controlsRows: some View {
        MonitorOperatorSafetySettings(
            recordConfirmation: Bindable(model).recordConfirmationEnabled,
            haptics: Bindable(model).hapticsEnabled,
            keepScreenAwake: Bindable(model).keepScreenAwake,
            hapticsHelp: SettingsHelpCopy.haptics,
            keepScreenAwakeHelp: SettingsHelpCopy.keepScreenAwake,
            feedback: { OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled) }
        )
        let capabilities = OsmoMonitorPresentation.capabilities(model.session)
        if capabilities.gimbal {
            SettingsRowCard(title: "Gimbal") {
                SettingsInlineRow(
                    title: "Joystick sensitivity", help: SettingsHelpCopy.joystickSensitivity,
                    showTopDivider: false, stacked: true
                ) {
                    GimbalStickSensitivitySlider(value: Bindable(model).gimbalStickSensitivity)
                }
                if capabilities.headTracking {
                    SettingsSwitchInlineRow(
                        title: "Head Tracking (Experimental)", help: SettingsHelpCopy.headTracking,
                        isOn: model.headTrackingEnabled
                    ) { model.headTrackingEnabled.toggle() }
                }
            }
            SettingsRowCard(title: "On-screen joystick") {
                SettingsInlineRow(
                    title: "Size", help: SettingsHelpCopy.virtualJoystickSize,
                    showTopDivider: false, stacked: true
                ) {
                    SettingsSegmented(
                        options: MonitorJoystickSize.allCases.map(\.label),
                        selected: model.virtualJoystickSize.label,
                        compact: true
                    ) { value in
                        model.virtualJoystickSize = MonitorJoystickSize.fromLabel(value)
                    }
                    .accessibilityIdentifier("gimbal.virtual.size")
                }
                SettingsSwitchInlineRow(
                    title: "Invert pan", help: SettingsHelpCopy.virtualJoystickInvertPan,
                    isOn: model.virtualJoystickInvertPan,
                    identifier: "gimbal.virtual.invertPan"
                ) { model.virtualJoystickInvertPan.toggle() }
                SettingsSwitchInlineRow(
                    title: "Invert tilt", help: SettingsHelpCopy.virtualJoystickInvertTilt,
                    isOn: model.virtualJoystickInvertTilt,
                    identifier: "gimbal.virtual.invertTilt"
                ) { model.virtualJoystickInvertTilt.toggle() }
                SettingsInlineRow(
                    title: "Dead zone", help: SettingsHelpCopy.virtualJoystickDeadzone,
                    stacked: true
                ) {
                    VirtualJoystickDeadzoneSlider(
                        value: Bindable(model).virtualJoystickDeadzonePercent)
                }
                SettingsInlineRow(
                    title: "Response curve", help: SettingsHelpCopy.virtualJoystickResponse,
                    stacked: true
                ) {
                    SettingsSegmented(
                        options: GimbalStick.ResponseCurve.allCases.map(\.label),
                        selected: model.virtualJoystickResponseCurve.label,
                        compact: true
                    ) { value in
                        model.virtualJoystickResponseCurve =
                            GimbalStick.ResponseCurve.fromLabel(value)
                    }
                    .accessibilityIdentifier("gimbal.virtual.response")
                }
            }
        }
        SettingsRowCard(title: "Controller") {
            SettingsInlineRow(
                title: "Gimbal joystick", help: SettingsHelpCopy.gimbalJoystick,
                showTopDivider: false, stacked: true
            ) {
                SettingsSegmented(
                    options: GamepadGimbalStick.allCases.map(\.label),
                    selected: gimbalGamepadStick.label,
                    compact: true
                ) { value in
                    let next = GamepadGimbalStick.fromLabel(value)
                    if next != OperatorPrefs.gimbalGamepadStick {
                        OperatorPrefs.gimbalGamepadStick = next
                        gimbalGamepadStick = next
                        model.gimbalPadHeld = false
                        model.session.endGimbalStick()
                    }
                }
            }
            SettingsInlineRow(
                title: "Gamepad", help: SettingsHelpCopy.gamepad
            ) {
                SettingsValueText(value: model.gamepadConnected ? "Connected" : "Not connected")
            }
        }
    }

    // MARK: - Display (honest: rail-owned)

    @ViewBuilder private var displayRows: some View {
        Group {
            MonitorPanelSettings(
                hdrDisplay: Bindable(model).hdrDisplay, help: SettingsHelpCopy.hdrDisplay,
                feedback: { OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled) }
            )
            dispSectionCard(
                .live,
                reset: { model.dispLive = .liveDefaults }
            )
            dispSectionCard(
                .clean,
                reset: { model.dispClean = .cleanDefaults }
            )
        }
        .onAppear {
            model.chromeEditorReturnMode = nil
        }
    }

    @ViewBuilder
    private func dispSectionCard(
        _ section: PocketDispMode,
        reset: @escaping () -> Void
    ) -> some View {
        SettingsRowCard(title: section.settingsTitle, onReset: reset) {
            Text(section.settingsCaption)
                .font(MonitorTheme.font(10.5)).foregroundStyle(MonitorTheme.muted)
                .padding(.vertical, 5)
            dispSectionBody(section)
        }
    }

    @ViewBuilder
    private func dispSectionBody(_ section: PocketDispMode) -> some View {
        if model.isLive {
            SettingsActionPill(title: "Edit view") {
                model.beginChromeEditing(section)
            }
            .padding(.vertical, 8)
            .accessibilityHint(SettingsHelpCopy.editView)
        } else {
            Text("Connect to arrange this on the monitor.")
                .font(LiveType.ui(size: 11, weight: .semibold))
                .foregroundStyle(LiveDesign.muted)
                .padding(.vertical, 6)
        }
        dispToggles(section == .clean ? Bindable(model).dispClean : Bindable(model).dispLive)
        if section == .clean {
            cleanViewPinBlock
        }
    }

    @ViewBuilder
    private var cleanViewPinBlock: some View {
        Text("View assists that stay on in clean view")
            .font(LiveType.ui(size: 11, weight: .semibold))
            .foregroundStyle(LiveDesign.muted)
            .padding(.top, 8)
        CleanViewPinStrip()
    }

    @ViewBuilder
    private func dispToggles(_ chrome: Binding<PocketDispChrome>) -> some View {
        SettingsSwitchInlineRow(
            title: "Status Bar",
            help: "REC, timecode, format, and FPS along the top of the feed.",
            showTopDivider: true,
            isOn: chrome.wrappedValue.statusBar
        ) { chrome.wrappedValue.statusBar.toggle() }
        SettingsSwitchInlineRow(
            title: "Tool Bar",
            help: "The view-assist strip under the feed.",
            isOn: chrome.wrappedValue.toolBar
        ) { chrome.wrappedValue.toolBar.toggle() }
        SettingsSwitchInlineRow(
            title: "Camera Values",
            help: "ISO, shutter, white balance, and the rest of the capture strip.",
            isOn: chrome.wrappedValue.cameraValues
        ) { chrome.wrappedValue.cameraValues.toggle() }
        SettingsSwitchInlineRow(
            title: "Lock Button",
            help: "Side-rail lock. Remounts while the interface is locked.",
            isOn: chrome.wrappedValue.lockButton
        ) { chrome.wrappedValue.lockButton.toggle() }
        SettingsSwitchInlineRow(
            title: "Batteries",
            help: "Phone and camera battery cluster.",
            isOn: chrome.wrappedValue.batteries
        ) { chrome.wrappedValue.batteries.toggle() }
        SettingsSwitchInlineRow(
            title: "REC",
            help: "Standby / recording chip on the status bar.",
            isOn: chrome.wrappedValue.recReadout
        ) { chrome.wrappedValue.recReadout.toggle() }
        if OsmoMonitorPresentation.capabilities(model.session).timecode {
            SettingsSwitchInlineRow(
                title: "Timecode",
                help: "Running timecode on the status bar.",
                isOn: chrome.wrappedValue.timecode
            ) { chrome.wrappedValue.timecode.toggle() }
        }
        SettingsSwitchInlineRow(
            title: "Format",
            help: "Recording resolution and frame rate.",
            isOn: chrome.wrappedValue.format
        ) { chrome.wrappedValue.format.toggle() }
        SettingsSwitchInlineRow(
            title: "Color",
            help: "Color mode chip on the status bar.",
            isOn: chrome.wrappedValue.color
        ) { chrome.wrappedValue.color.toggle() }
        SettingsSwitchInlineRow(
            title: "Storage",
            help: "Remaining media time on the status bar.",
            isOn: chrome.wrappedValue.storage
        ) { chrome.wrappedValue.storage.toggle() }
        SettingsSwitchInlineRow(
            title: "FPS",
            help: "Live-view rate and link bars.",
            isOn: chrome.wrappedValue.fps
        ) { chrome.wrappedValue.fps.toggle() }
        SettingsSwitchInlineRow(
            title: "Record",
            help: "Rail record lamp. Stays available while rolling.",
            isOn: chrome.wrappedValue.railRecord
        ) { chrome.wrappedValue.railRecord.toggle() }
        SettingsSwitchInlineRow(
            title: "Media",
            help: "Rail media button.",
            isOn: chrome.wrappedValue.railMedia
        ) { chrome.wrappedValue.railMedia.toggle() }
        SettingsSwitchInlineRow(
            title: "Settings",
            help: "Rail settings button. Always an escape hatch.",
            isOn: chrome.wrappedValue.railSettings
        ) { chrome.wrappedValue.railSettings.toggle() }
        let capabilities = OsmoMonitorPresentation.capabilities(model.session)
        if capabilities.zoom {
            SettingsSwitchInlineRow(
                title: "Zoom Chip",
                help: "Live zoom readout on the feed.",
                isOn: chrome.wrappedValue.zoomChip
            ) { chrome.wrappedValue.zoomChip.toggle() }
        }
        if capabilities.gimbal {
            SettingsSwitchInlineRow(
                title: "Gimbal Stick",
                help: "On-screen gimbal stick.",
                isOn: chrome.wrappedValue.gimbalStick
            ) { chrome.wrappedValue.gimbalStick.toggle() }
        }
        SettingsSwitchInlineRow(
            title: "AF Box",
            help: "Focus and face-tracking brackets on the feed.",
            isOn: chrome.wrappedValue.focusBox
        ) { chrome.wrappedValue.focusBox.toggle() }
    }

    // MARK: - Storage

    @ViewBuilder private var storageRows: some View {
        SettingsRowCard {
            SettingsInlineRow(
                title: "Frame.io",
                help: SettingsHelpCopy.frameIO,
                showTopDivider: false
            ) {
                frameioStatusControl
            }
        }
        MonitorCacheSettings(
            cacheOriginals: Binding(get: { model.cacheFullResolution }, set: { model.cacheFullResolution = $0 }),
            sizeLabel: cacheSizeLabel, clearing: clearingCache,
            cacheHelp: SettingsHelpCopy.cacheFullResolution,
            scopeHelp: "Originals and playback proxies downloaded from the camera.",
            clearHelp: SettingsHelpCopy.clearCache,
            feedback: { OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled) },
            clear: { confirmClearCache = true })
        .confirmationDialog(
            "Clear cache?",
            isPresented: $confirmClearCache,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                clearingCache = true
                Task {
                    do { try await model.session.clearMediaCache() } catch {
                        cacheClearFailed = true
                    }
                    clearingCache = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes downloaded clip files from this phone. The clip list is kept.")
        }
        .disabled(clearingCache)
        .task(id: cacheSizeRequest) {
            let request = cacheSizeRequest
            cacheBytes = nil
            let bytes = await model.session.cameraMedia.cacheByteCount(cameraID: request.cameraID)
            guard !Task.isCancelled, cacheSizeRequest == request else { return }
            cacheBytes = bytes
        }
        .alert("Could not clear the cache. Try again.", isPresented: $cacheClearFailed) {
            Button("OK", role: .cancel) {}
        }
    }

    @ViewBuilder private var frameioStatusControl: some View {
        if !model.isFrameioConfigured {
            SettingsValueText(value: "Not configured")
        } else if model.frameioConnecting {
            ProgressView().controlSize(.small).tint(LiveDesign.accent)
        } else if model.isFrameioConnected {
            Button {
                model.disconnectFrameio()
            } label: {
                Text("Log out")
                    .font(LiveType.ui(size: 13, weight: .semibold))
                    .foregroundStyle(LiveDesign.accent)
            }
            .buttonStyle(.zcTapTarget)
        } else {
            Button {
                Task {
                    try? await model.connectFrameio()
                }
            } label: {
                Text("Sign in")
                    .font(LiveType.ui(size: 13, weight: .semibold))
                    .foregroundStyle(LiveDesign.accent)
            }
            .buttonStyle(.zcTapTarget)
        }
    }

    private var cacheSizeLabel: String {
        guard let bytes = cacheBytes else { return "Checking…" }
        if bytes == 0 { return "Empty" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - System

    @ViewBuilder private var systemRows: some View {
        MonitorSupportSettings(
            automaticReports: Binding(get: { reliabilityOptIn }, set: {
                reliabilityOptIn = $0; ReliabilityReporting.setConsent($0)
            }), available: ReliabilityReporting.isAvailable,
            automaticHelp: SettingsHelpCopy.reliabilityReports,
            unavailableHelp: SettingsHelpCopy.reliabilityUnavailable,
            report: { showProblemReport = true }, privacy: { legalKind = .privacy })
        MonitorDiagnosticSettings(expanded: $showDiagnosticOptions,
            deleteHelp: SettingsHelpCopy.deleteStoredIncidents,
            save: {
                if let url = DiagnosticCenter.shared.writeReport(session: model.session) {
                    diagnosticsShare = DiagnosticSharePayload(url: url)
                } else { supportError = true }
            }, delete: { FeedIncidentRuntime.deleteStoredIncidents {} })

        MonitorProjectLegalSettings(
            sourceHelp: SettingsHelpCopy.sourceHelp, termsHelp: "How you can use OpenInstaCine.",
            source: { if let url = OpenInstaCineLinks.source { openURL(url) } },
            privacy: { legalKind = .privacy },
            terms: { if let url = OpenInstaCineLinks.terms { openURL(url) } },
            licenses: { legalKind = .licenses }, notice: { legalKind = .notice })
        MonitorAppInformationSettings(
            theme: "Charcoal", protocolName: "Insta360 / BLE + Wi-Fi", version: Self.appVersionText,
            themeHelp: SettingsHelpCopy.themeHelp,
            protocolHelp: "Camera control speaks Insta360's protocol over Bluetooth and the camera's Wi-Fi. No Insta360 SDK is bundled or required.",
            versionHelp: "Current OpenInstaCine build from the native project metadata.")
    }

    static var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// One switch per cinema view-assist tool — the DISP 2 keep list.
struct CleanViewPinStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 7)], spacing: 7) {
            // A camera without live audio levels offers no AUDIO pin.
            ForEach(LiveAssistTool.cleanPinCases.filter { $0 != .audioMeters || OsmoMonitorPresentation.capabilities(model.session).audio }) { tool in
                DisplayToggleItem(
                    title: tool.displaySettingsTitle,
                    isOn: model.assist.cleanViewPinnedTools.contains(tool)
                ) {
                    OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled)
                    model.assist.toggleCleanViewPin(tool)
                }
                .accessibilityLabel("Keep \(tool.displaySettingsTitle) in clean view")
                .accessibilityValue(
                    model.assist.cleanViewPinnedTools.contains(tool) ? "On" : "Off")
            }
        }
    }
}
