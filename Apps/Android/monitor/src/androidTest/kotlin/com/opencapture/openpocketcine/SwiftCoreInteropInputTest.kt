package com.opencapture.openpocketcine

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.session.CameraCommands
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.json.JSONObject
import org.junit.Test
import org.junit.runner.RunWith

/** SIMULATED inputs exercise the actual packaged Swift library through all eight JNI bindings. */
@RunWith(AndroidJUnit4::class)
class SwiftCoreInteropInputTest {
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
        assertEquals("false", SwiftCore.cameraSoftAPDecision("canSendHandshake",
            """{"receiveArmed":true,"connectionReady":false}"""))
        assertEquals("true", SwiftCore.cameraSoftAPDecision("canSendHandshake",
            """{"receiveArmed":true,"connectionReady":true}"""))
        val conform = JSONObject(assertNotNull(SwiftCore.conformPreviewJSON(
            """{"nominalFrameRate":120,"targetRate":24,"sourceSeconds":10}""")))
        assertEquals(120.0, conform.getDouble("captureRate"))
        assertEquals(50.0, conform.getDouble("conformedDuration"))
    }
}
