import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineAppKitApple
import OpenCineApple
import OpenCineFrameIOApple
import OpenCineCameraControls
import OpenCineRelayApple
import OpenInstaViewCore
import SwiftUI
import UIKit

/// Operator Setup rail tabs: Luna subset of OpenZCine `OperatorSettingsTab`.
/// Operator-facing Settings help. Never name a sister app or another camera brand.
enum SettingsHelpCopy {
    static let currentTransport =
        "Luna uses Bluetooth to pair, then the camera's own 5 GHz Wi-Fi for HEVC. USB-C, hotspot, and HDMI capture are not in this build."
    static let themeHelp =
        "Charcoal field-monitor chrome with yellow accents, tuned for low reflection on set."
}

/// OpenZCine `OperatorSettingsPanel` chrome. Live chrome presents this; home uses `AppPanelHost`.
///
/// `safeArea` is the host-processed inset (OpenZCine `fullScreenPanelSafeArea` / standalone
/// cover): landscape zeros the clean short edge. Do not read `GeometryReader.safeAreaInsets`
/// here: this surface `ignoresSafeArea()`, so SwiftUI reports 0 and the island/trailing
/// card get only the 16pt floor.
struct SettingsRootView: View {
    var safeArea: EdgeInsets = EdgeInsets()
    var onClose: (() -> Void)? = nil
    @Environment(AppModel.self) private var model

    var body: some View {
        MonitorOperatorSettingsScreen(shell: model.shell, brand: "OpenInstaCine",
            preferences: OperatorPrefs.common, display: OperatorPrefs.display, assist: model.assist,
            library: model.session.mediaLibrary, operatorSession: model.operatorSession,
            configuration: configuration)
    }

    private var configuration: MonitorOperatorSettingsConfiguration<MonitorLUTLooks> {
        let transfer = model.monitorTransfer ?? model.monitorColorMode.map(MonitorTransfer.init) ?? .rec709
        return .init(safeArea: safeArea, phase: model.session.phase.label, isLive: model.isLive,
            sharingSubtitle: MonitorSettingsCopy.sharingSubtitle(app: "OpenInstaCine"),
            close: {
                model.settingsAccount.retire()
                model.settingsSupport.retire()
                if let onClose { onClose() } else { model.shell.dismissCover() }
            },
            disconnect: {
                model.settingsAccount.retire()
                model.settingsSupport.retire()
                model.disconnect()
            }, feedback: feedback, link: link, sharing: sharing,
            assist: .init(state: model.assist, stores: .app, falseColorLooks: .app, palette: LiveDesign.self,
                haptics: .app, transfer: transfer, clipByte: model.monitorSamples.exposureCeiling.clipByte(transfer: transfer),
                exposureHelp: "Show the exposure meter at the picture's left edge in DISP 1. It reads the camera's metered EV, or meters the picture when the camera reports none. It never changes exposure settings.",
                lookLabel: model.assist.lutStatusLabel, lookCatalog: { AnyView(LUTPicker(assist: model.assist)) }),
            controls: .init(recordConfirmation: Bindable(model).recordConfirmationEnabled,
                haptics: .init(value: Bindable(model).hapticsEnabled, help: MonitorSettingsCopy.gimbalHaptics),
                keepAwake: .init(value: Bindable(model).keepScreenAwake, help: MonitorSettingsCopy.keepScreenAwake),
                motion: motion),
            display: .init(hdr: .init(value: Bindable(model).hdrDisplay, help: MonitorSettingsCopy.hdrPanel(cameraMode: "Dolby Vision color mode")),
                sections: availableDisplay),
            cache: .init(source: cache,
                cacheOriginals: .init(value: Bindable(model).cacheFullResolution, help: MonitorSettingsCopy.cacheFullResolution),
                clearHelp: MonitorSettingsCopy.clearAllCamerasCache),
            account: .init(title: "Frame.io", help: MonitorSettingsCopy.accountHelp(service: "Frame.io"), model: model.settingsAccount,
                actions: model.settingsAccountActions, readState: { accountState },
                consentTitle: MonitorSettingsCopy.accountConsentTitle,
                consentMessage: MonitorSettingsCopy.accountConsentMessage(service: "Frame.io"),
                consentAction: MonitorSettingsCopy.accountConsentAction),
            support: support,
            information: .init(theme: "Charcoal", protocolName: "Insta360 / BLE + Wi-Fi", version: Self.appVersionText,
                themeHelp: SettingsHelpCopy.themeHelp, protocolHelp: "Camera control speaks Insta360's protocol over Bluetooth and the camera's Wi-Fi. No Insta360 SDK is bundled or required.",
                versionHelp: MonitorSettingsCopy.versionHelp(app: "OpenInstaCine")))
    }

