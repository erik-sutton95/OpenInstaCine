package com.opencapture.openinstacine.monitor.feed

import com.opencapture.openinstacine.monitor.BuildConfig
import kotlin.test.Test
import kotlin.test.assertEquals

class AppVulkanCrashGuardTest {
    @Test
    fun holderUsesThisAppsPreferencesAndVersion() {
        assertEquals("openpocketcine.vulkan_guard", appVulkanCrashGuard.preferencesName)
        assertEquals(BuildConfig.VERSION_CODE, appVulkanCrashGuard.versionCode)
    }
}
