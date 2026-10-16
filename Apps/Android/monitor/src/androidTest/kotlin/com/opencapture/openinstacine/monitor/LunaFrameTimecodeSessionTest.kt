package com.opencapture.openinstacine.monitor

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.opencapture.monitorui.MonitorTimecodeFormat
import com.opencapture.opencine.appkit.label
import com.opencapture.opencine.core.TimecodePrecision
import com.opencapture.opencine.insta360.luna.LunaCameraSession
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import com.opencapture.opencine.insta360.shell.EncodedVideoFrame
import com.opencapture.openinstacine.monitor.session.PocketCameraSession
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Characterization of the session facade's time-of-day timecode from live frame stamps: pinned to
 * the phone clock by the earliest arrival, published once a second, cleared when the link phase
 * changes.
 */
@RunWith(AndroidJUnit4::class)
class LunaFrameTimecodeSessionTest {
    private val backend = FakeShellBackend()
    private lateinit var session: PocketCameraSession

    @Before fun open() { session = liveSession(backend) }
    @After fun close() { onMain { session.close() } }

    /** The clock the common Luna session publishes, formatted by the shared rule (seconds, D2). */
    private fun timecode() = onMain {
        (session.control.state.value.session as? LunaCameraSession)?.snapshots?.value?.timecode?.value
            ?.let { MonitorTimecodeFormat.label(it, TimecodePrecision.Seconds) }
    }

    /** Emits a frame stamped [stampMs] on the frame clock (the backend reports microseconds). */
    private fun frame(stampMs: Long) {
        assertTrue(waitUntil { backend.frameFlow.subscriptionCount.value > 0 })
        assertTrue(backend.frameFlow.tryEmit(EncodedVideoFrame(ByteArray(0), stampMs * 1_000)))
    }

    /** Repeats a frame until a timecode shows (the collector may still be subscribing). */
    private fun frameUntilShown(stampMs: Long) {
        val end = SystemClock.elapsedRealtime() + 5_000
        while (timecode() == null && SystemClock.elapsedRealtime() < end) {
            frame(stampMs)
            SystemClock.sleep(20)
        }
        assertNotNull(timecode())
    }

    /** `HH:MM:SS` (whole seconds: the phone clock invents no frame field) as the second of day. */
    private fun parse(text: String): Int {
        val (h, m, s) = text.split(":").map(String::toInt)
        return h * 3600 + m * 60 + s
    }

    @Test fun frameStampsPinToTheEarliestArrivalAndPublishOncePerSecond() {
        val first = 100_000L
        frameUntilShown(first)
        val shown = timecode()!!
        val second = parse(shown)
        // Later arrivals keep the earliest offset, so a frame stamped a whole second earlier shows
        // exactly the previous second, whatever the sub-second phase of the pinned arrival.
        frame(first - 1_000)
        assertTrue(waitUntil { timecode() != shown })
        val previous = timecode()
        assertEquals((second + 86_399) % 86_400, parse(previous!!))
        frame(first - 1_000)
        SystemClock.sleep(300)
        assertEquals(previous, timecode(), "the timecode changes only when its second does")
        frame(first)
        assertTrue(waitUntil { timecode() != previous })
        assertEquals(shown, timecode())
    }

    @Test fun linkPhaseChangesClearTheTimecodeAndStartThePinningOver() {
        frameUntilShown(100_000)
        backend.phase.value = ConnectionPhase.IDLE
        assertTrue(waitUntil { timecode() == null })
        val polls = backend.calls("gimbalAngle").size
        backend.phase.value = ConnectionPhase.LIVE
        // The live handler resets, then restarts the angle poll.
        assertTrue(waitUntil { backend.calls("gimbalAngle").size > polls })
        // The same stamp publishes again: the reset forgot the reported second.
        frameUntilShown(100_000)
    }
}
