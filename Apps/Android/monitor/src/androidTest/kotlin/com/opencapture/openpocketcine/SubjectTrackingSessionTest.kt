package com.opencapture.openpocketcine

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.opencapture.opencine.insta360.shell.CameraNotice
import com.opencapture.opencine.insta360.shell.CameraTrackFrame
import com.opencapture.opencine.insta360.shell.CameraTrackState
import com.opencapture.openpocketcine.session.FocusOverlay
import com.opencapture.openpocketcine.session.PocketCameraSession
import com.opencapture.openpocketcine.session.TrackingBox
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Characterization of the session facade's Deep Track and tap focus: what it sends through the
 * backend's controls, and how the camera's track frames and notices drive the boxes it shows.
 */
@RunWith(AndroidJUnit4::class)
class SubjectTrackingSessionTest {
    private val backend = FakeShellBackend()
    private lateinit var session: PocketCameraSession
    private val request = TrackingBox(0.1, 0.1, 0.2, 0.2)

    @Before fun open() { session = liveSession(backend) }
    @After fun close() { onMain { session.close() } }

    private fun overlay() = onMain { session.trackingHud.value.overlay }
    private fun tracking() = onMain { session.trackingHud.value.isTracking }
    private fun note() = onMain { session.controlNote.value }

    private fun frame(state: CameraTrackState, box: TrackingBox) {
        assertTrue(waitUntil { backend.trackFrameFlow.subscriptionCount.value > 0 })
        assertTrue(backend.trackFrameFlow.tryEmit(CameraTrackFrame(state, box.x, box.y, box.width, box.height)))
    }

    private fun notice(active: Boolean) {
        assertTrue(waitUntil { backend.noticeFlow.subscriptionCount.value > 0 })
        assertTrue(backend.noticeFlow.tryEmit(CameraNotice.Tracking(active)))
    }

    /** Lets a frame or notice that should change nothing reach the facade. */
    private fun settle() = SystemClock.sleep(200)

    private fun start(box: TrackingBox) {
        val sent = backend.calls("startTracking").size
        onMain { session.startTracking(box) }
        assertTrue(waitUntil { backend.calls("startTracking").size == sent + 1 })
    }

    @Test fun startSendsTheBoxInsideTheFrameAndTheStreamDrivesTheBoxes() {
        val edge = TrackingBox(0.8, -0.1, 0.4, 0.3)
        start(edge)
        assertEquals(listOf(0.8, 0.0, minOf(0.4, 1 - 0.8), minOf(0.3, 1 - 0.0)), backend.calls("startTracking").single().args)
        assertEquals(FocusOverlay.Search(edge), overlay())
        assertTrue(tracking())

        // Before the first lock, lost and idle frames change nothing.
        frame(CameraTrackState.LOST, TrackingBox(0.82, 0.0, 0.1, 0.1))
        frame(CameraTrackState.IDLE, TrackingBox(0.0, 0.0, 0.0, 0.0))
        settle()
        assertEquals(FocusOverlay.Search(edge), overlay())

        val locked = TrackingBox(0.82, 0.02, 0.1, 0.1)
        frame(CameraTrackState.TRACKING, locked)
        assertTrue(waitUntil { overlay() == FocusOverlay.Subject(locked) })
        val lost = TrackingBox(0.85, 0.05, 0.1, 0.1)
        frame(CameraTrackState.LOST, lost)
        assertTrue(waitUntil { overlay() == FocusOverlay.Search(lost) }, "the last box searches until reacquired")
        assertTrue(tracking())
        frame(CameraTrackState.IDLE, lost)
        assertTrue(waitUntil { overlay() == FocusOverlay.Focus })
        assertFalse(tracking())
    }

    @Test fun thePreviousSubjectIsIgnoredUntilTheCameraReportsOneNearTheNewBox() {
        start(request)
        frame(CameraTrackState.TRACKING, TrackingBox(0.7, 0.7, 0.1, 0.1))
        settle()
        assertEquals(FocusOverlay.Search(request), overlay())
        val near = TrackingBox(0.15, 0.15, 0.1, 0.1)
        frame(CameraTrackState.TRACKING, near)
        assertTrue(waitUntil { overlay() == FocusOverlay.Subject(near) })
    }

    @Test fun noticesLockTheSearchAndEndTracking() {
        start(request)
        notice(true)
        assertTrue(waitUntil { overlay() == FocusOverlay.Subject(TrackingBox.subject(request)) })
        assertTrue(tracking())
        notice(false)
        assertTrue(waitUntil { overlay() == FocusOverlay.Focus })
        assertFalse(tracking())
        notice(false)
        settle()
        assertEquals(FocusOverlay.Focus, overlay())
    }

    @Test fun aRefusedStartClearsTheBoxesAndSaysSo() {
        backend.accepts = false
        start(request)
        assertTrue(waitUntil { note() == "Deep Track did not start." })
        assertEquals(FocusOverlay.Focus, overlay())
        assertFalse(tracking())
    }

    @Test fun aTooSmallBoxSendsNothing() {
        onMain { session.startTracking(TrackingBox(0.5, 0.5, 0.05, 0.2)) }
        assertTrue(waitUntil { note() == "Frame Too Small" })
        settle()
        assertTrue(backend.calls("startTracking").isEmpty())
        assertEquals(FocusOverlay.Focus, overlay())
    }

    @Test fun cancelSendsTheCameraCancelOnlyWhileTracking() {
        onMain { session.cancelTracking() }
        settle()
        assertTrue(backend.calls("stopTracking").isEmpty())
        start(request)
        onMain { session.cancelTracking() }
        assertEquals(FocusOverlay.Focus, overlay())
        assertFalse(tracking())
        assertTrue(waitUntil { backend.calls("stopTracking").size == 1 })
        onMain { session.cancelTracking() }
        settle()
        assertEquals(1, backend.calls("stopTracking").size)
    }

    @Test fun tapFocusEndsTrackingAndSendsThePoint() {
        start(request)
        onMain { session.tapFocus(0.3f, 0.6f) }
        assertTrue(waitUntil { backend.calls("tapFocus").size == 1 })
        assertEquals(listOf(0.3f.toDouble(), 0.6f.toDouble()), backend.calls("tapFocus").single().args)
        assertEquals(1, backend.calls("stopTracking").size, "a tap focus ends Deep Track")
        assertEquals(FocusOverlay.Focus, overlay())
        assertFalse(tracking())

        backend.accepts = false
        onMain { session.tapFocus(0.5f, 0.5f) }
        assertTrue(waitUntil { note() == "Focus did not reach the camera." })
        assertEquals(1, backend.calls("stopTracking").size, "no cancel without tracking")
    }
}
