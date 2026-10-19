package com.opencapture.openinstacine.monitor.media

import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * IA-552: the media cache lives under noBackupFilesDir, which FileProvider cannot name, so the
 * shared MediaShare stages share copies in cacheDir/share/ready and the provider must name them.
 */
class MediaShareProviderPathsTest {
    @Test fun providerPathsCoverTheShareCopies() {
        val paths = File("src/main/res/xml/opc_media_file_paths.xml").readText()
        assertTrue(Regex("""<cache-path\s+name="[^"]+"\s+path="share/ready/"\s*/>""").containsMatchIn(paths))
    }
}
