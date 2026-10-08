package com.opencapture.openinstacine.monitor.session

import com.opencapture.opencine.media.MonitorTransfer
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraLUTProfile
import com.opencapture.opencine.vocabulary.LutCategory
import com.opencapture.opencine.vocabulary.LutEntry
import com.opencapture.opencine.vocabulary.LutLookSource

/** The camera adapter declares only the official cube actually shipped by this integration. */
object LunaCameraLUTProfile {
    private val iLog = LutLookSource.Asset("Luna_I-Log_to_Rec709_BT1886_s33_v2.cube",
        MonitorTransfer.ILOG, "I-Log → Rec.709")
    val value = CameraLUTProfile(automatic = mapOf(CameraCommands.COLOR_ILOG to iLog),
        selections = mapOf("lunaILog" to iLog), cameraLooks = listOf(
            LutEntry(id = "camera:insta360-luna-ilog-rec709-v2", title = "I-Log → Rec.709",
                category = LutCategory.CAMERA, fileName = iLog.fileName, inputTransfer = MonitorTransfer.ILOG,
                caption = "Manual conversion · source must be I-Log")))
}
