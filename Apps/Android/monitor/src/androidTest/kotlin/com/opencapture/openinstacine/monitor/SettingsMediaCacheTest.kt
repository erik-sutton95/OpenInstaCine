package com.opencapture.openinstacine.monitor

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.os.SystemClock
import androidx.activity.compose.setContent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.opencine.appkit.MonitorSettingsCacheModel
import com.opencapture.opencine.appkit.MonitorSettingsCacheSource
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.test.assertEquals
import kotlin.test.assertFalse

/**
 * Settings > Storage reads and clears the cache the gallery writes (A4-05: it counted and cleared
 * `filesDir/OpenInstaCine/media` while the gallery wrote `noBackupFilesDir/OpenPocketCine/media`).
 * SIMULATED cache bytes in an isolated context; the actual app model, settings composition and the
 * shared settings cache owner.
 */
@RunWith(AndroidJUnit4::class)
class SettingsMediaCacheTest {
    @Before fun installActualBackend() {
        MonitorConfiguration.install(MonitorConfiguration.identity) { context ->
            val wifi = com.opencapture.opencine.platform.CameraWifiCredentialStore(context, com.opencapture.openinstacine.monitor.pairing.cameraWifiStorage)
            com.opencapture.opencine.insta360.luna.LunaBackend(context,
                savedWifi = wifi::load, saveWifi = wifi::save, forgetWifi = wifi::remove)
        }
    }

    @Test fun settingsCountAndClearTheGalleryCache() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val base = instrumentation.targetContext.applicationContext
        val domain = "settings-cache." + UUID.randomUUID()
        val root = File(base.cacheDir, domain)
        val domains = mutableSetOf<String>()
        val context = object : ContextWrapper(base) {
            override fun getApplicationContext(): Context = this
            override fun getNoBackupFilesDir(): File = File(root, "no-backup")
            override fun getFilesDir(): File = File(root, "files")
            override fun getCacheDir(): File = File(root, "cache")
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences {
                val key = "$domain.$name"; domains += key
                return base.getSharedPreferences(key, mode)
            }
        }
        // What the gallery wrote for camera "fixture": one original and its clip list.
        val gallery = File(context.noBackupFilesDir, "OpenPocketCine/media/fixture")
        val original = File(gallery, "files/VID_20261003_140001_00_001.mp4").apply { parentFile!!.mkdirs(); writeBytes(ByteArray(4_096) { 7 }) }
        val catalog = File(gallery, "index.json").apply { writeText("[]") }
        val written = original.length() + catalog.length()
        context.getSharedPreferences("openpocketcine.media", Context.MODE_PRIVATE).edit()
            .putString("opc.media.lastCameraID", "fixture").commit()
        var model: AppModel? = null
        try {
            ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
                var source: MonitorSettingsCacheSource? = null
                scenario.onActivity { activity ->
                    model = AppModel(context)
                    val app = operatorSetupApp(model!!)
                    activity.setContent { source = requireNotNull(app.cacheSource)(context) }
                }
                // Composition runs on the next frame; wait for it.
                val deadline = SystemClock.uptimeMillis() + 5_000
                while (source == null && SystemClock.uptimeMillis() < deadline) {
                    instrumentation.waitForIdleSync(); SystemClock.sleep(50)
                }
                val captured = requireNotNull(source) { "Settings composed no cache source" }
                runBlocking(Dispatchers.Main) {
                    val settings = MonitorSettingsCacheModel(this)
                    settings.refresh(captured)
                    val counted = withTimeout(10_000) { settings.state.first { it.bytes != null || it.readFailed } }
                    assertEquals(written, counted.bytes, "Settings must count the bytes the gallery wrote")
                    settings.requestClear()
                    settings.clear()
                    withTimeout(10_000) { settings.state.first { !it.clearing } }
                    settings.retire()
                }
                assertFalse(original.exists(), "Clear cache must remove the gallery's originals")
                assertFalse(catalog.exists(), "The all-camera Settings clear removes the camera index")
            }
        } finally {
            instrumentation.runOnMainSync { model?.close() }
            domains.forEach { base.deleteSharedPreferences(it) }
            root.deleteRecursively()
        }
    }
}
