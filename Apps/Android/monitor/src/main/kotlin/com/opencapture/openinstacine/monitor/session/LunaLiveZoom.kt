package com.opencapture.openinstacine.monitor.session

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Live Luna zoom, the twin of iOS `updateZoomPinch` and `queueZoomWrite` (#111). The zoom wheel
 * and pinch write while the finger moves instead of once on lift. Writes are coalesced: the
 * latest factor wins, at most one write is in flight, and each write is followed by
 * [WRITE_GAP_MS] because the camera cannot take a 60 Hz drag. Lifting the finger queues the
 * final factor, so it is always the last write of the burst.
 *
 * Confined to the session's main scope, like the rest of the session state.
 */
internal class LunaLiveZoom(
    private val scope: CoroutineScope,
    private val canWrite: () -> Boolean,
    private val write: suspend (Double) -> Boolean,
    /** The burst drained: the last factor written and whether the camera took it. */
    private val burstEnded: (last: Double, applied: Boolean) -> Unit,
) {
    /** The factor under the finger, null outside a drag. */
    var preview: Double? = null
        private set
    private var anchor = 1.0
    private var pending: Double? = null
    private var worker: Job? = null

    /** A write is in flight or waiting out its gap. */
    val isWriting: Boolean get() = worker?.isActive == true

    /**
     * One wheel or pinch sample: [magnification] of the factor the drag began at ([current] on
     * the first sample), kept within 1x and [maximum]. Returns the factor now under the finger.
     */
    fun drag(magnification: Double, current: Double, maximum: Double): Double {
        if (preview == null) anchor = current
        val factor = (anchor * magnification).coerceIn(1.0, maxOf(1.0, maximum))
        preview = factor
        queue(factor)
        return factor
    }

    /** The finger lifted: the final factor is queued again so the camera ends on it. */
    fun end(): Double? {
        val last = preview ?: return null
        preview = null
        queue(last)
        return last
    }

    /** Writes [factor] as soon as the write in flight and its gap finish; a newer factor replaces it. */
    fun queue(factor: Double) {
        if (!canWrite()) return
        pending = factor
        if (isWriting) return
        worker = scope.launch {
            var last = factor
            var applied = true
            var retried: Double? = null
            while (true) {
                val next = pending ?: break
                pending = null
                if (!canWrite()) break
                last = next
                // The camera leaves the odd zoom SET unanswered (about 2 in 100 on fw 1.2.7): a
                // newer factor replaces it; the burst's last factor is sent once more.
                val isRetry = retried == next
                applied = write(next)
                if (applied) retried = null
                else if (pending == null && !isRetry) { retried = next; pending = next }
                delay(WRITE_GAP_MS)
            }
            burstEnded(last, applied)
        }
    }

    /** The link left live: drop the drag and any queued write. */
    fun cancel() {
        pending = null
        preview = null
        worker?.cancel()
        worker = null
    }

    companion object {
        /**
         * iOS `zoomWriteGap`. The Luna makes a quick jump to each written factor and holds it, so
         * the write rate is what the picture shows: 80 ms stepped visibly on a preset ramp; 10 ms
         * (about 28 writes a second with the round trip, close to the official zoom bar) looked
         * smoothest on fw 1.2.7 (2026-11-22); no gap at all once froze the camera for seconds.
         */
        const val WRITE_GAP_MS = 10L
    }
}
