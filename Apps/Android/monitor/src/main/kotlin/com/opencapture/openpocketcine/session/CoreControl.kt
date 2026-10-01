package com.opencapture.openpocketcine.session

import com.opencapture.opencine.core.CameraCommandIntent
import com.opencapture.opencine.core.CameraSnapshot
import com.opencapture.opencine.core.CommandFailure
import com.opencapture.opencine.core.CommandRejection
import com.opencapture.opencine.core.CommandStage
import com.opencapture.opencine.core.ISOValue
import com.opencapture.opencine.core.OperationID
import com.opencapture.opencine.core.RecordingState
import com.opencapture.opencine.core.SettingKey
import com.opencapture.opencine.core.SettingValue
import com.opencapture.opencine.core.ShutterValue
import com.opencapture.opencine.core.UnavailableReason
import com.opencapture.opencine.core.WhiteBalanceValue
import kotlin.math.roundToInt

/**
 * The operator's target for one setting while its operation is unfinished: presentation state,
 * never written into the session's snapshot.
 */
internal data class PendingSetting(val operation: OperationID, val value: SettingValue)

/**
 * The shared status view of the OpenCineCore session (CORE-02). ISO, shutter, white balance and
 * recording come only from the session's snapshot, with pending targets on top; the live ISO and
 * shutter readouts (what Auto chose) stay with the readout mapping. No camera-protocol type here.
 */
internal object CorePresentation {
    fun apply(snapshot: CameraSnapshot, pending: Map<SettingKey, PendingSetting>, status: CameraStatus): CameraStatus {
        fun shown(key: SettingKey) = pending[key]?.value ?: snapshot.value(key).value
        var next = status
        var isoAuto: Boolean? = null
        var shutterAuto: Boolean? = null
        when (val iso = (shown(SettingKey.ISO) as? SettingValue.Iso)?.value) {
            is ISOValue.Manual -> {
                next = next.copy(isoIndex = CameraCommands.isoIndexFromValue(iso.iso) ?: -1, iso = iso.iso)
                isoAuto = false
            }
            ISOValue.Auto, is ISOValue.AutoLimited -> {
                next = next.copy(isoIndex = 0)
                isoAuto = true
            }
            null -> next = next.copy(isoIndex = -1)
        }
        when (val shutter = (shown(SettingKey.SHUTTER) as? SettingValue.Shutter)?.value) {
            is ShutterValue.Duration -> {
                // The live readout already shows a reported shutter; only a target replaces it.
                if (SettingKey.SHUTTER in pending) next = next.copy(shutterDenom = (1 / shutter.seconds.doubleValue).roundToInt())
                shutterAuto = false
            }
            null -> Unit
            else -> shutterAuto = true
        }
        if (isoAuto != null && shutterAuto != null) {
            next = next.copy(expoMode = if (isoAuto && shutterAuto) CameraCommands.EXPO_AUTO else CameraCommands.EXPO_MANUAL)
        }
        next = when (val balance = (shown(SettingKey.WHITE_BALANCE) as? SettingValue.WhiteBalance)?.value) {
            is WhiteBalanceValue.Kelvin -> next.copy(wbMode = CameraCommands.WB_CUSTOM, wbKelvin = balance.kelvin, wbTint = 0)
            null -> next.copy(wbMode = -1)
            // Auto keeps the last custom kelvin for the picker.
            else -> next.copy(wbMode = CameraCommands.WB_AUTO, wbTint = 0)
        }
        return next.copy(isRecording = snapshot.recording.value == RecordingState.RECORDING)
    }

    /** Start or stop from the camera's report; null while it is unknown. Never a blind toggle. */
    fun recordIntent(reported: RecordingState?): CameraCommandIntent? = when (reported) {
        RecordingState.RECORDING -> CameraCommandIntent.StopRecording
        RecordingState.IDLE -> CameraCommandIntent.StartRecording
        else -> null
    }

    /** Operator copy for an outcome that is not a confirmation. */
    fun note(stage: CommandStage, label: String): String? = when (stage) {
        CommandStage.Confirmed -> null
        is CommandStage.Rejected -> when (val rejection = stage.rejection) {
            CommandRejection.CameraRefused -> "$label: the camera refused it."
            CommandRejection.OutOfDomain, CommandRejection.Unsupported, CommandRejection.SupportUnknown ->
                "$label is not offered by this camera."
            CommandRejection.StaleCapabilities, CommandRejection.StaleEpoch ->
                "$label was not sent: the camera state changed. Try again."
            is CommandRejection.Unavailable ->
                if (rejection.reason == UnavailableReason.Mode) "$label is not available in this mode." else "$label is not available right now."
            else -> "Connect the camera to use its controls."
        }
        is CommandStage.Failed ->
            if (stage.failure == CommandFailure.NOT_APPLIED) "$label was not applied by the camera." else "$label was not sent."
        CommandStage.OutcomeUnknown -> "$label: the camera link dropped before it confirmed."
        else -> "The camera did not confirm $label."
    }
}
