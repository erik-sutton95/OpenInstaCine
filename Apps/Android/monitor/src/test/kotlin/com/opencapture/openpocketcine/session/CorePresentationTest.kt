package com.opencapture.openpocketcine.session

import com.opencapture.opencine.core.CameraCommandIntent
import com.opencapture.opencine.core.CameraSessionID
import com.opencapture.opencine.core.CameraSnapshot
import com.opencapture.opencine.core.CommandFailure
import com.opencapture.opencine.core.CommandStage
import com.opencapture.opencine.core.ISOValue
import com.opencapture.opencine.core.MonotonicInstant
import com.opencapture.opencine.core.Observation
import com.opencapture.opencine.core.ObservationOrigin
import com.opencapture.opencine.core.OperationID
import com.opencapture.opencine.core.Rational
import com.opencapture.opencine.core.RecordingState
import com.opencapture.opencine.core.SettingKey
import com.opencapture.opencine.core.SettingValue
import com.opencapture.opencine.core.ShutterValue
import com.opencapture.opencine.core.WhiteBalanceValue
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.Test

/** The shared status shows reported Core values, with a pending target only while it is unfinished. */
class CorePresentationTest {
    private fun reported(value: SettingValue) = Observation(value, ObservationOrigin.CAMERA_REPORTED, MonotonicInstant.ZERO)

    private val snapshot = CameraSnapshot(
        CameraSessionID(),
        settings = mapOf(
            SettingKey.ISO to reported(SettingValue.Iso(ISOValue.Manual(400))),
            SettingKey.SHUTTER to reported(SettingValue.Shutter(ShutterValue.Duration(Rational(1, 50)))),
            SettingKey.WHITE_BALANCE to reported(SettingValue.WhiteBalance(WhiteBalanceValue.Kelvin(5600))),
        ),
        recording = Observation(RecordingState.IDLE, ObservationOrigin.CAMERA_REPORTED, MonotonicInstant.ZERO),
    )

    @Test fun reportedValuesMapOntoTheSharedStatus() {
        val s = CorePresentation.apply(snapshot, emptyMap(), CameraStatus(shutterDenom = 50))
        assertEquals(CameraCommands.EXPO_MANUAL, s.expoMode)
        assertEquals("400", s.isoLabel)
        assertEquals("5600K", s.wbLabel)
        assertFalse(s.isRecording)
        val auto = CorePresentation.apply(
            snapshot.copy(
                settings = mapOf(
                    SettingKey.ISO to reported(SettingValue.Iso(ISOValue.Auto)),
                    SettingKey.SHUTTER to reported(SettingValue.Shutter(ShutterValue.Auto)),
                    SettingKey.WHITE_BALANCE to reported(SettingValue.WhiteBalance(WhiteBalanceValue.Auto)),
                ),
            ),
            emptyMap(), s,
        )
        assertEquals(CameraCommands.EXPO_AUTO, auto.expoMode)
        assertEquals("Auto", auto.isoLabel)
        assertEquals("Auto", auto.wbLabel)
        assertEquals(5600, auto.wbKelvin, "Auto keeps the last custom kelvin")
    }

    @Test fun pendingTargetShowsUntilItsOperationEnds() {
        val pending = mapOf(
            SettingKey.WHITE_BALANCE to PendingSetting(OperationID(), SettingValue.WhiteBalance(WhiteBalanceValue.Kelvin(3200))),
            SettingKey.SHUTTER to PendingSetting(OperationID(), SettingValue.Shutter(ShutterValue.Duration(Rational(1, 100)))),
        )
        val held = CorePresentation.apply(snapshot, pending, CameraStatus(shutterDenom = 50))
        assertEquals(3200, held.wbKelvin)
        assertEquals(100, held.shutterDenom)
        val ended = CorePresentation.apply(snapshot, emptyMap(), held.copy(shutterDenom = 50))
        assertEquals(5600, ended.wbKelvin)
        assertEquals(50, ended.shutterDenom)
    }

    @Test fun unknownRecordingIsNeitherShownNorToggled() {
        val unknown = snapshot.copy(recording = Observation.unknown)
        assertFalse(CorePresentation.apply(unknown, emptyMap(), CameraStatus(isRecording = true)).isRecording)
        assertNull(CorePresentation.recordIntent(unknown.recording.value), "no blind toggle")
        assertEquals(CameraCommandIntent.StopRecording, CorePresentation.recordIntent(RecordingState.RECORDING))
        assertEquals(CameraCommandIntent.StartRecording, CorePresentation.recordIntent(RecordingState.IDLE))
        assertTrue(
            CorePresentation.apply(
                snapshot.copy(recording = Observation(RecordingState.RECORDING, ObservationOrigin.CAMERA_REPORTED, null)),
                emptyMap(), CameraStatus(),
            ).isRecording,
        )
    }

    @Test fun onlyAConfirmationIsSilent() {
        assertNull(CorePresentation.note(CommandStage.Confirmed, "ISO 400"))
        assertEquals("ISO 400 was not applied by the camera.", CorePresentation.note(CommandStage.Failed(CommandFailure.NOT_APPLIED), "ISO 400"))
        assertEquals("The camera did not confirm WB 3200K.", CorePresentation.note(CommandStage.TimedOut, "WB 3200K"))
    }
}
