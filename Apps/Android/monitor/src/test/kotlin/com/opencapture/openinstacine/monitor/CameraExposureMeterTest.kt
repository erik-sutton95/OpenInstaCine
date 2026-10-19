package com.opencapture.openinstacine.monitor

import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.openinstacine.monitor.assists.LiveAssistState
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.opencine.cameracontrols.MonitorOperatorExposureReading
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import com.opencapture.opencine.cameracontrols.CleanPinTool
import com.opencapture.opencine.appkit.renderPlan

class CameraExposureMeterTest {
    /** IA-153 / IA-246: the Luna meters no EV, so the live screen reads it from the picture (main, iOS). */
    @Test fun aCameraWithoutMeteredEvReadsThePicture() {
        val assist = LiveAssistState()
        if (!assist.isOn(MonitorAssistTool.EV)) assist.toggle(MonitorAssistTool.EV)
        assist.followMeteredEvSource(reportsMeteredEV = false)
        assertTrue(assist.evMeterFromPicture)
        assertTrue(assist.renderPlan(com.opencapture.opencine.media.MonitorTransfer.REC709).scopeTap.evMeter, "the picture tap feeds the meter")
        assist.followMeteredEvSource(reportsMeteredEV = true)
        assertFalse(assist.evMeterFromPicture, "a camera that meters keeps its own value")
    }

    @Test fun reportedMeterLabelsStayIndependentOfConfiguredCompensation() {
        assertEquals("−0.7", MonitorOperatorExposureReading(0x0E).label)
        assertEquals("−0.7", MonitorOperatorExposureReading(CameraStatus(evComp = 0x19, meteredEv = 0x0E).meteredEv).label)
        assertEquals("−3.0", MonitorOperatorExposureReading(CameraStatus(evComp = 0x19, meteredEv = 0x07).meteredEv).label)
    }

    @Test fun everyValidRawMeterStepMapsToThirdStopsAndTheVerticalNeedle() {
        for (raw in 0x07..0x19) {
            val meter = MonitorOperatorExposureReading(raw)
            assertEquals((raw - 16) / 3.0, meter.stops)
            assertEquals((25 - raw) / 18f, meter.needleFraction)
        }
        assertEquals("−3.0", MonitorOperatorExposureReading(0x07).label)
        assertEquals("0.0", MonitorOperatorExposureReading(0x10).label)
        assertEquals("+3.0", MonitorOperatorExposureReading(0x19).label)
    }

    @Test fun activeRecoveryHidesRetainedTelemetryButFreshMeterDoesNotRequireAPicture() {
        val recovering = MonitorOperatorExposureReading(0x19, available = false)
        assertEquals("—", recovering.label)
        assertNull(recovering.needleFraction)
        assertNull(recovering.stops)
        assertEquals("Camera exposure meter, unavailable", recovering.accessibilityLabel)
        // Availability depends on camera telemetry and recovery, with no decoder-picture input.
        val fresh = MonitorOperatorExposureReading(0x19)
        assertEquals("+3.0", fresh.label)
        assertEquals(0f, fresh.needleFraction)
    }

    @Test fun unavailableAndMalformedTelemetryNeverBorrowConfiguredEVOrRetainTheLastMeter() {
        for (raw in listOf(-1, 0, 6, 26, 255, Int.MIN_VALUE, Int.MAX_VALUE)) {
            val meter = MonitorOperatorExposureReading(raw)
            assertNull(meter.stops)
            assertNull(meter.needleFraction)
            assertEquals("—", meter.label)
            assertEquals("Camera exposure meter, unavailable", meter.accessibilityLabel)
        }
        assertEquals("\u2014", MonitorOperatorExposureReading(CameraStatus(evComp = 0x10).meteredEv).label)
    }

    @Test fun fixedGaugeUsesFeedLeftEdgeAndUpwardPreferredCenterInDispOneOnly() {
        for (feed in listOf(ChromeRect(80f, 200f, 300f, 300f), ChromeRect(170f, 30f, 600f, 320f))) {
            val frame = MonitorOperatorExposureReading.frame(feed, PocketDispMode.LIVE)!!
            assertEquals(feed.minX + 6f, frame.minX)
            assertEquals(feed.midY - 16f, frame.midY)
            assertEquals(28f, frame.width)
            assertEquals(180f, frame.height)
            assertNull(MonitorOperatorExposureReading.frame(feed, PocketDispMode.CLEAN))
        }
        val shortFeed = ChromeRect(40f, 25f, 200f, 100f)
        val short = MonitorOperatorExposureReading.frame(shortFeed, PocketDispMode.LIVE)!!
        assertEquals(88f, short.height)
        assertEquals(shortFeed.minY + 6f, short.minY)
        assertEquals(shortFeed.maxY - 6f, short.maxY)
        assertNull(MonitorOperatorExposureReading.frame(ChromeRect(0f, 0f, 39f, 180f), PocketDispMode.LIVE))
        assertNull(MonitorOperatorExposureReading.frame(ChromeRect(0f, 0f, 100f, 83f), PocketDispMode.LIVE))
        val minimum = MonitorOperatorExposureReading.frame(ChromeRect(0f, 0f, 40f, 84f), PocketDispMode.LIVE)!!
        assertEquals(28f, minimum.width)
        assertEquals(72f, minimum.height)
    }

