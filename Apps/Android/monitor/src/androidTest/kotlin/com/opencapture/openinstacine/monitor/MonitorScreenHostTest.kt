package com.opencapture.openinstacine.monitor

import android.graphics.Color
import android.os.SystemClock
import android.view.View
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.monitorui.MonitorLayoutPolicy
import com.opencapture.opencine.appkit.MonitorControlModel
import com.opencapture.opencine.appkit.MonitorScreen
import com.opencapture.opencine.appkit.MonitorScreenPresentation
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.roundToInt
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

/** SIMULATED native hosts exercise the production shared screen, without a decoder or camera. */
@RunWith(AndroidJUnit4::class)
class MonitorScreenHostTest {
    @Test fun captureContentKeepsItsIntrinsicHeightAboveTheFixedBottom() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val layout = MonitorLayoutPolicy.fieldMonitor(400f, 800f)
        var captureHeight = 0
        var captureBottom = 0f
        var density = 1f
        var scope: CoroutineScope? = null
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                density = activity.resources.displayMetrics.density
                val owner = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
                scope = owner
                val control = MonitorControlModel(owner)
                activity.setContent {
                    MonitorScreen(control, layout,
                        MonitorScreenPresentation(statusMounted = false, powerMounted = false),
                        picture = {}, capture = {
                            // Font metrics can make two readout rows taller than the placement frame.
                            Box(Modifier.fillMaxWidth().height(100.dp).onGloballyPositioned {
                                captureHeight = it.size.height
                                captureBottom = it.positionInRoot().y + it.size.height
                            })
                        })
                }
            }
            settle()
            scenario.onActivity {
                assertEquals((100f * density).roundToInt(), captureHeight)
                assertEquals((layout.values.y + layout.values.height) * density, captureBottom, 1f)
            }
        }
        instrumentation.runOnMainSync { scope?.cancel() }
    }

    @Test fun nativeHostsRemainMountedThroughOrientationAndOpaqueCovers() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        var layout by mutableStateOf(MonitorLayoutPolicy.fieldMonitor(400f, 800f))
        var covered by mutableStateOf(false)
        var pictureMakes = 0
        var assistMakes = 0
        var detaches = 0
        var picture: View? = null
        var assists: View? = null
        var scope: CoroutineScope? = null
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val owner = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
                scope = owner
                val control = MonitorControlModel(owner)
                val detachListener = object : View.OnAttachStateChangeListener {
                    override fun onViewAttachedToWindow(view: View) = Unit
                    override fun onViewDetachedFromWindow(view: View) { detaches++ }
                }
                activity.setContent {
                    MonitorScreen(control, layout, MonitorScreenPresentation(visible = !covered,
                        statusMounted = false, powerMounted = false, captureMounted = false),
                        picture = {
                            AndroidView(factory = { context -> View(context).also {
                                pictureMakes++; picture = it; it.setBackgroundColor(Color.BLUE)
                                it.addOnAttachStateChangeListener(detachListener)
                            } }, modifier = Modifier.fillMaxSize())
                        }, assists = {
                            AndroidView(factory = { context -> View(context).also {
                                assistMakes++; assists = it; it.addOnAttachStateChangeListener(detachListener)
                            } }, modifier = Modifier.fillMaxSize())
                        }, cover = { if (covered) Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.Black)) })
                }
            }
            settle()
            val initialPicture = assertNotNull(picture)
            val initialAssists = assertNotNull(assists)
            for ((index, size) in listOf(800f to 400f, 400f to 800f, 1024f to 1366f, 1366f to 1024f).withIndex()) {
                scenario.onActivity {
                    covered = index % 2 == 0
                    layout = MonitorLayoutPolicy.fieldMonitor(size.first, size.second, fill = index == 1)
                }
                settle()
                scenario.onActivity {
                    assertSame(initialPicture, picture)
                    assertSame(initialAssists, assists)
                    assertTrue(initialPicture.isAttachedToWindow && initialAssists.isAttachedToWindow)
                    assertEquals(1, pictureMakes)
                    assertEquals(1, assistMakes)
                    assertEquals(0, detaches)
                }
            }
        }
        instrumentation.runOnMainSync { scope?.cancel() }
    }

    private fun settle() {
        // Wait for native layout and one publication cycle, not camera/core time.
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        SystemClock.sleep(120)
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
    }
}
