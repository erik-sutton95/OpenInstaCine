package com.opencapture.openinstacine.monitor

import android.content.Context
import androidx.compose.runtime.Composable
import com.opencapture.monitorui.MonitorQuickControl
import com.opencapture.opencine.appkit.MonitorCaptureField
import com.opencapture.opencine.cameracontrols.CaptureQuickLifetime
import com.opencapture.opencine.cameracontrols.LiveSheet
import com.opencapture.opencine.cameracontrols.MonitorOperatorCaptureSource
import com.opencapture.opencine.cameracontrols.rememberMonitorCaptureLifetime
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.core.SettingKey
import com.opencapture.opencine.insta360.shell.ConnectionPhase

/** Native reports and typed setter routes over the common capture owner. */
internal fun AppModel.makeOperatorCaptureSource(): MonitorOperatorCaptureSource = MonitorOperatorCaptureSource(
    host = this, control = session.control, phaseEvents = session.phaseFlow,
    readStatus = { session.status.value }, readSessionState = {
        instaCaptureSessionState({ session.aeLock.value }, { session.awbLockKelvin.value },
        { session.autoWhiteBalanceLock(session.status.value) != null }, { session.isFormatPinActive },
        { com.opencapture.opencine.cameracontrols.CaptureLists.supportsFocusModeOrDefault(camera) },
        { session.supportsNativeIsoHop }, { camera?.captureProfile?.supportsAperture == true })
    }, ready = { session.phase == ConnectionPhase.LIVE }, busy = { session.controlBusy.value },
    nativeExposureCompensation = true,
    confirmRecording = { recordConfirmationEnabled }, takePhoto = ::pressShutter,
)

internal fun captureQuickControl(sheet: LiveSheet, status: CameraStatus, model: AppModel,
    context: Context, lifetime: CaptureQuickLifetime? = null): MonitorQuickControl? =
    model.operatorCaptureSource.quick(sheet, status, lifetime)

internal fun commonCaptureField(sheet: LiveSheet, status: CameraStatus, model: AppModel): MonitorCaptureField? =
    model.operatorCaptureSource.commonField(sheet, status)

internal fun captureReadoutLabel(sheet: LiveSheet, status: CameraStatus, model: AppModel?, nativeLabel: String): String =
    model?.operatorCaptureSource?.readout(sheet, status, nativeLabel) ?: nativeLabel

internal fun applyCaptureQuickControl(sheet: LiveSheet, value: String, status: CameraStatus,
    model: AppModel, context: Context): Unit = model.operatorCaptureSource.apply(sheet, value, status)

internal fun applyCaptureFocusChoice(label: String, status: CameraStatus, model: AppModel): Unit =
    com.opencapture.opencine.cameracontrols.applyCaptureFocusChoice(label, status, model::setFocusMode,
        model::setFocusTrack, model.labelProfile.focusLabels)

@Composable
internal fun rememberCaptureQuickLifetime(model: AppModel): CaptureQuickLifetime =
    rememberMonitorCaptureLifetime(model.operatorCaptureSource)

internal fun releaseCaptureQuickControl(sheet: LiveSheet, expected: MonitorQuickControl, value: String,
    model: AppModel, context: Context, lifetime: CaptureQuickLifetime, enabled: Boolean): Unit =
    model.operatorCaptureSource.release(sheet, expected, value, lifetime, enabled)
