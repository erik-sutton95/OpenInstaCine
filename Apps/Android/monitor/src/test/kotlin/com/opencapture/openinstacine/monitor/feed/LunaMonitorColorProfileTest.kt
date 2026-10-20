package com.opencapture.openinstacine.monitor.feed

import com.opencapture.opencine.insta360.shell.LunaScopeClip
import com.opencapture.opencine.media.MonitorTransfer
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class LunaMonitorColorProfileTest {
    @Test fun actualLunaSourceHasOnlyItsIlogLookAndIlogClipAndNoDjiPreviewCalibration() {
        val source = LunaMonitorColorProfile.value
        assertEquals(LunaScopeClip.PROFILE, source.clip)
        assertEquals(setOf(MonitorTransfer.ILOG), source.clip.calibrations.keys)
        assertEquals(setOf(MonitorTransfer.ILOG), source.rec709LookCurves.keys)
        assertEquals(33, source.rec709LookCurves[MonitorTransfer.ILOG]?.size)
        // Luna reports ISO 0 in Auto; until a report the ceiling assumes the lowest ISO.
        assertEquals(100, LunaScopeExposureCeiling().resolvedISO())
        val ceiling = LunaScopeExposureCeiling()
        assertEquals(205, ceiling.clipByte(MonitorTransfer.ILOG, 100))
        assertEquals(248, ceiling.clipByte(MonitorTransfer.ILOG, 400))
        assertEquals(255, ceiling.clipByte(MonitorTransfer.REC709, 100))
        assertFalse(source.rec709LookCurves.containsKey(MonitorTransfer.DLOG2))
    }
}
