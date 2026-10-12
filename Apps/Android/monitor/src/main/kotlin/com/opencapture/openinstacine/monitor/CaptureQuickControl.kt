package com.opencapture.openinstacine.monitor

import com.opencapture.opencine.cameracontrols.MonitorOperatorCaptureSource
import com.opencapture.opencine.vocabulary.CameraStatus
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

internal fun applyCaptureFocusChoice(label: String, status: CameraStatus, model: AppModel): Unit =
    com.opencapture.opencine.cameracontrols.applyCaptureFocusChoice(label, status, model::setFocusMode,
        model::setFocusTrack, model.labelProfile.focusLabels)
