package com.opencapture.openinstacine.monitor

import com.opencapture.opencine.appkit.MonitorActivityConfigChanges
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals

/** A4-26: no configuration change the activity can handle recreates it and drops the session. */
class MonitorActivityManifestTest {
    @Test
    fun everyMonitorActivityHandlesEveryMonitorConfigurationChange() {
        // The Luna launcher, the debug review driver over the same root, and the shared base.
        for ((path, activity) in listOf(
            "../app/src/main/AndroidManifest.xml" to ".MainActivity",
            "../app/src/debug/AndroidManifest.xml" to ".ShellReviewActivity",
            "src/main/AndroidManifest.xml" to ".MainActivity",
        )) {
            assertEquals(emptyList(), MonitorActivityConfigChanges.missingIn(File(path).readText(), activity), "$path $activity")
        }
    }
}
