package com.opencapture.openinstacine.monitor

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.opencine.core.testing.FakeCameraSession
import com.opencapture.opencine.core.testing.FakeDevice
import com.opencapture.opencine.core.testing.lunaLike
import com.opencapture.opencine.insta360.shell.CameraReadout
import com.opencapture.opencine.insta360.shell.CameraRecordFormat
import com.opencapture.opencine.insta360.shell.CameraShootingMode
import com.opencapture.opencine.vocabulary.VideoFormat
import com.opencapture.opencine.vocabulary.VideoFrameRate
import com.opencapture.openinstacine.monitor.session.PocketCameraSession
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * A5-07: the host-emulated shutter angle follows a format change only for an established manual
 * video exposure (Core `ShutterAngle`); an unknown exposure never gets a hidden shutter SET.
 */
@RunWith(AndroidJUnit4::class)
class ShutterAngleRematchSessionTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val backend = FakeShellBackend()
    private lateinit var session: PocketCameraSession
    private var usesAngle = false
    private var degrees = 180.0

    @Before fun open() {
        usesAngle = OperatorPrefs.shutterUsesAngle(context)
        degrees = OperatorPrefs.shutterAngleDegrees(context)
        OperatorPrefs.setShutterUsesAngle(context, true)
        OperatorPrefs.setShutterAngleDegrees(context, 180.0)
        session = liveSession(backend)
    }

    @After fun close() {
        onMain { session.close() }
        OperatorPrefs.setShutterUsesAngle(context, usesAngle)
        OperatorPrefs.setShutterAngleDegrees(context, degrees)
    }

    @Test fun formatChangeWithUnknownExposureSendsNoShutter() {
        // Mode known, ISO and shutter not reported yet: the exposure is unknown.
        val camera = onMain {
            FakeCameraSession(FakeCameraSession.lunaLike().behavior, FakeDevice(0x01, emptyMap(), recording = null))
                .also { it.cameraReportsStatus(); session.control.bind(it) }
        }
        backend.readout.value = CameraReadout(
            shootingMode = CameraShootingMode.VIDEO,
            recordFormat = CameraRecordFormat(1, 3840, 2160, 25.0),
            recordFormats = listOf(CameraRecordFormat(1, 3840, 2160, 25.0), CameraRecordFormat(2, 3840, 2160, 30.0)),
        )
        assertTrue(waitUntil { session.status.value.fps == 25 })
        assertEquals(-1, onMain { session.status.value.expoMode })

        val thirty = onMain { session.status.value.availableVideoFormats.first { it.frameRate == VideoFrameRate.FPS30 } }
        assertTrue(onMain { session.setVideoFormat(thirty) })
        assertTrue(waitUntil { backend.calls("setRecordFormat").isNotEmpty() })
        SystemClock.sleep(300)
        assertEquals(emptyList(), onMain { camera.wire }.filter { "shutter" in it.lowercase() },
            "no hidden shutter SET while exposure is unknown")
    }
}