    private func feedback() { OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled) }

    private var link: MonitorSettingsLinkSource {
        .init(transport: model.isLive ? "BLE + Wi-Fi active" : "Not connected",
            transportHelp: SettingsHelpCopy.currentTransport, phase: model.session.phase.label,
            phaseHelp: "Where the BLE → Wi-Fi → datalink handshake is right now.", network: model.session.joinedSSID.flatMap { $0.isEmpty ? nil : $0 },
            networkHelp: "SSID joined for this session. The password stays in the iOS Keychain on this phone.",
            signalBars: model.session.liveSignalBars, saved: model.savedCameras.map { camera in
                let network = camera.routes.first { $0.kind == .cameraAccessPoint }?.network
                return .init(id: camera.id, name: camera.displayName,
                    detail: camera.model + (network.map { " · \($0)" } ?? ""), network: network)
            }, savedHelp: "Pair from the home list. Settings does not start a new pair; that stays on Your cameras.",
            processing: .init(upscaler: Binding(get: { FeedUpscaleSwitch.shared.upscaler },
                set: { FeedUpscaleSwitch.shared.upscaler = $0 })))
    }

    private var sharing: MonitorSettingsSharingSource {
        .init(sharing: Binding(get: { model.shareThisFeed }, set: model.setShareThisFeed),
            passcode: Bindable(model).sharePasscode, controlRequests: Bindable(model).controlRequestsAllowed,
            priority: Bindable(model).broadcastPriority,
            help: .init(sharing: MonitorSettingsCopy.shareThisFeed, passcode: MonitorSettingsCopy.watcherPasscode,
                controlRequests: MonitorSettingsCopy.controlRequests, priority: MonitorSettingsCopy.broadcastPriority),
            browseHelp: MonitorSettingsCopy.shareThisFeed, browse: model.openWatcherBrowse,
            passcodeChanged: { WatcherRelayKeychain.app.hostPasscode = $0 },
            joinCode: { AnyView(WatcherWiFiCodeSheet().environment(model)) })
    }

    private var motion: MonitorSettingsMotionSource {
        let capabilities = OsmoMonitorPresentation.capabilities(model.session)
        return .init(sensitivity: capabilities.gimbal ? .init(value: Bindable(model).gimbalStickSensitivity,
                range: 1...5, help: MonitorSettingsCopy.joystickSensitivity, feedback: feedback) : nil,
            headTracking: capabilities.headTracking ? .init(value: Bindable(model).headTrackingEnabled,
                help: MonitorSettingsCopy.headTracking, feedback: feedback) : nil,
            joystick: capabilities.gimbal ? .init(
                size: .init(options: MonitorJoystickSize.allCases.map(\.label),
                    selection: Binding(get: { model.virtualJoystickSize.label }, set: { model.virtualJoystickSize = MonitorJoystickSize.fromLabel($0) }),
                    help: MonitorSettingsCopy.virtualJoystickSize, feedback: feedback),
                invertPan: .init(value: Bindable(model).virtualJoystickInvertPan,
                    help: MonitorSettingsCopy.virtualJoystickInvertPan, feedback: feedback),
                invertTilt: .init(value: Bindable(model).virtualJoystickInvertTilt,
                    help: MonitorSettingsCopy.virtualJoystickInvertTilt, feedback: feedback),
                deadZone: .init(value: Bindable(model).virtualJoystickDeadzonePercent,
                    range: GimbalStick.deadzonePercentRange, help: MonitorSettingsCopy.virtualJoystickDeadzone, suffix: "%", feedback: feedback),
                response: .init(options: GimbalStick.ResponseCurve.allCases.map(\.label),
                    selection: Binding(get: { model.virtualJoystickResponseCurve.label }, set: { model.virtualJoystickResponseCurve = GimbalStick.ResponseCurve.fromLabel($0) }),
                    help: MonitorSettingsCopy.virtualJoystickResponse, feedback: feedback), identifier: "gimbal.virtual") : nil,
            controller: .init(options: GamepadGimbalStick.allCases.map(\.label),
                selection: Binding(get: { OperatorPrefs.gimbalGamepadStick.label }, set: {
                    let next = GamepadGimbalStick.fromLabel($0)
                    guard next != OperatorPrefs.gimbalGamepadStick else { return }
                    OperatorPrefs.gimbalGamepadStick = next
                    model.gimbalPadHeld = false
                    model.session.endGimbalStick()
                }), help: MonitorSettingsCopy.gimbalJoystick, feedback: feedback),
            controllerStatus: model.gamepadConnected ? "Connected" : "Not connected", controllerHelp: MonitorSettingsCopy.gamepad)
    }

    private var availableDisplay: Set<MonitorDisplayChrome.Section> {
        let capabilities = OsmoMonitorPresentation.capabilities(model.session)
        return Set(MonitorDisplayChrome.Section.allCases.filter {
            if $0 == .zoomChip { return capabilities.zoom }
            if $0 == .gimbalStick { return capabilities.gimbal }
            if $0 == .timecode { return capabilities.timecode }
            return true
        })
    }
    private var accountState: MonitorAccountState {
        if !model.frameio.isConfigured { return .notConfigured }
        if model.frameio.connecting || model.settingsAccount.busy { return .connecting }
        return model.frameio.isConnected ? .signedIn : .signedOut
    }
    private var cache: MonitorSettingsCacheSource { model.settingsCacheSource }
    private var support: MonitorSettingsSupportSource {
        .init(consent: Binding(get: { AppDiagnostics.reporting.isOptedIn }, set: AppDiagnostics.reporting.setConsent),
            available: AppDiagnostics.reporting.isAvailable, automaticHelp: MonitorSettingsCopy.automaticReports,
            unavailableHelp: MonitorSettingsCopy.automaticReportsUnavailable,
            sourceHelp: MonitorSettingsCopy.sourceHelp(app: "OpenInstaCine"), termsHelp: MonitorSettingsCopy.termsHelp(app: "OpenInstaCine"),
            model: model.settingsSupport, actions: model.settingsSupportActions, links: [], privacy: nil,
            source: browserDestination("settings.source", "Source Code", OpenInstaCineLinks.source),
            terms: browserDestination("settings.terms", "Terms of Use", OpenInstaCineLinks.terms),
            reportTitle: "Report a problem", reportActionTitle: "Open", diagnosticsHelp: MonitorSettingsCopy.shareDiagnostics,
            report: { model.isProblemReportPresented = true },
            shareReport: { AnyView(MonitorActivityShareSheet(items: [$0])) },
            deleteStoredReports: { AppDiagnostics.incidents.deleteStoredIncidents {} },
            deleteReportsHelp: MonitorSettingsCopy.deleteSavedFeedReports,
            supportEmail: "support@opencapture.org", legal: .settings)
    }
    private func browserDestination(_ id: String, _ title: String, _ url: URL?) -> MonitorSettingsBrowserDestination? {
        url.map {
            .init(id: id, title: title, url: $0,
                confirmationMessage: MonitorSettingsCopy.browserConfirmation(title: title, app: "OpenInstaCine"))
        }
    }
    static var appVersionText: String { MonitorSettingsAppInformation.version() }
}


extension AppModel {
    var settingsCacheSource: MonitorSettingsCacheSource {
        let model = self
        let session = model.session
        let revision = session.mediaCacheRevision
        let source = model.shell.monitor?.id
        // Delivery exports count and clear with the media cache (A2-58). The scope is every
        // camera's cache on this phone (A2-33), so the identity is the shared cache parent.
        return model.delivery.cacheSource(.init(
            identity: .init(namespace: session.cameraMedia.mediaCacheParentPath, source: source), revision: revision,
            isCurrent: { model.session === session && model.shell.monitor?.id == source },
            count: { await session.cameraMedia.cacheByteCountAllCameras() },
            clear: { try await session.clearAllCamerasCache() }))
    }
}