    @Test fun gaugeMovesAboveCollapsedPaletteBeforeShorteningItsScale() {
        val feed = ChromeRect(20f, 40f, 500f, 300f)
        val palette = ChromeRect(22f, 240f, 54f, 100f)
        val normal = MonitorOperatorExposureReading.frame(feed, PocketDispMode.LIVE)!!
        val above = MonitorOperatorExposureReading.frame(feed, PocketDispMode.LIVE, palette)!!
        assertEquals(180f, above.height)
        assertEquals(normal.minX, above.minX)
        assertEquals(28f, above.width)
        assertEquals(palette.minY - 12f, above.maxY)
        assertFalse(above.intersects(palette))
        assertTrue(above.midY < normal.midY)
        // A toolbar beside or far below the preferred gauge does not move it.
        assertEquals(normal, MonitorOperatorExposureReading.frame(feed, PocketDispMode.LIVE, palette.copy(x = 100f)))
        assertEquals(normal, MonitorOperatorExposureReading.frame(feed, PocketDispMode.LIVE, palette.copy(y = 400f)))
        val limited = MonitorOperatorExposureReading.frame(feed, PocketDispMode.LIVE, palette.copy(y = 220f))!!
        assertEquals(162f, limited.height)
        assertEquals(feed.minY + 6f, limited.minY)
        assertEquals(208f, limited.maxY)
    }

    @Test fun gaugeUsesBelowIntervalWhenExpandedPaletteLeavesNoRoomAbove() {
        val feed = ChromeRect(20f, 40f, 500f, 400f)
        val expanded = ChromeRect(22f, 50f, 54f, 180f)
        val below = MonitorOperatorExposureReading.frame(feed, PocketDispMode.LIVE, expanded)!!
        assertEquals(180f, below.height)
        assertEquals(expanded.maxY + 12f, below.minY)
        assertFalse(below.intersects(expanded))
        assertTrue(below.maxY <= feed.maxY - 6f)
    }

    @Test fun gaugeHidesWhenExpandedPaletteLeavesNeitherIntervalTallEnough() {
        val feed = ChromeRect(20f, 40f, 500f, 400f)
        val expanded = ChromeRect(22f, 80f, 54f, 300f)
        assertNull(MonitorOperatorExposureReading.frame(feed, PocketDispMode.LIVE, expanded))
        val exactMinimum = ChromeRect(22f, 130f, 54f, 300f)
        val minimum = MonitorOperatorExposureReading.frame(feed, PocketDispMode.LIVE, exactMinimum)!!
        assertEquals(72f, minimum.height)
        assertEquals(exactMinimum.minY - 12f, minimum.maxY)
        assertFalse(minimum.intersects(exactMinimum))
    }

    @Test fun evTogglePersistsButDisplaysOnlyInDispOneAndDoesNotJoinImageAnalysis() {
        var saved: String? = null
        val state = LiveAssistState(encoded = """{"tools":[]}""", onPersist = { saved = it })
        assertFalse(state.evMeter)
        state.toggle(MonitorAssistTool.EV)
        assertTrue(state.evMeter)
        assertTrue(state.isVisible(MonitorAssistTool.EV))
        val restored = LiveAssistState(encoded = saved)
        assertTrue(restored.evMeter)
        restored.clean = true
        assertFalse(restored.isVisible(MonitorAssistTool.EV))
        restored.togglePin(MonitorAssistTool.EV)
        assertFalse(restored.isVisible(MonitorAssistTool.EV))
        restored.clean = false
        assertTrue(restored.isVisible(MonitorAssistTool.EV))
        assertFalse(MonitorAssistTool.EV in state.scopeStack)
        assertFalse(MonitorAssistTool.EV in LiveAssistState.stackableScopeTools)
        assertFalse(MonitorAssistTool.EV in LiveAssistState.processedPlaybackTools)
        assertFalse(MonitorAssistTool.EV in LiveAssistState.lookOverlayTools)
        assertNull(state.inspectorScopeDemand)
        state.toggle(MonitorAssistTool.EV)
        assertFalse(LiveAssistState(encoded = saved).evMeter)
    }

    @Test fun legacyEvGeometryPinsAndPlaybackAreIgnoredWhileTheLiveToggleIsRestored() {
        val state = LiveAssistState(
            encoded = """{"tools":["EV"],"evScale":1.5,"evCenter":{"xFraction":0.8,"yFraction":0.1},"scopeStack":["EV"]}""",
            pinnedNames = setOf("EV"),
            playbackNames = setOf("EV"),
        )
        assertEquals(MonitorAssistTool.EV, MonitorAssistTool.fromPersisted("EV"))
        assertTrue(state.evMeter)
        assertTrue(state.pinned.isEmpty())
        assertTrue(state.playbackVisibleTools.isEmpty())
        state.togglePlayback(MonitorAssistTool.EV)
        assertTrue(state.playbackVisibleTools.isEmpty())
        assertTrue(MonitorAssistTool.EV in MonitorAssistTool.toolbarCases)
        assertTrue(MonitorAssistTool.EV in MonitorAssistTool.settingsCases)
        assertFalse(MonitorAssistTool.EV in MonitorAssistTool.cleanPinCases)
        assertFalse(MonitorAssistTool.EV in MonitorAssistTool.playbackToolbarCases)
        assertFalse(state.encoded().contains("evScale"))
        assertFalse(state.encoded().contains("evCenter"))
        assertFalse(CleanPinTool.entries.any { it.key == "EV" })
    }
}
