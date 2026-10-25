package com.opencapture.openinstacine.monitor.assists

import com.opencapture.monitorui.MonitorGuideMaskPolicy
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class AppAssistHostTest {
    /**
     * IA-251: with two or more frame guides, "Mask outside frame" keeps their bounding rectangle
     * clear, as this app's baseline and Pocket do, so the corners between crossing frames stay lit.
     */
    @Test
    fun `guide mask keeps the envelope of the selected frames clear`() {
        assertEquals(MonitorGuideMaskPolicy.ENVELOPE, AppAssistHost.guideMaskPolicy)
    }

    /** Owner style rule: operator help copy never uses the em dash (hardware pass 2026-10-24). */
    @Test
    fun `ND help copy never uses the em dash`() {
        assertFalse('\u2014' in ND_HELP, ND_HELP)
        assertEquals(ND_HELP, AppAssistHost.ndHelp)
    }
}
