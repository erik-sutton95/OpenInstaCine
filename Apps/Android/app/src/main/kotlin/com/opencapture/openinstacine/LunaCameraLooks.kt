package com.opencapture.openinstacine

import com.opencapture.openinstacine.monitor.session.LunaCameraLUTProfile

/** Installed compatibility catalogue and per-source profile share one adapter-owned definition. */
internal object LunaCameraLooks {
    val entries = LunaCameraLUTProfile.value.cameraLooks
}
