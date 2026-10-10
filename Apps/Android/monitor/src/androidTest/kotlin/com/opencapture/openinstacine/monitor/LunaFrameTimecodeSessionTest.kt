package com.opencapture.openinstacine.monitor

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
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

    private fun timecode() = onMain { session.status.value.timecode }

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

    /** `HH:MM:SS:FF` as (second of day, frame). */
    private fun parse(text: String): Pair<Int, Int> {
        val (h, m, s, f) = text.split(":").map(String::toInt)
        return (h * 3600 + m * 60 + s) to f
    }

    @Test fun frameStampsPinToTheEarliestArrivalAndPublishOncePerSecond() {
        val first = 100_000L
        frameUntilShown(first)
        val (second, frames) = parse(timecode()!!)
        // Unknown fps counts 25 frames a second, so the frame number places the arrival within
        // 40 ms of its second; each probe below stays clear of that uncertainty. Older stamps
        // arrived later than the pinned one, so the offset holds.
        val previousSecond = (second + 86_399) % 86_400
        fun assertUnchanged(stampMs: Long) {
            val before = timecode()
            frame(stampMs)
            SystemClock.sleep(300)
            assertEquals(before, timecode(), "the timecode changes only when its second does")
        }
        fun assertPrevious(stampMs: Long, expectedFrames: Set<Int>) {
            val before = timecode()
            frame(stampMs)
            assertTrue(waitUntil { timecode() != before })
            val (shown, shownFrames) = parse(timecode()!!)
            assertEquals(previousSecond, shown)
            assertTrue(shownFrames in expectedFrames, "frame $shownFrames")
        }
        if (frames >= 10) {
            assertUnchanged(first - 250)
            assertPrevious(first - (frames + 1) * 40 - 300, setOf(16, 17))
        } else {
            val previous = first - (frames + 1) * 40 - 500
            assertPrevious(previous, setOf(11, 12))
            assertUnchanged(previous - 250)
        }
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
