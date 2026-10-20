package com.opencapture.openinstacine.monitor.feed

import com.opencapture.opencine.insta360.shell.LunaScopeClip
import com.opencapture.opencine.media.MonitorColorSourceProfile
import com.opencapture.opencine.media.MonitorTransfer

/** Luna's bundled I-Log look and the shared Luna I-Log clip per ISO ([LunaScopeClip], derived, awaiting a hardware measurement). */
object LunaMonitorColorProfile {
    val value = MonitorColorSourceProfile(clip = LunaScopeClip.PROFILE, rec709LookCurves = mapOf(
        MonitorTransfer.ILOG to listOf(
        0.0011, 0.0011, 0.0011, 0.0050, 0.0291, 0.0509, 0.0733, 0.0996, 0.1309, 0.1673,
        0.2093, 0.2563, 0.3080, 0.3636, 0.4216, 0.4813, 0.5402, 0.5974, 0.6525, 0.7045,
        0.7530, 0.7982, 0.8388, 0.8751, 0.9065, 0.9325, 0.9528, 0.9680, 0.9791, 0.9871,
        0.9918, 0.9958, 0.9994,

        ),
    ))
}

class LunaScopeExposureCeiling : com.opencapture.opencine.media.ScopeExposureCeiling(PROFILE) {
    companion object {
        val PROFILE = LunaMonitorColorProfile.value.clip
        val UNOBSERVED get() = LunaScopeExposureCeiling()
        const val CLIP_SHELF_CODES = com.opencapture.opencine.media.ScopeExposureCeiling.CLIP_SHELF_CODES
    }
}
