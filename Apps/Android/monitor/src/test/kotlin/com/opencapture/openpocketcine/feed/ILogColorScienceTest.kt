package com.opencapture.openpocketcine.feed

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ILogColorScienceTest {
    @Test
    fun paperAnchorsAndUnclampedMathematicalDomain() {
        assertEquals(0.09055934, ILog.encode(0.0), 1e-10)
        assertEquals(0.4220033397, ILog.encode(0.18), 1e-10)
        assertEquals(0.6252022223, ILog.encode(1.0), 1e-10)
        assertEquals(0.9999994560, ILog.encode(22.0), 1e-10)
        assertEquals(22.00009844, ILog.decode(1.0), 1e-7)
        assertTrue(ILog.decode(0.0) < 0.0)
        assertTrue(ILog.encode(30.0) > 1.0)
    }

    @Test
    fun piecewiseBoundariesUsePublishedRoundedCoefficients() {
        assertEquals(0.15440192831901123, ILog.encode(0.01104854), 1e-13)
        assertEquals(0.0110485524, ILog.decode(0.154402), 1e-9)
        for (value in listOf(0.0, 0.005, 0.01104854, 0.0110486, 0.18, 1.0, 22.0)) {
            assertEquals(value, ILog.decode(ILog.encode(value)), 1e-8, "scene reflectance $value")
        }
    }

    @Test
    fun neutralBridgeIdNeverMasqueradesAsACameraWireByte() {
        assertEquals(65_536, MonitorTransfer.ILOG.colorMode)
        assertEquals(MonitorTransfer.ILOG, MonitorTransfer.fromColorMode(65_536))
        assertEquals(MonitorTransfer.REC709, MonitorTransfer.fromColorMode(-1))
        assertEquals(MonitorTransfer.REC709, MonitorTransfer.fromColorMode(65_537))
    }

    @Test
    fun sourceMeteringUsesBt2020AndNoDjiEiCalibration() {
        assertEquals(Triple(0.2627, 0.6780, 0.0593), LiveColorScience.lumaWeights(MonitorTransfer.ILOG))
        assertEquals(0.0, LiveColorScience.stops(ILog.encode(0.18), MonitorTransfer.ILOG), 1e-12)
        assertEquals(42.20033397, MonitorTransfer.ILOG.middleGrayPaperIRE, 1e-8)
        for (iso in listOf(100, 400, 800, 1600, 6400)) {
            assertEquals(255, ScopeExposureCeiling.clipByte(MonitorTransfer.ILOG, iso))
        }
    }
}
