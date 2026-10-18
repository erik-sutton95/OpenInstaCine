package com.opencapture.openinstacine.monitor.media

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals

/** The gallery, its player and photo pages and their Back order come from the one shared media host (A4-13). */
class MediaHostRuleTest {
    private val sources: Map<String, String> = File("src/main/kotlin").walkTopDown()
        .filter { it.isFile && it.name.endsWith(".kt") }.associate { it.name to it.readText() }

    private fun filesUsing(token: String): List<String> = sources.filterValues { token in it }.keys.sorted()

    @Test
    fun theSharedHostOwnsTheGalleryAndItsBackOrder() {
        assertEquals(emptyList(), filesUsing("MonitorOperatorCatalogScreen("))
        assertEquals(listOf("MediaLibraryScreen.kt"), filesUsing("MonitorOperatorMediaScreen("))
        assertEquals(false, "BackHandler" in sources.getValue("MediaLibraryScreen.kt"))
    }
}
