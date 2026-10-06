package com.opencapture.openinstacine.monitor

import android.graphics.Rect
import android.os.SystemClock
import android.view.MotionEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.monitorui.MonitorPlaybackScrubber
import com.opencapture.monitorui.MonitorEditingCancellation
import com.opencapture.opencine.appkit.*
import com.opencapture.opencine.core.MonotonicInstant
import com.opencapture.opencine.media.*
import java.io.File
import java.net.URI
import java.util.UUID
import kotlinx.coroutines.*
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.test.*
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/** SIMULATED native port, actual playback/cache owners and native Compose pointer cancellation. */
@RunWith(AndroidJUnit4::class)
class LunaPlaybackScrubCancellationInputTest {
    @Test fun nativePointerCancelEndsOnlyAdmittedScrubAndResumesWithoutFinalSeek() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val root = File(instrumentation.targetContext.cacheDir, "scrub-owner-" + UUID.randomUUID())
        val port = Port()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        var library: MonitorMediaLibraryModel<String>? = null
        var playback: MonitorMediaPlaybackModel<String, String>? = null
        val record = MonitorMediaRecord(MediaAsset(MediaAssetID("fixture-A"), filename = "A.mp4", kind = MediaAssetKind.VIDEO,
            durationSeconds = 100.0, representations = emptyList()), "A",
            MonitorMediaCacheAddress("A.jpg", emptyMap(), "A"))
        try {
            ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
                scenario.onActivity { activity ->
                    val codec = object : MonitorMediaCatalogCodec<String> {
                        override fun decode(bytes: ByteArray) = listOf(record)
                        override fun encode(records: List<MonitorMediaRecord<String>>) = "[]".toByteArray()
                        override fun capture(asset: MediaAsset, binding: MediaBrowseBinding): MonitorMediaRecord<String> = error("No camera service")
                    }
                    val cache = MonitorMediaCache(MonitorMediaCacheDirectory(root), codec, MonitorMediaOriginalEligibility.ExactSize,
                        "index.json", listOf("index.json"))
                    cache.directory.write("[]".toByteArray(), "index.json")
                    library = MonitorMediaLibraryModel(cache, object : MonitorMediaFavoritesStore {
                        override fun favorites() = emptySet<String>()
                        override fun saveFavorites(keys: Set<String>) {}
                    }, scope = scope).also { it.begin() }
                    val owner = MonitorMediaPlaybackModel<String, String>(library!!, port, scope,
                        candidates = { listOf(MonitorPlaybackCandidate.Cached(MonitorPlaybackItem(URI("file:/fixture-A.mp4"), "video/mp4", "A"))) },
                        now = { MonotonicInstant(100.seconds) })
                    playback = owner
                    owner.load(record, listOf(record))
                    activity.setContent {
                        val state by owner.state.collectAsState()
                        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center) {
                            MonitorPlaybackScrubber(state.scrubPosition.toFloat(), 100f, state.token,
                                begin = { item -> if (owner.state.value.token == item) owner.beginScrub() else null },
                                update = { edit, time -> owner.updateScrub(time, edit) },
                                commit = { edit, time -> owner.updateScrub(time, edit); owner.commitScrub(edit) },
                                cancel = { edit, reason -> owner.cancelScrub(reason == MonitorEditingCancellation.INTERRUPTED, edit) },
                                modifier = Modifier.width(280.dp))
                        }
                    }
                }
                await { playback!!.state.value.ready && port.plays == 1 }
                val item = playback!!.state.value.token
                val track = bounds("Playback position")
                val x = track.left + track.width() * .25f; val y = track.centerY().toFloat()
                val down = SystemClock.uptimeMillis()
                pointer(scenario, MotionEvent.ACTION_DOWN, x, y, down)
                pointer(scenario, MotionEvent.ACTION_MOVE, x + track.width() * .2f, y, down)
                await { playback!!.state.value.scrubbing && port.pauses == 1 }
                val seekCount = port.seeks
                pointer(scenario, MotionEvent.ACTION_CANCEL, x + track.width() * .2f, y, down)
                await { !playback!!.state.value.scrubbing && port.plays == 2 }
                assertEquals(item, playback!!.state.value.token)
                assertEquals(seekCount, port.seeks, "Cancel must not commit a final seek")
                assertTrue(playback!!.state.value.playRequested)
            }
        } finally {
            runBlocking { withContext(Dispatchers.Main.immediate) { playback?.close(); library?.dispose(); scope.cancel() } }
            root.deleteRecursively()
        }
    }
    private class Port : MonitorPlaybackPort {
        override var onEvent: ((MonitorPlaybackItemToken, MonitorPlaybackEvent) -> Unit)? = null
        @Volatile var plays = 0; @Volatile var pauses = 0; @Volatile var seeks = 0
        override fun retireItem(token: MonitorPlaybackItemToken) {}
        override suspend fun prepare(item: MonitorPlaybackItem, token: MonitorPlaybackItemToken, readyTimeout: Duration?) = MonitorPlaybackMetadata(duration = 100.0)
        override fun play(rate: Double, token: MonitorPlaybackItemToken) { plays += 1 }
        override fun pause(token: MonitorPlaybackItemToken) { pauses += 1 }
        override suspend fun seek(seconds: Double, tolerance: Double, token: MonitorPlaybackItemToken): Boolean { seeks += 1; return true }
        override fun setMuted(muted: Boolean, token: MonitorPlaybackItemToken) {}
        override fun close(token: MonitorPlaybackItemToken) {}
    }
    private fun await(condition: () -> Boolean) {
        val deadline = SystemClock.uptimeMillis() + 2000
        while (SystemClock.uptimeMillis() < deadline) {
            if (condition()) return
            SystemClock.sleep(16)
        }
        assertTrue(condition(), "Native pointer/actual owner condition was not observed")
    }
    private fun bounds(label: String): Rect {
        fun find(node: AccessibilityNodeInfo): Rect? {
            if (node.contentDescription?.toString() == label) return Rect().also(node::getBoundsInScreen)
            for (index in 0 until node.childCount) {
                val child = node.getChild(index) ?: continue
                try { find(child)?.let { return it } } finally { child.recycle() }
            }
            return null
        }
        var result: Rect? = null
        await {
            val node = InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow
            if (node != null) { try { result = find(node) } finally { node.recycle() } }
            result?.let { it.width() > 0 && it.height() > 0 } == true
        }
        return result!!
    }
    private fun pointer(scenario: ActivityScenario<BackdropRenderActivity>, action: Int, x: Float, y: Float, down: Long) {
        scenario.onActivity { activity ->
            val origin = IntArray(2); activity.window.decorView.getLocationOnScreen(origin)
            val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, x - origin[0], y - origin[1], 0)
            try { activity.dispatchTouchEvent(event) } finally { event.recycle() }
        }
    }
}
