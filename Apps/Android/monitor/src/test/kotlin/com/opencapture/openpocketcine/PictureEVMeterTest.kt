package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.feed.MonitorTransfer
import kotlin.test.Test
import kotlin.test.assertEquals

class PictureEVMeterTest {
    @Test
    fun learnsTheAutoExposurePlacementAndReadsManualAgainstIt() {
        var saved: Map<MonitorTransfer, Double> = emptyMap()
        val meter = PictureEVMeter { saved = it }
        // Seeded: auto at EV 0 with the I-Log median 1.3 stops under grey reads 0.
        assertEquals(0.0, meter.stops(-1.3, MonitorTransfer.ILOG, evComp = null, now = 0.0), 1e-9)
        // Auto at EV 0 in a scene the camera places at -0.8: the offset follows.
        var t = 0.0
        while (t < 20) {
            t += 0.04
            meter.stops(-0.8, MonitorTransfer.ILOG, evComp = 0.0, now = t)
        }
        assertEquals(-0.8, meter.offset(MonitorTransfer.ILOG), 0.01)
        assertEquals(-0.8, saved.getValue(MonitorTransfer.ILOG), 0.05)
        // Manual, one stop darker than auto chose: reads -1.0; the offset holds.
        assertEquals(-1.0, meter.stops(-1.8, MonitorTransfer.ILOG, evComp = null, now = t + 1), 0.01)
        assertEquals(-0.8, meter.offset(MonitorTransfer.ILOG), 0.01)
        // Rec.709 has no seed.
        assertEquals(0.4, meter.stops(0.4, MonitorTransfer.REC709, evComp = null, now = t + 2), 1e-9)
    }

    @Test
    fun pictureStopsIsTheLumaMedianAgainstGrey() {
        // All pixels at the Rec.709 code for 18% grey read 0 stops; an empty histogram reads nothing.
        val grey = (0..255).minBy { kotlin.math.abs(com.opencapture.openpocketcine.feed.LiveColorScience.stops(it / 255.0, MonitorTransfer.REC709)) }
        val histogram = IntArray(256).also { it[grey] = 100 }
        assertEquals(0.0, NDFilterRecommendation.pictureStops(histogram, MonitorTransfer.REC709)!!, 0.1)
        assertEquals(null, NDFilterRecommendation.pictureStops(IntArray(256), MonitorTransfer.REC709))
    }
}
