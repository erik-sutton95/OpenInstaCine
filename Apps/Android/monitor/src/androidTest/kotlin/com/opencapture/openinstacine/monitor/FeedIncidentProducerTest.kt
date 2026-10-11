package com.opencapture.openinstacine.monitor

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import com.opencapture.opencine.insta360.shell.EncodedVideoFrame
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** SIMULATED actual facade producer and captured sink submission; no native codec or camera. */
@RunWith(AndroidJUnit4::class)
class FeedIncidentProducerTest {
    @Test fun actualFacadePublishesBoundedSnapshotsWithoutInventingTransportOrDecodeClocks() {
        val backend = FakeShellBackend().also { it.frameGeneration = 1L }
        val sink = RecordingFeedIncidentSink()
        val session = liveSession(backend, sink)
        try {
            assertEquals(1, sink.contexts.size)
            assertTrue(waitUntil { backend.frameFlow.subscriptionCount.value > 0 })
            assertTrue(backend.frameFlow.tryEmit(EncodedVideoFrame(byteArrayOf(), 1, 1L)))
            assertTrue(waitUntil { session.accessUnits == 1 })
            assertTrue(waitUntil { sink.snapshots.isNotEmpty() })
            val snapshot = sink.snapshots.last()
            assertNotNull(snapshot.ages.accessUnitAge)
            assertNull(snapshot.ages.packetAge)
            assertNull(snapshot.ages.statusAge)
            assertNull(snapshot.ages.decodeAcceptAge)
            assertNull(snapshot.ages.decodedOutputAge)
            assertNull(snapshot.ages.presentAge)
            assertNull(snapshot.ingress)
            assertFalse(snapshot.lifecycle.liveEstablished)
            // One AU is not one report. Native stages have no clocks until actual native admission.
            assertFalse(sink.events.contains("disconnected"))
            assertFalse(sink.events.contains("exhausted"))
            onMain { session.noteSceneBecameInactive() }
            assertTrue(waitUntil { sink.snapshots.last().lifecycle.foreground == false })
            onMain { session.disconnect() }
            assertEquals("end", sink.events.last())
        } finally { onMain { session.close() } }
    }

    @Test fun replacingFacadeRetiresOldSinkAndRejectsItsLateLifecycleSubmissions() {
        val oldSink = RecordingFeedIncidentSink()
        val firstBackend = FakeShellBackend()
        val first = liveSession(firstBackend, oldSink)
        val nextSink = RecordingFeedIncidentSink()
        val second = liveSession(FakeShellBackend(), nextSink)
        try {
            assertEquals("end", oldSink.events.last())
            assertEquals(1, oldSink.events.count { it == "end" })
            val retiredEvents = oldSink.events.toList()
            onMain { first.noteSceneBecameInactive(); first.close() }
            assertEquals(retiredEvents, oldSink.events.toList())
            assertEquals(1, nextSink.contexts.size)
            assertFalse(nextSink.events.contains("end"))
            assertTrue(waitUntil { nextSink.snapshots.isNotEmpty() })
            onMain { second.close() }
            assertEquals("end", nextSink.events.last())
        } finally { onMain { first.close(); second.close() } }
    }

    @Test fun actualFacadeRetainsTheMediaBindingInsteadOfSubmittingToTheUnboundSink() {
        val unbound = RecordingFeedIncidentSink()
        val bound = RecordingFeedIncidentSink()
        val hostSink = object : com.opencapture.opencine.media.FeedIncidentSink by unbound {
            override fun beginBoundSession(context: com.opencapture.opencine.media.FeedIncidentSessionContext): com.opencapture.opencine.media.FeedIncidentSource {
                bound.beginSession(context)
                return bound
            }
        }
        val session = liveSession(FakeShellBackend(), hostSink)
        try {
            assertEquals(1, bound.contexts.size)
            assertTrue(waitUntil { bound.snapshots.isNotEmpty() })
            onMain { session.noteSceneBecameInactive() }
            assertTrue(bound.events.contains("breadcrumb"))
            onMain { session.close() }
            assertEquals("end", bound.events.last())
            assertTrue(unbound.contexts.isEmpty())
            assertTrue(unbound.snapshots.isEmpty())
            assertTrue(unbound.events.isEmpty())
        } finally { onMain { session.close() } }
    }

    @Test fun anActualFailedLiveLinkRecordsDisconnectAndOperatorExitEndsTheSameSession() {
        val sink = RecordingFeedIncidentSink()
        val backend = FakeShellBackend()
        val session = liveSession(backend, sink)
        try {
            onMain { backend.phase.value = ConnectionPhase.FAILED }
            assertTrue(waitUntil { sink.events.contains("disconnected") })
            onMain { session.abandonRecoveryToMenu() }
            assertEquals(1, sink.contexts.size)
            assertEquals(1, sink.events.count { it == "end" })
            assertFalse(sink.events.contains("exhausted"))
        } finally { onMain { session.close() } }
    }
}
