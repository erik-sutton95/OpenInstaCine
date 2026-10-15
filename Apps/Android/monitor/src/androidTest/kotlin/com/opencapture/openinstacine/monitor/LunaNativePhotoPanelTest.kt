package com.opencapture.openinstacine.monitor

import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.opencine.cameracontrols.LiveControlSheet
import com.opencapture.opencine.cameracontrols.LiveSheet
import com.opencapture.opencine.insta360.shell.CameraReadout
import com.opencapture.opencine.insta360.shell.CameraRecordFormat
import com.opencapture.opencine.insta360.shell.CameraShootingMode
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** SIMULATED actual app host and shared drawer; retained video facts must not replace Photo. */
@RunWith(AndroidJUnit4::class)
class LunaNativePhotoPanelTest {
    @Test fun photoKeepsOriginalFormatFallbackWithRetainedVideoFacts() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val backend = FakeShellBackend().apply {
            readout.value = CameraReadout(shootingMode = CameraShootingMode.PHOTO, recording = false,
                recordFormat = CameraRecordFormat(48,3840,2160,25.0),
                recordFormats = listOf(CameraRecordFormat(48,3840,2160,25.0)))
        }
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            var model: AppModel? = null
            try {
                MonitorConfiguration.install(MonitorConfiguration.identity) { backend }
                try { scenario.onActivity { model = AppModel(it) } }
                finally {
                    MonitorConfiguration.install(MonitorConfiguration.identity) { context ->
                        val wifi = com.opencapture.openinstacine.monitor.pairing.CameraWifiCredentialStore(context)
                        com.opencapture.opencine.insta360.luna.LunaBackend(context,
                            savedWifi = wifi::load, saveWifi = wifi::save, forgetWifi = wifi::remove)
                    }
                }
                assertTrue("The real facade must report Photo before mounting", waitUntil { checkNotNull(model).session.status.value.isPhoto })
                scenario.onActivity {
                    val host = checkNotNull(model)
                    val status = host.session.status.value
                    assertNull("Photo has no native format quick choice", host.nativeCaptureQuick(LiveSheet.FORMAT, status))
                    assertNull("Photo has no native colour quick choice", host.nativeCaptureQuick(LiveSheet.COLOR, status))
                }
                val drawn = CountDownLatch(1)
                scenario.onActivity { activity -> activity.setContent {
                    OpenPocketCineTheme {
                        val status by checkNotNull(model).session.status.collectAsState()
                        Box(Modifier.fillMaxSize().semantics { contentDescription = "SIMULATED photo drawer" }) {
                            LiveControlSheet(LiveSheet.FORMAT, checkNotNull(model), status,
                                locked = false, onDismiss = {}, portrait = false)
                            LaunchedEffect(Unit) { withFrameNanos { }; withFrameNanos { }; drawn.countDown() }
                        }
                    }
                } }
                assertTrue("The native drawer must render", drawn.await(10,TimeUnit.SECONDS))
                instrumentation.waitForIdleSync()
                fun currentHost(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
                    if (node.contentDescription?.toString() == "SIMULATED photo drawer") return node
                    for (index in 0 until node.childCount) node.getChild(index)?.let { currentHost(it)?.let { return it } }
                    return null
                }
                val publicationDeadline = android.os.SystemClock.uptimeMillis() + 5_000
                var published: AccessibilityNodeInfo? = null
                while (published == null && android.os.SystemClock.uptimeMillis() < publicationDeadline) {
                    instrumentation.waitForIdleSync()
                    published = instrumentation.uiAutomation.rootInActiveWindow?.let(::currentHost)
                }
                val root = checkNotNull(published) { "Current SIMULATED photo drawer was not published to native accessibility" }
                fun text(node: AccessibilityNodeInfo): List<String> =
                    listOfNotNull(node.text?.toString(),node.contentDescription?.toString(),node.stateDescription?.toString()) +
                        (0 until node.childCount).flatMap { node.getChild(it)?.let(::text).orEmpty() }
                val values = text(root)
                assertTrue("Photo must retain the existing shared fallback: $values", "Photo" in values)
                assertFalse("A retained video format must not become the Photo drawer: $values", values.any { "4K" in it || "25p" in it })
                assertTrue("Rendering this read-only fixture sends no native format command", backend.calls("setRecordFormat").isEmpty())
            } finally { scenario.onActivity { model?.close() } }
        }
    }
}
