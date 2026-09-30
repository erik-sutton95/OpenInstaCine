package com.opencapture.openpocketcine

import android.content.Context
import com.opencapture.openpocketcine.feed.MonitorTransfer
import kotlin.math.exp

/**
 * iOS `PictureEVMeter`: EV meter for a camera that reports no metered EV. The picture's median
 * against 18% grey, less where the camera's own auto exposure places it. With matrix metering
 * the Luna puts the I-Log median about 1.3 stops under 18% grey at EV 0. While the camera
 * exposes in auto that offset is learned (median stops minus EV comp) and kept per curve, so in
 * manual the meter reads how far the exposure is from where auto would put it.
 */
internal class PictureEVMeter(
    initial: Map<MonitorTransfer, Double> = emptyMap(),
    private val save: (Map<MonitorTransfer, Double>) -> Unit = {},
) {
    private val offsets = initial.toMutableMap()
    private var lastAt: Double? = null
    private var savedAt = 0.0

    fun offset(transfer: MonitorTransfer): Double = offsets[transfer] ?: SEEDS[transfer] ?: 0.0

    /** Metered EV in stops. [evComp] is the camera's compensation while it exposes in auto, null in manual. */
    fun stops(picture: Double, transfer: MonitorTransfer, evComp: Double?, now: Double): Double {
        var offset = offset(transfer)
        if (evComp != null) {
            val dt = lastAt?.let { (now - it).coerceIn(0.0, 0.5) } ?: 0.0
            offset += (picture - evComp - offset) * (1 - exp(-dt / LEARN_SECONDS))
            offsets[transfer] = offset
            if (now - savedAt > 5) {
                savedAt = now
                save(offsets.toMap())
            }
        }
        lastAt = now
        return picture - offset
    }

    companion object {
        /** Time for the learned offset to follow a new scene (first order). */
        const val LEARN_SECONDS = 3.0
        private val SEEDS = mapOf(MonitorTransfer.ILOG to -1.3)
        private const val PREFS = "openpocketcine.operator"
        private const val KEY = "OpenInstaCine.PictureEVMeter.offset."
        private var shared: PictureEVMeter? = null

        fun shared(context: Context): PictureEVMeter = shared ?: run {
            val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val stored = MonitorTransfer.entries.filter { prefs.contains(KEY + it.name) }
                .associateWith { prefs.getFloat(KEY + it.name, 0f).toDouble() }
            PictureEVMeter(stored) { offsets ->
                prefs.edit().apply { offsets.forEach { (t, v) -> putFloat(KEY + t.name, v.toFloat()) } }.apply()
            }.also { shared = it }
        }
    }
}
