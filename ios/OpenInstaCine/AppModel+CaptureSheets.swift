import MonitorPresentation
import OpenCineAppKit
import OpenCineCameraControls
import OpenCineCore
import OpenPocketViewCore
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

    var cameraStatus: CameraStatus { session.status }
    var displayStatus: CameraStatus { session.status }
    var connectedBody: CameraModel? { session.connectedCamera?.model }
    var sessionPhaseLabel: String { session.phase.label }
    var bodyFamily: CameraBodyFamily { session.bodyFamily }
    var labelProfile: CameraLabelProfile { session.profile }
    var colorModes: [ColorMode] { session.colorModes }
    var currentShootingMode: ShootingMode? { session.currentShootingMode }
    var sessionLocked: Bool { session.isLocked }
    var formatPinActive: Bool { session.isFormatPinActive }
    var autoExposureLocked: Bool { session.autoExposureLock != nil }
    var autoWhiteBalanceLocked: Bool { session.autoWhiteBalanceLock != nil }
    var canLockAutoWhiteBalance: Bool { session.canLockAutoWhiteBalance }
    var captureCapabilities: CaptureSheetCapabilities {
        CaptureSheetCapabilities(
            focusMode: session.supportsFocusMode, aperture: session.supportsAperture,
            nativeIsoHop: session.supportsNativeIsoHop, isoLimit: session.supportsIsoLimit,
            commonExposureCompensation: false, commonFocusMode: false,
            audio: OsmoMonitorPresentation.capabilities(session).audio,
            faceMetering: session.supportsFaceMetering)
    }
    var focusOptions: [FocusOption] { CaptureLists.focusOptions }
    var shutterUsesAngle: Bool {
        get { OperatorPrefs.shutterUsesAngle }
        set { OperatorPrefs.shutterUsesAngle = newValue }
    }
    var shutterAngleDegrees: Double { OperatorPrefs.shutterAngleDegrees }
    var coverOpen: Bool { shell.cover != nil }
    var operatorPanelOpen: Bool { shell.cover != nil }

    func quickSnapshot(_ sheet: CaptureSheet) -> CaptureQuickSnapshot? {
        CaptureQuickSnapshot.primary(sheet, model: self)
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
        case .audioChannel(let channel): session.setAudioChannel(channel)
        case .windNoiseReduction(let value): session.setWindNR(value)
        case .directionalAudio(let value): session.setDirectionalAudio(value)
        case .vocalBoost(let value): session.setVocalBoost(value)
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
    }
    func refreshIsoLimit() async { await session.refreshIsoLimit() }
    func refreshAudioState() async { await session.refreshAudioState() }
}
