package com.opencapture.openinstacine

import com.opencapture.openpocketcine.feed.MonitorTransfer
import com.opencapture.openpocketcine.lut.LutCategory
import com.opencapture.openpocketcine.lut.LutEntry

/** Official SDR conversion supplied by the brand; shared monitor contains no camera catalog. */
internal object LunaCameraLooks {
    val entries = listOf(
        LutEntry(
            id = "camera:insta360-luna-ilog-rec709-v2",
            title = "I-Log → Rec.709",
            category = LutCategory.DJI,
            fileName = "Luna_I-Log_to_Rec709_BT1886_s33_v2.cube",
            inputTransfer = MonitorTransfer.ILOG,
            caption = "Manual conversion · source must be I-Log",
        ),
    )
}
