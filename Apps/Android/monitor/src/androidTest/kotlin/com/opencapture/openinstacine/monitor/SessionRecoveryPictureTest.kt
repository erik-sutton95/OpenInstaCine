package com.opencapture.openinstacine.monitor

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.opencapture.opencine.decoder.HevcDecoder
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import com.opencapture.opencine.insta360.shell.EncodedVideoFrame
import com.opencapture.opencine.vocabulary.SessionRecoveryUi
import com.opencapture.openinstacine.monitor.session.PocketCameraSession
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * SIMULATED: actual consuming facade/Flow/probe/cancellation. Native codec admission and output
 * clocks are injected explicitly; this suite does not qualify MediaCodec or a physical camera.
 */
@RunWith(AndroidJUnit4::class)
class SessionRecoveryPictureTest {
    private fun backend() = FakeShellBackend().also { backend ->
        backend.frameGeneration = 1L
        backend.onConnect = {
            backend.frameGeneration = backend.frameGeneration!! + 1
            backend.phase.value = ConnectionPhase.LIVE
        }
    }

    private fun field(owner: Any, name: String): Any? =
        owner.javaClass.getDeclaredField(name).apply { isAccessible = true }.get(owner)

    private fun decoderField(session: PocketCameraSession, name: String, value: Any) {
        HevcDecoder::class.java.getDeclaredField(name).apply { isAccessible = true }.set(session.decoder, value)
    }

    private fun probeMinimum(session: PocketCameraSession): Long {
        val clock = field(session.decoder, "presentedClock")!!
        return field(clock, "minimumSourceNs") as Long
    }

    private fun beginRecovery(session: PocketCameraSession, backend: FakeShellBackend): Long {
        assertTrue(waitUntil { backend.frameFlow.subscriptionCount.value > 0 })
        val oldSourceStamp = System.nanoTime()
        onMain { backend.phase.value = ConnectionPhase.FAILED }
        assertTrue(waitUntil {
            backend.connectCalls.size == 1 && probeMinimum(session) > oldSourceStamp &&
                session.recoveryState.value is SessionRecoveryUi.Retrying
        })
        return oldSourceStamp
    }

    private fun frame(backend: FakeShellBackend, generation: Long? = backend.frameGeneration) {
        assertTrue(backend.frameFlow.tryEmit(EncodedVideoFrame(byteArrayOf(), 1, generation)))
    }

    @Test fun liveHandshakeAndOldPictureCannotCompleteRecoveryButCurrentPictureCan() {
        val backend = backend()
        val session = liveSession(backend)
        try {
            val oldStamp = beginRecovery(session, backend)
            assertEquals(ConnectionPhase.LIVE, session.phase)
            frame(backend, 1L)
            frame(backend, null)
            frame(backend)
            assertTrue(waitUntil { session.videoPackets == 1 })
            // An AU was received, but an empty AU did not enter the native decoder.
            session.decoder.notePresented(System.nanoTime())
            assertFalse(session.hasRecoveryPicture(0))
            onMain {
                decoderField(session, "hasSeenNativeOutput", true)
                decoderField(session, "lastDecoderOutputAt", 0L)
                decoderField(session, "lastDecoderAcceptedAt", SystemClock.elapsedRealtime())
            }
            // Neither a retained image nor stale native output establishes a recovered picture.
            session.decoder.notePresented(oldStamp)
            assertFalse(session.hasRecoveryPicture(SystemClock.elapsedRealtime() - 1_000))
            assertTrue(session.recoveryState.value is SessionRecoveryUi.Retrying)
            decoderField(session, "lastDecoderOutputAt", SystemClock.elapsedRealtime())
            session.decoder.notePresented(System.nanoTime())
            assertTrue(waitUntil { session.recoveryState.value == SessionRecoveryUi.Idle })
            assertEquals(1, backend.connectCalls.size)
        } finally { onMain { session.close() } }
    }

    @Test fun surfaceOnlyOutputUsesFreshAdmissionAndCodecStampedPresentation() {
        val backend = backend()
        val session = liveSession(backend)
        try {
            val oldStamp = beginRecovery(session, backend)
            frame(backend)
            assertTrue(waitUntil { session.videoPackets == 1 })
            decoderField(session, "lastDecoderAcceptedAt", SystemClock.elapsedRealtime())
            session.decoder.notePresented(oldStamp)
            assertFalse(session.hasRecoveryPicture(0))
            assertTrue(session.recoveryState.value is SessionRecoveryUi.Retrying)
            session.decoder.notePresented(System.nanoTime())
            assertTrue(waitUntil { session.recoveryState.value == SessionRecoveryUi.Idle })
        } finally { onMain { session.close() } }
    }

