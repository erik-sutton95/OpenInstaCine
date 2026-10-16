import Insta360Protocol
import MonitorPresentation
import OpenCineAppKit
import OpenCineCameraControls
import OpenCineCore
import OpenInstaViewCore
import SwiftUI

typealias LiveCapturePickerHost = CaptureSheetPickerHost<AppModel>
typealias CaptureControlSheet = CaptureSheetModal<AppModel>
typealias CapturePickerPanel = CaptureSheetPanel<AppModel>
typealias LiveCaptureDrumHost = CaptureSheetDrumHost<AppModel>
typealias CaptureReadoutGesture = CaptureSheetReadoutGesture<AppModel>

extension CaptureLists {
    static let nativeIsoHopHelp =
        "On: switching color mode hops ISO to that curve's starred native if you were still on native. Off: keep the ISO you set."
}

extension CaptureQuickSnapshot {
    @MainActor static func primary(_ sheet: CaptureSheet, model: AppModel) -> Self? {
        var status = model.session.status
        if sheet == .iso, !model.session.supportsIsoLimit, status.isoIndex == .auto {
            // No auto ISO ceiling on this camera: the hold drum offers manual ISO instead.
            status.isoIndex = nil
        }
        return primary(
            sheet, status: status, cameraModel: model.session.connectedCamera?.model,
            supportsFocusMode: model.session.supportsFocusMode,
            supportsAperture: model.session.supportsAperture,
            facePriorityExposureEnabled: model.facePriorityExposureEnabled,
            shutterUsesAngle: OperatorPrefs.shutterUsesAngle,
            shutterAngleDegrees: OperatorPrefs.shutterAngleDegrees,
            aeLocked: model.session.autoExposureLock != nil,
            awbLocked: model.session.autoWhiteBalanceLock != nil,
            offersAwbLock: model.session.canLockAutoWhiteBalance,
            focusOptions: CaptureLists.focusOptions, profile: model.session.profile)
    }
}

/// The shared capture sheets on this app's session: the sheets' ISO tabs and white balance rows
/// commit through the common fields they open, readout drums and the rest as typed calls.
extension AppModel: CaptureSheetHost {
    typealias Palette = LiveDesign
    typealias NativeCapturePanel = LunaNativeCapturePanel
    func nativeCapturePanel(_ sheet: CaptureSheet, enabled: Bool) -> LunaNativeCapturePanel? {
        guard [.resolution, .color].contains(sheet), !cameraStatus.isPhoto else { return nil }
        return LunaNativeCapturePanel(model: self, sheet: sheet, enabled: enabled)
    }

    var nativeMeteringSource: CaptureNativeMeteringSource? {
        guard session.supportsFaceMetering else { return nil }
        let owner = session
        let camera = control.snapshot?.session, epoch = control.snapshot?.epoch
        let phase = owner.phase, face = owner.faceMetering
        let nativeOwner = owner.lunaSession, nativeSource = nativeOwner?.commandOwner.source
        return .init(face: face, isCurrent: { [weak self, weak owner] in
            guard let self, let owner else { return false }
            return self.session === owner && self.control.snapshot?.session == camera
                && self.control.snapshot?.epoch == epoch && owner.phase == phase
                && owner.lunaSession === nativeOwner && nativeOwner?.commandOwner.source == nativeSource
                && owner.faceMetering == face && owner.supportsFaceMetering && owner.canSendControl
        }, setFace: { [weak owner] in owner?.setFaceMetering($0) })
    }

