package com.opencapture.openinstacine.monitor.feed

import com.opencapture.opencine.media.MonitorTransfer
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LunaMonitorColorProfileTest {
    @Test fun actualLunaSourceHasOnlyItsIlogLookAndNoDjiPreviewCalibration() {
        val source = LunaMonitorColorProfile.value
        assertTrue(source.clip.calibrations.isEmpty())
        assertNull(source.clip.defaultIso)
        assertEquals(setOf(MonitorTransfer.ILOG), source.rec709LookCurves.keys)
        assertEquals(33, source.rec709LookCurves[MonitorTransfer.ILOG]?.size)
        assertNull(LunaScopeExposureCeiling().resolvedISO())
        assertFalse(source.rec709LookCurves.containsKey(MonitorTransfer.DLOG2))
    }
}
