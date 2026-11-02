package com.opencapture.openinstacine.monitor.session

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.currentTime
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * #111: a zoom wheel or pinch drag reaches the Luna while the finger moves, coalesced to one
 * write in flight with the latest factor winning, and the final factor is the last write.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class LunaLiveZoomTest {
    private data class Write(val factor: Double, val startedAt: Long, val endedAt: Long)

    private class Camera(private val scope: TestScope, private val roundTripMs: Long = 30) {
        val writes = mutableListOf<Write>()
        var inFlight = 0
        var maxInFlight = 0
        var accepts = true
        val bursts = mutableListOf<Pair<Double, Boolean>>()

        fun zoom(scope: CoroutineScope, live: () -> Boolean = { true }) = LunaLiveZoom(scope, live,
            write = { factor ->
                val started = this.scope.currentTime
                inFlight += 1
                maxInFlight = maxOf(maxInFlight, inFlight)
                delay(roundTripMs)
                inFlight -= 1
                writes += Write(factor, started, this.scope.currentTime)
                accepts
            },
            burstEnded = { last, applied -> bursts += last to applied })
    }

    /** 60 Hz samples from 1x toward 6x over [durationMs], then the finger lifts. */
    private fun TestScope.drag(zoom: LunaLiveZoom, durationMs: Long = 600): List<Double> {
        val samples = mutableListOf<Double>()
        var t = 0L
        while (t <= durationMs) {
            samples += zoom.drag(1.0 + 5.0 * t / durationMs, current = 1.0, maximum = 15.0)
            advanceTimeBy(16)
            t += 16
        }
        return samples
    }

    @Test fun aDragWritesLiveCoalescedAndEndsOnTheFinalFactor() = runTest {
        val camera = Camera(this)
        val zoom = camera.zoom(this)

        val samples = drag(zoom)
        val liftedAt = currentTime
        val writesWhileDragging = camera.writes.count { it.startedAt < liftedAt }
        val final = zoom.end()
        advanceUntilIdle()

        assertTrue(writesWhileDragging >= 4, "the camera follows the finger before it lifts: $writesWhileDragging writes")
        assertTrue(camera.writes.size < samples.size / 2, "${samples.size} samples coalesce, not one write each: ${camera.writes.size}")
        assertEquals(1, camera.maxInFlight, "at most one zoom write in flight")
        camera.writes.zipWithNext().forEach { (a, b) ->
            assertTrue(b.startedAt - a.endedAt >= LunaLiveZoom.WRITE_GAP_MS, "the Luna gets ${LunaLiveZoom.WRITE_GAP_MS} ms between writes")
        }
        val factors = camera.writes.map { it.factor }
        assertEquals(factors.sorted(), factors, "latest wins: an older factor never follows a newer one")
        assertEquals(samples.last(), final)
        assertEquals(final, camera.writes.last().factor, "the final factor is the last write")
        assertEquals(listOf(final!! to true), camera.bursts.takeLast(1))
    }

    @Test fun aFingerHeldStillStopsWritingAndLiftingResendsTheFinalFactor() = runTest {
        val camera = Camera(this)
        val zoom = camera.zoom(this)

        zoom.drag(2.0, current = 1.5, maximum = 15.0)
        advanceTimeBy(1_000)
        assertEquals(listOf(3.0), camera.writes.map { it.factor }, "one write, then the stream rests")

        zoom.end()
        advanceUntilIdle()
        assertEquals(listOf(3.0, 3.0), camera.writes.map { it.factor })
        assertEquals(null, zoom.preview)
    }

    @Test fun aRefusedFinalWriteIsReportedAndLeavingLiveDropsQueuedWrites() = runTest {
        val camera = Camera(this)
        var live = true
        val zoom = camera.zoom(this) { live }

        camera.accepts = false
        zoom.queue(4.0)
        advanceUntilIdle()
        assertEquals(listOf(4.0 to false), camera.bursts)

        camera.accepts = true
        zoom.drag(2.0, current = 1.0, maximum = 15.0)
        zoom.drag(3.0, current = 1.0, maximum = 15.0)
        live = false
        zoom.cancel()
        zoom.drag(4.0, current = 1.0, maximum = 15.0)
        advanceUntilIdle()
        assertEquals(listOf(4.0), camera.writes.map { it.factor }, "nothing after the link left live")
    }
}