    var cameraStatus: CameraStatus { session.status }
    var displayStatus: CameraStatus { session.status }
    /// main showed an ISO, shutter or white balance request at once.
    var captureStripShowsPendingEdits: Bool { true }
    var connectedBody: CameraModel? { session.connectedCamera?.model }
    var sessionPhaseLabel: String { session.phase.label }
    var bodyFamily: CameraBodyFamily { session.bodyFamily }
    var labelProfile: CameraLabelProfile { session.profile }
    var audioService: CaptureAudioService? { nil }
    var colorModes: [ColorMode] { session.colorModes }
    /// The one codec and colour popup. The Luna offers no codec choice, so it lists its native
    /// recording colours only, the same ones its colour drum writes.
    var recordingCodecColor: CaptureCodecColorChoices {
        let choices = LunaColorMode.nativeRecordingChoices
        return CaptureCodecColorChoices(
            colors: choices.map { CaptureCodecColorChoice(id: String($0.rawValue), label: $0.label) },
            selectedColor: session.nativeRecordingColor.map { String($0.rawValue) })
    }
    var currentShootingMode: ShootingMode? { session.currentShootingMode }
    var sessionLocked: Bool { session.isLocked }
    var formatPinActive: Bool { session.isFormatPinActive }
    var autoExposureLocked: Bool { session.autoExposureLock != nil }
    var autoWhiteBalanceLocked: Bool { session.autoWhiteBalanceLock != nil }
    var canLockAutoWhiteBalance: Bool { session.canLockAutoWhiteBalance }
    var captureRouting: CaptureSheetRouting { .init() }
    var captureCapabilities: CaptureSheetCapabilities {
        CaptureSheetCapabilities(
            focusMode: session.supportsFocusMode, aperture: session.supportsAperture,
            nativeISO: .init(hop: session.supportsNativeIsoHop, ceiling: session.supportsIsoLimit),
            audio: audioService != nil,
            faceMetering: session.supportsFaceMetering)
    }
    var focusOptions: [FocusOption] { CaptureLists.focusOptions }
    var shutterUsesAngle: Bool {
        get { OperatorPrefs.shutterUsesAngle }
        set {
            OperatorPrefs.shutterUsesAngle = newValue
            session.configureShutterPresentation(usesAngle: newValue)
        }
    }
    var shutterAngleDegrees: Double { OperatorPrefs.shutterAngleDegrees }
    var coverOpen: Bool { shell.cover != nil }
    var operatorPanelOpen: Bool { shell.cover != nil }

    /// Video format and colour are native quick choices; Photo keeps the shared fallback, as the
    /// native drawer does (`nativeCapturePanel`).
    func quickSnapshot(_ sheet: CaptureSheet) -> CaptureQuickSnapshot? {
        guard [.resolution, .color].contains(sheet), !cameraStatus.isPhoto else {
            return CaptureQuickSnapshot.primary(sheet, model: self)
        }
        let enabled = session.phase == .live && session.hasControlLink && !session.isLocked && control.isRecording == false
        let source = session.lunaSession?.commandOwner.source.uuidString ?? "none"
        if sheet == .resolution {
            guard let current = session.nativeRecordingFormat, let currentRate = Rational.frameRate(current.framesPerSecond) else { return nil }
            let values = nativeRateChoices(for: current)
            let labels = values.compactMap { Rational.frameRate($0.framesPerSecond).map { MonitorCapturePresentation.frameRate($0) + "p" } }
            return .native(sheet: .resolution, title: "Frame rate", options: labels,
                selection: MonitorCapturePresentation.frameRate(currentRate) + "p",
                context: values.map { String($0.rawValue) }.joined(separator: ":") + "@" + String(current.rawValue) + "/" + source, enabled: enabled)
        }
        let choices = LunaColorMode.nativeRecordingChoices
        let current = session.nativeRecordingColor.flatMap { choices.contains($0) ? $0 : nil }
        return .native(sheet: .color, title: "Color", options: choices.map(\.label),
            selection: current?.label ?? "",
            context: (session.nativeRecordingColor.map { String($0.rawValue) } ?? "unknown") + "/" + source, enabled: enabled)
    }