    @Test fun idleCancelsPendingEpisodeBeforeLateEvidenceAndDoesNotReconnect() {
        val backend = backend()
        val session = liveSession(backend)
        try {
            beginRecovery(session, backend)
            assertTrue(onMain { session.isSessionRecoveryRunning })
            onMain { backend.frameGeneration = 3L; backend.phase.value = ConnectionPhase.IDLE }
            assertTrue(waitUntil { !session.isSessionRecoveryRunning && !session.holdsMonitor })
            frame(backend, 2L)
            frame(backend)
            assertTrue(waitUntil { session.videoPackets == 1 })
            decoderField(session, "lastDecoderAcceptedAt", SystemClock.elapsedRealtime())
            session.decoder.notePresented(System.nanoTime())
            assertEquals(SessionRecoveryUi.Idle, session.recoveryState.value)
            assertEquals(1, backend.connectCalls.size)
        } finally { onMain { session.close() } }
    }

    @Test fun replacementDuringProbeWaitsForOperatorInsteadOfAcceptingOldProof() {
        val backend = backend()
        val session = liveSession(backend)
        try {
            beginRecovery(session, backend)
            onMain { backend.frameGeneration = 3L }
            frame(backend, 2L)
            decoderField(session, "lastDecoderAcceptedAt", SystemClock.elapsedRealtime())
            session.decoder.notePresented(System.nanoTime())
            assertTrue(waitUntil { session.recoveryState.value is SessionRecoveryUi.WaitingForOperator })
            assertEquals(1, backend.connectCalls.size)
        } finally { onMain { session.close() } }
    }

    /** IA-366: a live link reached outside the episode (a resume reconnect) clears the waiting card. */
    @Test fun liveOutsideTheEpisodeRetiresTheWaitingCard() {
        val backend = backend()
        val session = liveSession(backend)
        try {
            beginRecovery(session, backend)
            onMain { backend.frameGeneration = 3L }
            frame(backend, 2L)
            decoderField(session, "lastDecoderAcceptedAt", SystemClock.elapsedRealtime())
            session.decoder.notePresented(System.nanoTime())
            assertTrue(waitUntil { session.recoveryState.value is SessionRecoveryUi.WaitingForOperator })
            onMain { backend.phase.value = ConnectionPhase.SCANNING }
            onMain { backend.phase.value = ConnectionPhase.LIVE }
            assertTrue(waitUntil { session.recoveryState.value == SessionRecoveryUi.Idle })
        } finally { onMain { session.close() } }
    }

    @Test fun sourceReplacementRejectsQueuedOldAndUnknownFrames() {
        val backend = backend()
        val session = liveSession(backend)
        try {
            assertTrue(waitUntil { backend.frameFlow.subscriptionCount.value > 0 })
            val lock = field(session, "recoveryFrameLock")!!
            synchronized(lock) {
                frame(backend, 1L)
                backend.frameGeneration = 2L
                frame(backend, null)
            }
            frame(backend)
            assertTrue(waitUntil { session.videoPackets == 1 })
            assertEquals(1, session.accessUnits)
        } finally { onMain { session.close() } }
    }

    @Test fun unknownSourceCannotCompleteEvenWithFreshClocks() {
        val backend = FakeShellBackend()
        val session = liveSession(backend)
        try {
            assertTrue(waitUntil { backend.frameFlow.subscriptionCount.value > 0 })
            frame(backend)
            assertTrue(waitUntil { session.videoPackets == 1 })
            decoderField(session, "lastDecoderAcceptedAt", SystemClock.elapsedRealtime())
            session.decoder.notePresented(System.nanoTime())
            assertFalse(session.hasRecoveryPicture(0))
        } finally { onMain { session.close() } }
    }

    @Test fun liveWithoutPictureTimesOutAndRetriesWithinExistingPolicy() {
        val backend = backend()
        val session = liveSession(backend)
        try {
            onMain { backend.phase.value = ConnectionPhase.FAILED }
            assertTrue(waitUntil(timeoutMs = 15_000) { backend.connectCalls.size >= 2 })
            assertTrue(session.recoveryState.value is SessionRecoveryUi.Retrying)
            onMain { session.disconnect() }
            assertEquals(SessionRecoveryUi.Idle, session.recoveryState.value)
        } finally { onMain { session.close() } }
    }
}
