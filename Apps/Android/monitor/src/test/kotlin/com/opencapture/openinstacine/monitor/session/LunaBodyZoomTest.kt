package com.opencapture.openinstacine.monitor.session

import com.opencapture.monitorui.MonitorZoomCaption
import com.opencapture.opencine.insta360.luna.LunaModel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals

/**
 * The zoom a connected Luna body offers (Swift `LunaBodyZoomTests`): a Luna Pro has no 3x telephoto,
 * so it gets no 3x chip, no tele mark and no TELE caption, and stops at 4x; the Luna Ultra keeps
 * exactly what it had.
 */
class LunaBodyZoomTest {
    private fun stops(body: LunaModel?) = PocketCameraSession.lunaZoomStops(body, body?.maximumZoom ?: LunaModel.ULTRA.maximumZoom)

    @Test fun theLunaUltraKeepsItsTelephotoZoom() {
        val stops = stops(LunaModel.ULTRA)
        assertEquals(listOf(1.0, 2.0, 3.0, 6.0, 15.0), stops)
        assertEquals(stops, stops(null), "an unidentified body keeps the Ultra's chips, as before the Pro")
        val optical = PocketCameraSession.opticalZoomStops(LunaModel.ULTRA, stops)
        assertEquals(listOf(1.0, 3.0), optical)
        assertEquals(optical, PocketCameraSession.opticalZoomStops(null, stops))
        assertEquals("TELE", MonitorZoomCaption.label(3.0, optical))
    }

    @Test fun theLunaProHidesTelephotoOnlyZoom() {
        val stops = stops(LunaModel.PRO)
        assertEquals(listOf(1.0, 2.0, 4.0), stops)
        assertFalse(3.0 in stops, "no 3x lens chip")
        val optical = PocketCameraSession.opticalZoomStops(LunaModel.PRO, stops)
        assertEquals(listOf(1.0), optical, "no tele mark on the zoom dial")
        for (factor in listOf(2.0, 3.0, 4.0)) assertNotEquals("TELE", MonitorZoomCaption.label(factor, optical))
        assertEquals("DIGITAL CROP", MonitorZoomCaption.label(3.0, optical))
    }
}
