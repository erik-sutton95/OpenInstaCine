package com.opencapture.openpocketcine.feed

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ScopeSamplePublicationTest {
    private val bus = LiveScopeSampleBus()
    @Test fun changingClipsClearsScopesAndRejectsAnAlreadyQueuedOldResult() {
        val first = bus.openSource()
        val oldFrame = picture(200)
        assertTrue(bus.publish(first, oldFrame))
        val queuedPublish = { bus.publish(first, oldFrame) }
        val second = bus.openSource()
        try {
            assertFalse(queuedPublish())
            assertTrue(bus.bundle.isEmpty)
            val newFrame = picture(80)
            assertTrue(bus.publish(second, newFrame))
            assertEquals(newFrame, bus.bundle)
        } finally { bus.closeSource(second) }
    }

    @Test fun departingLiveRendererCannotOverwriteOrClearPlayback() {
        val live = bus.openSource()
        val playback = bus.openSource()
        val frame = picture(128)
        try {
            assertTrue(bus.publish(playback, frame))
            assertFalse(bus.publish(live, picture(230)))
            bus.closeSource(live)
            assertEquals(frame, bus.bundle)
            assertTrue(bus.isCurrent(playback))
        } finally { bus.closeSource(playback) }
        assertFalse(bus.publish(playback, frame))
        assertTrue(bus.bundle.isEmpty)
    }

    private fun picture(code: Int) = ScopeAssistBundle(
        revision = 1,
        samples = ScopeSamples.EMPTY.copy(histogramLuma = IntArray(256).also { it[code] = 9 }),
    )
}
