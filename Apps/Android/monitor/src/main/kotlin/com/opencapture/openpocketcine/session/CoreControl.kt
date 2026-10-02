package com.opencapture.openpocketcine.session

import com.opencapture.opencine.core.CameraSnapshot
import com.opencapture.opencine.core.ISOValue
import com.opencapture.opencine.core.RecordingState
import com.opencapture.opencine.core.SettingKey
import com.opencapture.opencine.core.SettingValue
import com.opencapture.opencine.core.ShutterValue
import com.opencapture.opencine.core.WhiteBalanceValue
import kotlin.math.roundToInt

/**
 * Temporary projection (SHELL-03 I-1) of the shared `MonitorControlModel` onto the app's
 * [CameraStatus]: ISO, shutter, white balance and recording from the session's snapshot, with
 * the shared model's pending targets on top; the live ISO and shutter readouts (what Auto chose)
 * stay with the readout mapping. Goes once the HUD and capture views read the shared model (I-2).
 */
internal object CorePresentation {
    fun apply(snapshot: CameraSnapshot, pending: Map<SettingKey, SettingValue>, status: CameraStatus): CameraStatus {
        fun shown(key: SettingKey) = pending[key] ?: snapshot.value(key).value
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
}
