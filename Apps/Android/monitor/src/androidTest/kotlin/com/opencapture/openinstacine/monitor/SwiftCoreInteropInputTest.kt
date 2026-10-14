package com.opencapture.openinstacine.monitor

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.opencine.media.MonitorTransfer
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.LutCatalog
import com.opencapture.openinstacine.monitor.assists.LiveAssistState
import com.opencapture.openinstacine.monitor.bridge.SwiftCore
import com.opencapture.openinstacine.monitor.feed.FeedEffectsRenderPlanFactory
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** SIMULATED inputs exercise the actual packaged Swift library through legacy and typed JNI bindings. */
@RunWith(AndroidJUnit4::class)
class SwiftCoreInteropInputTest {
    @Test fun liveRenderPlanUsesThePackagedIlogCurveWithoutInventingAnUnknownCurve() {
        assertTrue(SwiftCore.isAvailable)
        val assist = LiveAssistState()
        assist.toggle(MonitorAssistTool.FALSE)
        fun plan(code: Int) = FeedEffectsRenderPlanFactory.create(
            context = InstrumentationRegistry.getInstrumentation().targetContext,
            assist = assist, lutSelection = LutCatalog.OFF, colorMode = code, iso = 100,
            family = "SIMULATED", cameraName = null,
        )
        val log = plan(CameraCommands.COLOR_ILOG)
        assertEquals(MonitorTransfer.ILOG, log.scopeTap.transfer)
        assertEquals(assist.peakingSensitivity.noiseGate.toFloat(), log.peakingNoiseGate)
        assertNotNull(log.falseColorPaint)
        assertNotNull(log.falseColorWeight)
        val unknown = plan(CameraCommands.COLOR_DOLBY_VISION)
        assertNull(unknown.falseColorPaint)
        assertNull(unknown.falseColorWeight)
    }

    @Test fun packagedNamedCurvesKeepIlogAndRefuseUnknownWireValues() {
        assertTrue(SwiftCore.isAvailable, "The actual packaged typed bindings must load")
        val typed = assertNotNull(SwiftCore.feedAssistScalarsForTransfer("ilog", 100, 100f, 55f))
        assertEquals(1f, typed[3])
        assertTrue(typed.contentEquals(assertNotNull(SwiftCore.feedAssistScalars(CameraCommands.COLOR_ILOG, 100, 100f, 55f))))
        assertNull(SwiftCore.feedAssistScalarsForTransfer(null, 100, 100f, 55f))
        assertNull(SwiftCore.feedAssistScalarsForTransfer("65536", 100, 100f, 55f))
        assertNull(SwiftCore.packFalseColorPaintForTransfer(0, null, 100))
        assertNull(SwiftCore.packFalseColorWeightForTransfer(0, "unknown", 100))
        assertNull(SwiftCore.packCreativeLutForTransfer("Warm", 0.0, null))
        assertNull(SwiftCore.packImportedLutForTransfer(ByteArray(0), 0.0, "PQ"))
        assertTrue(assertNotNull(SwiftCore.packFalseColorPaintForTransfer(0, "ilog", 100)).isNotEmpty())
        assertTrue(assertNotNull(SwiftCore.packFalseColorWeightForTransfer(0, "ilog", 100)).isNotEmpty())
        assertTrue(assertNotNull(SwiftCore.packCreativeLutForTransfer("Warm", 0.0, "ilog")).isNotEmpty())
    }

    @Test fun packagedCorePreservesSessionCurveIsolationAndNativeWireResponses() {
        assertTrue(SwiftCore.isAvailable, "The packaged native dependency closure must load")
        assertTrue(SwiftCore.coreVersion().endsWith("/arm64"))
        val code = CameraCommands.COLOR_DLOG2
        fun highlight(iso: Int): Float = assertNotNull(
            SwiftCore.feedAssistScalars(code, iso, 100f, 55f))[0]
        val reference = highlight(1600)
        assertTrue(highlight(800) < reference)
        assertEquals(reference, highlight(1600))
        assertEquals(reference, highlight(0), "Unknown ISO keeps the existing reference calibration")
        val normal = assertNotNull(SwiftCore.feedAssistScalars(CameraCommands.COLOR_NORMAL, 100, 100f, 55f))
        assertEquals(4, normal.size)
        assertEquals(1.57f * 1.57f, normal[3], 0.00001f)
        val paint = assertNotNull(SwiftCore.packFalseColorPaint(3, code, 1600))
        val weight = assertNotNull(SwiftCore.packFalseColorWeight(3, code, 1600))
        assertEquals(paint.size, weight.size)
        assertTrue(paint.size > 256 && paint.size % 4 == 0)
        assertTrue(weight.indices.filter { it % 4 == 0 }.all { (weight[it].toInt() and 255) == 255 })
        assertTrue(assertNotNull(SwiftCore.packCreativeLut("Warm", 0.0, 0)).isNotEmpty())
        assertNull(SwiftCore.packImportedLut("not a cube".toByteArray(), 0.0, 0))
    }
}
