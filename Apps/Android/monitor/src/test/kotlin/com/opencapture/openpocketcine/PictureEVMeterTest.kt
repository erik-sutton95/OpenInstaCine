package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.feed.MonitorTransfer
import com.opencapture.opencine.core.ObservationOrigin
import kotlin.test.Test
import kotlin.test.assertEquals

class PictureEVMeterTest {
    private val ilogA = PictureEVMeter.Source("LUNA-A", "226", MonitorTransfer.ILOG, "matrix")
    private val ilogB = PictureEVMeter.Source("LUNA-B", "226", MonitorTransfer.ILOG, "matrix")

    /** Fake operator preferences: the same key space the SharedPreferences meter reads and writes. */
    private fun meter(prefs: MutableMap<String, Double>) = PictureEVMeter(read = prefs::get, write = prefs::put)

    /** Auto at EV 0 in a scene the camera places at [placed], long enough for the offset to follow. */
    private fun learn(meter: PictureEVMeter, source: PictureEVMeter.Source, placed: Double, from: Double = 0.0): Double {
        var t = from
        while (t < from + 20) {
            t += 0.04
            meter.stops(placed, source, evComp = 0.0, now = t)
        }
        return t
    }

    @Test
    fun learnsTheAutoExposurePlacementAndReadsManualAgainstIt() {
        val prefs = mutableMapOf<String, Double>()
        val meter = meter(prefs)
        // Seeded: auto at EV 0 with the I-Log median 1.3 stops under grey reads 0.
        val first = meter.stops(-1.3, ilogA, evComp = null, now = 0.0)
        assertEquals(0.0, first.value!!, 1e-9)
        assertEquals(ObservationOrigin.IMAGE_ESTIMATED, first.origin, "a picture estimate is never camera-reported")
        val t = learn(meter, ilogA, -0.8)
        assertEquals(-0.8, meter.offset(ilogA), 0.01)
        assertEquals(-0.8, prefs.getValue(PictureEVMeter.V2 + ilogA.key), 0.05)
        // Manual, one stop darker than auto chose: reads -1.0; the offset holds.
        assertEquals(-1.0, meter.stops(-1.8, ilogA, evComp = null, now = t + 1).value!!, 0.01)
        assertEquals(-0.8, meter.offset(ilogA), 0.01)
        // Rec.709 has no seed.
        val rec709 = ilogA.copy(transfer = MonitorTransfer.REC709)
        assertEquals(0.4, meter.stops(0.4, rec709, evComp = null, now = t + 2).value!!, 1e-9)
    }

    /** STATE-01 persistence: v1 per-transfer offsets start every new v2 key of that transfer and are never lost. */
    @Test
    fun v1OffsetsSeedNewSourceKeysAndSurviveReruns() {
        val v1 = PictureEVMeter.V1 + MonitorTransfer.ILOG.name
        val prefs = mutableMapOf(v1 to -0.6)
        val meter = meter(prefs)
        assertEquals(-0.6, meter.offset(ilogA), 1e-9, "an existing user's learned I-Log offset carries over")
        assertEquals(-0.6, meter.offset(ilogB), 1e-9, "for every source with that transfer")
        assertEquals(0.0, meter.offset(ilogA.copy(transfer = MonitorTransfer.REC709)), 1e-9, "other transfers keep their own start")
        learn(meter, ilogA, -0.2)
        assertEquals(-0.6, prefs.getValue(v1), 1e-9, "v1 is never rewritten")
        assertEquals(setOf(v1, PictureEVMeter.V2 + ilogA.key), prefs.keys, "only the learned source is written")
        val learned = prefs.getValue(PictureEVMeter.V2 + ilogA.key)
        // Rerun (next launch, new instance on the same preferences), twice: the same values.
        repeat(2) {
            val rerun = meter(prefs)
            assertEquals(learned, rerun.offset(ilogA), 1e-9)
            assertEquals(-0.6, rerun.offset(ilogB), 1e-9)
            rerun.stops(-1.0, ilogA, evComp = null, now = 0.0)
            rerun.stops(-1.0, ilogB, evComp = null, now = 0.0)
        }
        assertEquals(mapOf(v1 to -0.6, PictureEVMeter.V2 + ilogA.key to learned), prefs, "reading never migrates destructively")
    }

    /** Two sources (sessions) in one process share the preferences but not their calibration. */
    @Test
    fun twoSourcesLearnIndependently() {
        val prefs = mutableMapOf<String, Double>()
        val a = meter(prefs)
        val b = meter(prefs)
        val face = ilogB.copy(metering = "face")
        learn(a, ilogA, -0.4)
        learn(b, face, -2.0)
        assertEquals(-0.4, a.offset(ilogA), 0.01)
        assertEquals(-2.0, b.offset(face), 0.01)
        assertEquals(-1.3, b.offset(ilogB), 1e-9, "another metering context keeps its own start")
        // Neither save clobbered the other's key.
        val rerun = meter(prefs)
        assertEquals(-0.4, rerun.offset(ilogA), 0.05)
        assertEquals(-2.0, rerun.offset(face), 0.05)
    }

    @Test
    fun pictureStopsIsTheLumaMedianAgainstGrey() {
        // All pixels at the Rec.709 code for 18% grey read 0 stops; an empty histogram reads nothing.
        val grey = (0..255).minBy { kotlin.math.abs(com.opencapture.openpocketcine.feed.LiveColorScience.stops(it / 255.0, MonitorTransfer.REC709)) }
        val histogram = IntArray(256).also { it[grey] = 100 }
        assertEquals(0.0, com.opencapture.opencine.media.MonitorNDFilterRecommendation.pictureStops(histogram, MonitorTransfer.REC709)!!, 0.1)
        assertEquals(null, com.opencapture.opencine.media.MonitorNDFilterRecommendation.pictureStops(IntArray(256), MonitorTransfer.REC709))
    }
}
