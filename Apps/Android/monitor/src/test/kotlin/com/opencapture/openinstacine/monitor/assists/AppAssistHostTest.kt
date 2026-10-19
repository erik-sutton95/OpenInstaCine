package com.opencapture.openinstacine.monitor.assists

import com.opencapture.monitorui.MonitorGuideMaskPolicy
import kotlin.test.Test
import kotlin.test.assertEquals

class AppAssistHostTest {
    /**
     * IA-251: with two or more frame guides, "Mask outside frame" keeps their bounding rectangle
     * clear, as this app's baseline and Pocket do, so the corners between crossing frames stay lit.
     */
    @Test
    fun `guide mask keeps the envelope of the selected frames clear`() {
        assertEquals(MonitorGuideMaskPolicy.ENVELOPE, AppAssistHost.guideMaskPolicy)
    }
}
