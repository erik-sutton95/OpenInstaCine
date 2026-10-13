package com.opencapture.openinstacine.monitor

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import com.opencapture.opencine.appkit.MonitorCaptureDrum
import com.opencapture.opencine.appkit.MonitorCaptureField
import com.opencapture.opencine.appkit.MonitorCapturePresentation
import com.opencapture.opencine.appkit.captureField
import com.opencapture.opencine.cameracontrols.CaptureDrumWheel
import com.opencapture.opencine.cameracontrols.CaptureLists
import com.opencapture.opencine.cameracontrols.CaptureRefresh
import com.opencapture.opencine.cameracontrols.CaptureWheelState
import com.opencapture.opencine.cameracontrols.LiveSheet
import com.opencapture.opencine.cameracontrols.applyCaptureShootingMode
import com.opencapture.opencine.core.ISOValue
import com.opencapture.opencine.core.SettingKey
import com.opencapture.opencine.core.SettingValue
import com.opencapture.opencine.core.ShutterValue
import com.opencapture.opencine.core.WhiteBalanceValue
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.CaptureSessionState
import com.opencapture.opencine.vocabulary.CaptureSetting

/** ISO, shutter and white balance open through Core; EV and focus stay typed. */
internal fun captureSettingKey(sheet: LiveSheet): SettingKey? = when (sheet) {
    LiveSheet.ISO -> SettingKey.ISO
    LiveSheet.SHUTTER -> SettingKey.SHUTTER
    LiveSheet.WB -> SettingKey.WHITE_BALANCE
    else -> null
}

/**
 * The capture session state from the session's locks and format pin, the body's focus mode support
 * and the session's native ISO hop capability. The aperture rows draw whenever the APERTURE sheet is
 * open (the live view closes that sheet for a body without aperture). Read when the sheet reads them.
 */
internal fun instaCaptureSessionState(
    aeLock: () -> Any?,
    awbLockKelvin: () -> Int?,
    awbLockOffered: () -> Boolean,
    formatPinned: () -> Boolean,
    focusModeSupported: () -> Boolean,
    nativeIsoHopSupported: () -> Boolean,
    irisSupported: () -> Boolean = { false },
    isoCeilingSupported: () -> Boolean? = { null },
): CaptureSessionState = object : CaptureSessionState {
    override val aeLocked get() = aeLock() != null
    override val awbLockKelvin get() = awbLockKelvin()
    override val awbLockOffered get() = awbLockOffered()
    override val formatPinned get() = formatPinned()
    override val focusModeSupported get() = focusModeSupported()
    override val irisSupported get() = irisSupported()
    override val nativeIsoHopSupported get() = nativeIsoHopSupported()
    override val nativeISO get() = com.opencapture.opencine.vocabulary.CaptureNativeISOCapabilities(
        hop = nativeIsoHopSupported(), ceiling = isoCeilingSupported())
}

@Composable
internal fun AppModel.observedCaptureSessionState(status: CameraStatus): CaptureSessionState {
    val aeLock by session.aeLock.collectAsState()
    val awbLock by session.awbLockKelvin.collectAsState()
    return instaCaptureSessionState({ aeLock }, { awbLock }, { session.autoWhiteBalanceLock(status) != null },
        { session.isFormatPinActive }, { CaptureLists.supportsFocusModeOrDefault(session.connectedCamera?.model) },
        { session.supportsNativeIsoHop }, { camera?.captureProfile?.supportsAperture == true },
        isoCeilingSupported = { false })
}

/** The Core drum for ISO, shutter and white balance Kelvin; EV is its own wheel on the typed path. */
@Composable
internal fun AppModel.InstaCommonDrum(sheet: LiveSheet, status: CameraStatus, field: MonitorCaptureField?,
    enabled: Boolean, wheel: CaptureWheelState) {
    if (CaptureLists.isEvSheet(sheet, status.expoMode)) {
        CaptureDrumWheel(
            options = CaptureLists.evLabels,
            selection = wheel.selection,
            interactive = enabled && !facePriorityExposureEnabled,
            onSelect = wheel.onSelect,
        )
    } else if (field != null) {
        val manual = field.choices.filter { choice ->
            when (val value = choice.value) {
                is SettingValue.Iso -> value.value is ISOValue.Manual
                is SettingValue.Shutter -> value.value != ShutterValue.Auto
                is SettingValue.WhiteBalance -> value.value is WhiteBalanceValue.Kelvin
                else -> false
            }
        }
        MonitorCaptureDrum(session.control, field, enabled = enabled, choices = manual)
    }
}

/** Commits [value] with the editor the sheet captured when it opened; refused once that editor is stale. */
private fun AppModel.commitCommon(value: SettingValue, field: MonitorCaptureField?): Boolean {
    val captured = field ?: return false
    val editor = captured.editor ?: return false
    val current = session.control.captureField(captured.key) ?: return false
    if (!current.isEditable || current.editor != editor) return false
    return session.control.commit(value, editor, "${captured.title} ${MonitorCapturePresentation.label(value)}")
}

/** The sheet's commits: ISO, shutter and white balance through Core, the rest on the typed session path. */
internal fun AppModel.routeCaptureSetting(setting: CaptureSetting, field: MonitorCaptureField?, status: CameraStatus) {
    when (setting) {
        is CaptureSetting.IsoIndex -> if (setting.index == 0) {
            commitCommon(SettingValue.Iso(ISOValue.Auto), field)
        } else {
            field?.choices?.firstOrNull {
                it.value is SettingValue.Iso && it.label == CameraCommands.isoLabel(setting.index)
            }?.let { commitCommon(it.value, field) }
        }
        is CaptureSetting.IsoLimitRaw -> setIsoLimit(setting.raw)
        is CaptureSetting.Ev -> setEv(setting.thirds)
        is CaptureSetting.ShutterDenom ->
            field?.choices?.firstOrNull { it.label == "1/${setting.denom}" }?.let { commitCommon(it.value, field) }
        is CaptureSetting.ShutterAngle -> session.setShutterAngle(setting.degrees)
        is CaptureSetting.WhiteBalance -> commitCommon(SettingValue.WhiteBalance(WhiteBalanceValue.Kelvin(setting.kelvin)), field)
        CaptureSetting.WhiteBalanceAuto -> commitCommon(SettingValue.WhiteBalance(WhiteBalanceValue.Auto), field)
        is CaptureSetting.WhiteBalanceTint ->
            setting.kelvin?.let { setWhiteBalance(it, setting.tint) } ?: setWhiteBalanceAuto(setting.tint)
        CaptureSetting.AutoWhiteBalanceLock -> session.lockAutoWhiteBalance()
        is CaptureSetting.Format -> setVideoFormat(setting.format)
        is CaptureSetting.ColorMode -> setColorMode(setting.code)
        is CaptureSetting.ShootingMode -> applyCaptureShootingMode(setting.label, session.status.value,
            session.connectedCamera?.model?.name, labelProfile, ::setShootingMode)
        is CaptureSetting.Aperture -> setApertureStrategy(setting.raw)
        is CaptureSetting.ExpoMode -> setExpoMode(setting.mode)
        is CaptureSetting.Focus -> applyCaptureFocusChoice(setting.label, status, this)
    }
}

internal suspend fun AppModel.refreshForCaptureSheet(what: CaptureRefresh) {
    when (what) {
        CaptureRefresh.AUDIO -> audioService?.refresh?.invoke()
        CaptureRefresh.FOCUS_TRACK -> refreshFocusTrack()
        CaptureRefresh.ISO_LIMIT -> refreshIsoLimitNow()
    }
}