    private func nativeRateChoices(for current: LunaVideoResolution) -> [LunaVideoResolution] {
        var rates = Set<Rational>()
        return LunaShellMapping.videoFormatValues.compactMap(LunaVideoResolution.init(rawValue:)).filter {
            guard $0.width == current.width, $0.height == current.height,
                let rate = Rational.frameRate($0.framesPerSecond) else { return false }
            return rates.insert(rate).inserted
        }
    }
    func commitNativeCaptureQuick(_ sheet: CaptureSheet, selection: String) {
        if sheet == .resolution, let current = session.nativeRecordingFormat,
            let value = nativeRateChoices(for: current).first(where: {
                Rational.frameRate($0.framesPerSecond).map { MonitorCapturePresentation.frameRate($0) + "p" } == selection
            }) { session.setNativeRecordingFormat(value) }
        else if sheet == .color, let value = LunaColorMode.nativeRecordingChoices.first(where: { $0.label == selection }) {
            session.setNativeRecordingColor(value)
        }
    }

    func commit(_ setting: CaptureSetting, from origin: CaptureCommitOrigin) {
        switch setting {
        case .iso(let iso): session.setISO(iso)
        case .isoAuto: _ = commitCommon(.iso(.auto), from: origin)
        case .isoManual(let label):
            guard case .sheet(let field) = origin else { return }
            let target =
                field?.choices.first {
                    if case .iso(.manual) = $0.value { return $0.label == label }
                    return false
                }
                ?? field?.choices.first {
                    if case .iso(.manual) = $0.value { return true }
                    return false
                }
            if let target { _ = commitCommon(target.value, from: origin) }
        case .isoLimit(let limit): session.setIsoLimit(limit)
        case .ev(let ev): session.setEv(ev)
        case .shutterDenom(let denom): session.setShutterDenom(denom)
        case .shutterAngle(let degrees): session.setShutterAngle(degrees)
        case .whiteBalanceAuto:
            if case .sheet = origin {
                if commitCommon(.whiteBalance(.auto), from: origin) { session.autoWhiteBalanceLock = nil }
            } else {
                session.setWhiteBalanceAuto()
            }
        case .whiteBalanceCustom(let kelvin, let tint):
            if case .sheet = origin {
                if commitCommon(.whiteBalance(.kelvin(kelvin)), from: origin) {
                    session.autoWhiteBalanceLock = nil
                }
            } else {
                session.setWhiteBalanceCustom(kelvin: kelvin, tint: tint)
            }
        case .whiteBalanceTint(let tint, let kelvin):
            // Auto SET keeps tint. Tint pad must not kick Auto into Custom.
            if let kelvin {
                session.setWhiteBalanceCustom(kelvin: kelvin, tint: tint)
            } else {
                session.setWhiteBalanceAuto(tint: tint)
            }
        case .autoWhiteBalanceLock: session.lockAutoWhiteBalance()
        case .videoFormat(let format):
            session.setVideoFormat(resolution: format.resolution, frameRate: format.frameRate)
        case .colorMode(let mode): session.setColorMode(mode)
        case .shootingMode(let mode): session.setShootingMode(mode)
        case .aperture(let strategy): session.setApertureStrategy(strategy)
        case .expoMode(let mode): session.setExpoMode(mode)
        case .focus(let option, _): session.setFocusOption(option)
        }
    }

    /// Commits through the field the sheet opened; a stale or read-only editor commits nothing.
    private func commitCommon(_ value: SettingValue, from origin: CaptureCommitOrigin) -> Bool {
        guard case .sheet(let field?) = origin, let editor = field.editor,
            control.captureField(field.key)?.isEditable == true,
            control.captureField(field.key)?.editor == editor
        else { return false }
        return control.commit(
            value, from: editor, label: "\(field.title) \(MonitorCapturePresentation.label(value))")
    }

    func captureDrumDidCommit(_ value: SettingValue) {
        if value.key == .whiteBalance { session.autoWhiteBalanceLock = nil }
        if case .shutter(.angle(let degrees)) = value { OperatorPrefs.shutterAngleDegrees = degrees }
    }
    func refreshIsoLimit() async { await session.refreshIsoLimit() }
}
