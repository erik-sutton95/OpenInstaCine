package com.opencapture.openpocketcine

import android.content.Context
import com.opencapture.opencine.core.Observation
import com.opencapture.opencine.core.ObservationOrigin
import com.opencapture.openpocketcine.feed.MonitorTransfer
import kotlin.math.exp

/**
 * iOS `PictureEVMeter`: EV meter for a camera that reports no metered EV. The picture's median
 * against 18% grey, less where the camera's own auto exposure places it. With matrix metering
 * the Luna puts the I-Log median about 1.3 stops under 18% grey at EV 0. While the camera
 * exposes in auto that offset is learned (median stops minus EV comp), so in manual the meter
 * reads how far the exposure is from where auto would put it.
 *
 * One instance per source (STATE-01). The learned offset belongs to a [Source]: device, recording
 * profile and transfer, and metering. Storage keys: v2 `OpenInstaCine.PictureEVMeter.v2.<key>` per
 * source; the v1 per-transfer `OpenInstaCine.PictureEVMeter.offset.<TRANSFER>` is read only, as the
 * starting value of every v2 key with that transfer (read-through migration, so a rerun changes
 * nothing). Saves write only this instance's own keys.
 */
internal class PictureEVMeter(
    private val read: (String) -> Double? = { null },
    private val write: (String, Double) -> Unit = { _, _ -> },
) {
    data class Source(val device: String, val profile: String, val transfer: MonitorTransfer, val metering: String) {
        val key: String get() = "$device|$profile|${transfer.name}|$metering"
    }

    private val offsets = HashMap<String, Double>()
    private val dirty = HashSet<String>()
    private var lastAt: Double? = null
    private var savedAt = 0.0

    fun offset(source: Source): Double = offsets.getOrPut(source.key) {
        read(V2 + source.key) ?: read(V1 + source.transfer.name) ?: SEEDS[source.transfer] ?: 0.0
    }

    /**
     * Metered EV in stops, estimated from the picture (never a camera report). [evComp] is the
     * camera's compensation while it exposes in auto, null in manual.
     */
    fun stops(picture: Double, source: Source, evComp: Double?, now: Double): Observation<Double> {
        var offset = offset(source)
        if (evComp != null) {
            val dt = lastAt?.let { (now - it).coerceIn(0.0, 0.5) } ?: 0.0
            offset += (picture - evComp - offset) * (1 - exp(-dt / LEARN_SECONDS))
            offsets[source.key] = offset
            dirty += source.key
            if (now - savedAt > 5) save(now)
        }
        lastAt = now
        return Observation(picture - offset, ObservationOrigin.IMAGE_ESTIMATED, at = null)
    }

    private fun save(now: Double) {
        savedAt = now
        dirty.forEach { write(V2 + it, offsets.getValue(it)) }
        dirty.clear()
    }

    companion object {
        /** Time for the learned offset to follow a new scene (first order). */
        const val LEARN_SECONDS = 3.0
        private val SEEDS = mapOf(MonitorTransfer.ILOG to -1.3)
        private const val PREFS = "openpocketcine.operator"
        const val V1 = "OpenInstaCine.PictureEVMeter.offset."
        const val V2 = "OpenInstaCine.PictureEVMeter.v2."

        /** A meter over the operator preferences. Each session makes its own. */
        fun stored(context: Context): PictureEVMeter {
            val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            return PictureEVMeter(
                read = { key -> if (prefs.contains(key)) prefs.getFloat(key, 0f).toDouble() else null },
                write = { key, value -> prefs.edit().putFloat(key, value.toFloat()).apply() },
            )
        }
    }
}
