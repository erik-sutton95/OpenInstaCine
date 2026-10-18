package com.opencapture.openinstacine.monitor.media

import android.content.SharedPreferences
import com.opencapture.opencine.appkit.MonitorMediaCacheStorage
import kotlinx.coroutines.test.runTest
import java.lang.reflect.Proxy
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

/** The shot color map shares the library directory's generation: a clear is never answered from memory. */
class LunaShotColorFenceTest {
    private val preferences = Proxy.newProxyInstance(SharedPreferences::class.java.classLoader,
        arrayOf(SharedPreferences::class.java)) { _, method, _ ->
        throw AssertionError("Unexpected preferences access: ${method.name}")
    } as SharedPreferences

    @Test fun clearedColorIsNotServedFromMemoryOrResurrectedByTheNextWrite() = runTest {
        val parent = Files.createTempDirectory("luna-color-fence-").toFile()
        try {
            val storage = MonitorMediaCacheStorage()
            val cache = MediaCache(parent, preferences, storage)
            val directory = storage.directory(cache.cacheRoot("camera"))
            cache.rememberShotColor("take", 65, "camera")
            assertEquals(65, cache.shotColor("take", "camera"))
            // A clear that does not keep color.json (Pocket's settings clear, iOS full clear).
            directory.clear(preserving = listOf("index.json"))
            assertEquals(-1, cache.shotColor("take", "camera"))
            cache.rememberShotColor("successor", 3, "camera")
            assertEquals(-1, cache.shotColor("take", "camera"))
            assertEquals(3, cache.shotColor("successor", "camera"))
            assertFalse("take" in directory.read("color.json").toString(Charsets.UTF_8))
        } finally { parent.deleteRecursively() }
    }
}
