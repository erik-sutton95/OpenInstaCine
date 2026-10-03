package com.opencapture.openpocketcine

import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.dp
import com.opencapture.monitorui.monitorReadoutShadow
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.monitorui.MonitorMaterial
import com.opencapture.monitorui.MonitorHistogramScopePlot
import com.opencapture.opencine.media.ScopeHistogramDisplay
import com.opencapture.opencine.media.ScopeTrafficLightsReading
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Pixel evidence from the real HWUI/RenderEffect modifier, not an emulated blur model. */
@RunWith(AndroidJUnit4::class)
class MonitorBackdropRenderTest {
    @Test fun sharedAspectMaskLeavesTheUnionClearAndDimsItsCorners() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val masked = androidx.compose.runtime.mutableStateOf(false)
            var density = 1f
            var origin = Rect.Zero
            scenario.onActivity { activity ->
                density = activity.resources.displayMetrics.density
                activity.setContent {
                    Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.Blue)
                        .onGloballyPositioned { origin = it.boundsInWindow() }) {
                        com.opencapture.monitorui.MonitorAspectGuideFrames(
                            setOf(com.opencapture.monitorui.MonitorGuideAspect.CINEMA,
                                com.opencapture.monitorui.MonitorGuideAspect.VERTICAL),
                            com.opencapture.monitorui.MonitorScopeRect(20 * density, 20 * density,
                                320 * density, 180 * density), masked.value)
                    }
                }
            }
            fun blue(image: Bitmap, x: Float, y: Float): Int = Color.blue(image.getPixel(
                (origin.left + x * density).roundToInt(), (origin.top + y * density).roundToInt()))
            val clear = capture(scenario, "shared-guides-clear")
            assertTrue(blue(clear, 32f, 32f) > 240)
            scenario.onActivity { masked.value = true }
            val image = capture(scenario, "shared-guides-union-mask")
            assertTrue(blue(image, 32f, 32f) in 95..110, "The corner outside both selected frames must be masked")
            assertTrue(blue(image, 180f, 110f) > 240, "The overlap stays clear")
            assertTrue(blue(image, 180f, 22f) > 240, "The tall guide's independent arm stays clear")
            assertTrue(blue(image, 30f, 110f) > 240, "The wide guide's independent arm stays clear")
            assertTrue(blue(image, 5f, 5f) > 240, "The mask cannot escape the picture rect")
        }
    }

    @Test fun sharedMovablePanelDragsResizesHoldsAndHonorsLock() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val enabled = androidx.compose.runtime.mutableStateOf(true)
            val scale = androidx.compose.runtime.mutableStateOf(1.0)
            val stored = androidx.compose.runtime.mutableStateOf<com.opencapture.monitorui.MonitorScopeStoredCenter?>(null)
            val canvas = androidx.compose.runtime.mutableStateOf(com.opencapture.monitorui.MonitorScopeRect(0f, 0f, 1080f, 2000f))
            var windowBounds = Rect.Zero
            var rootBounds = Rect.Zero
            var stores = 0
            var opens = 0
            var opened: com.opencapture.monitorui.MonitorScopeRect? = null
            var density = 1f
            scenario.onActivity { activity ->
                density = activity.resources.displayMetrics.density
                activity.setContent {
                    Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.Black)
                        .onGloballyPositioned { canvas.value = com.opencapture.monitorui.MonitorScopeRect(
                            0f, 0f, it.size.width.toFloat(), it.size.height.toFloat()) }) {
                        val c = canvas.value
                        com.opencapture.monitorui.MonitorMovableScopePanel(
                            identity = "wave", base = com.opencapture.monitorui.MonitorScopePanelSize.waveform,
                            scale = scale.value, stored = stored.value, canvas = c,
                            placementBounds = com.opencapture.monitorui.MonitorScopeRect(8 * density, 8 * density,
                                c.width - 16 * density, c.height - 16 * density),
                            defaultCenter = com.opencapture.monitorui.MonitorScopePoint(c.midX, c.midY),
                            enabled = enabled.value,
                            anchorOrigin = androidx.compose.ui.geometry.Offset(20 * density, 30 * density),
                            onStore = { stored.value = it; stores++ },
                            onScale = { scale.value = it.coerceIn(0.6, 1.6) },
                            onOpenOptions = { opened = it; opens++ },
                        ) {
                            Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.Red)
                                .onGloballyPositioned { windowBounds = it.boundsInWindow()
                                    rootBounds = it.boundsInRoot() })
                        }
                    }
                }
            }
            fun gesture(start: androidx.compose.ui.geometry.Offset, end: androidx.compose.ui.geometry.Offset,
                hold: Boolean = false, beforeUp: (() -> Unit)? = null) {
                val downTime = android.os.SystemClock.uptimeMillis()
                fun send(action: Int, point: androidx.compose.ui.geometry.Offset) {
                    val event = android.view.MotionEvent.obtain(downTime,
                        android.os.SystemClock.uptimeMillis(), action, point.x, point.y, 0)
                    event.source = android.view.InputDevice.SOURCE_TOUCHSCREEN
                    instrumentation.sendPointerSync(event)
                    event.recycle()
                }
                send(android.view.MotionEvent.ACTION_DOWN, start)
                if (hold) android.os.SystemClock.sleep(380)
                else for (step in 1..12) {
                    android.os.SystemClock.sleep(16)
                    send(android.view.MotionEvent.ACTION_MOVE, start + (end - start) * (step / 12f))
                }
                beforeUp?.invoke()
                send(android.view.MotionEvent.ACTION_UP, end)
                instrumentation.waitForIdleSync()
            }
            capture(scenario, "shared-panel-initial")
            val initial = windowBounds
            gesture(initial.center, initial.center + androidx.compose.ui.geometry.Offset(24 * density, 36 * density))
            capture(scenario, "shared-panel-dragged")
            assertEquals(1, stores, "A real drag persists once at release")
            assertTrue(windowBounds.left > initial.left + 16 * density)
            assertTrue(windowBounds.top > initial.top + 24 * density)
            val restored = stored.value!!.center(canvas.value)
            assertEquals(rootBounds.center.x, restored.x, 1f)
            assertEquals(rootBounds.center.y, restored.y, 1f)

            val beforeHold = rootBounds
            gesture(windowBounds.center, windowBounds.center, hold = true)
            capture(scenario, "shared-panel-held")
            assertEquals(1, opens)
            assertEquals(1, stores, "Opening options must not persist a drag")
            assertEquals(beforeHold.left / density - 20f, opened!!.x, 0.5f)
            assertEquals(beforeHold.top / density - 30f, opened!!.y, 0.5f)
            assertEquals(beforeHold.width / density, opened!!.width, 0.5f)

            fun grip(): androidx.compose.ui.geometry.Offset {
                val origin = com.opencapture.monitorui.MonitorScopePanelMath.gripHitOrigin(
                    windowBounds.width / density, windowBounds.height / density)
                val hit = com.opencapture.monitorui.MonitorScopePanelMath.gripHitSize(
                    windowBounds.width / density, windowBounds.height / density)
                return androidx.compose.ui.geometry.Offset(windowBounds.left + (origin.x + hit / 2) * density,
                    windowBounds.top + (origin.y + hit / 2) * density)
            }
            val originalWidth = windowBounds.width
            val resizeStart = grip()
            gesture(resizeStart, resizeStart + androidx.compose.ui.geometry.Offset(24 * density, 24 * density))
            capture(scenario, "shared-panel-resized")
            assertTrue(scale.value > 1.05, "The real corner changes the operator scale")
            assertTrue(windowBounds.width > originalWidth + 10 * density)
            assertEquals(1, stores, "Resize does not rewrite normalized placement")

            scenario.onActivity { enabled.value = false }
            capture(scenario, "shared-panel-locked")
            val locked = windowBounds
            val lockedScale = scale.value
            gesture(locked.center, locked.center + androidx.compose.ui.geometry.Offset(30 * density, 30 * density))
            gesture(grip(), grip() + androidx.compose.ui.geometry.Offset(30 * density, 30 * density))
            gesture(locked.center, locked.center, hold = true)
            capture(scenario, "shared-panel-lock-verified")
            assertEquals(locked, windowBounds)
            assertEquals(lockedScale, scale.value)
            assertEquals(1, stores)
            assertEquals(1, opens)

            scenario.onActivity { enabled.value = true }
            capture(scenario, "shared-panel-unlocked")
            gesture(windowBounds.center, windowBounds.center + androidx.compose.ui.geometry.Offset(-24 * density, -24 * density),
                beforeUp = {
                    scenario.onActivity { enabled.value = false }
                    capture(scenario, "shared-panel-lock-during-drag")
                })
            capture(scenario, "shared-panel-cancelled")
            assertEquals(1, stores, "Locking during a drag must retire it without saving a partial move")
            assertEquals(locked, windowBounds, "Cancelled movement restores the saved panel position")
        }
    }

    @Test fun sharedScopeBrightnessZeroClearsRetainedTraceAndKeepsGuides() {
        for (kind in listOf("wave", "parade", "vector")) {
            ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
                val intensity = androidx.compose.runtime.mutableStateOf(1.0)
                val samples = com.opencapture.opencine.media.ScopeSamples.EMPTY.copy(points =
                    List(76) { index -> com.opencapture.opencine.media.ScopePoint(
                        index / 76.0, 0.5, 191, 30, 30, 80) })
                val bundle = com.opencapture.opencine.media.ScopeAssistBundle.EMPTY.copy(
                    revision = 1, samples = samples, vectorscopePoints = samples.points)
                val publication = androidx.compose.runtime.mutableStateOf(bundle)
                val table = com.opencapture.opencine.media.WaveformIre.levelTable(
                    com.opencapture.opencine.media.MonitorTransfer.REC709)
                var bounds = Rect.Zero
                var density = 1f
                scenario.onActivity { activity ->
                    density = activity.resources.displayMetrics.density
                    activity.setContent {
                        Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.Black),
                            contentAlignment = Alignment.Center) {
                            val modifier = Modifier.size(if (kind == "vector") 190.dp else 250.dp,
                                if (kind == "vector") 190.dp else 153.dp).onGloballyPositioned {
                                    bounds = it.boundsInWindow()
                                }
                            val transfer = com.opencapture.opencine.media.MonitorTransfer.REC709
                            val guides = com.opencapture.monitorui.MonitorScopeGuides(false, false, false)
                            when (kind) {
                                "wave" -> com.opencapture.monitorui.MonitorWaveformScopePlot(publication.value,
                                    transfer, table, intensity = intensity.value, guides = guides, modifier = modifier)
                                "parade" -> com.opencapture.monitorui.MonitorParadeScopePlot(publication.value,
                                    transfer, table, intensity = intensity.value, guides = guides, modifier = modifier)
                                else -> com.opencapture.monitorui.MonitorVectorscopeScopePlot(publication.value,
                                    brightness = (intensity.value * 100).toInt(), modifier = modifier)
                            }
                        }
                    }
                }
                fun redPixels(image: Bitmap): Int =
                    (bounds.top.roundToInt() until bounds.bottom.roundToInt()).sumOf { y ->
                        (bounds.left.roundToInt() until bounds.right.roundToInt()).count { x ->
                            val color = image.getPixel(x, y)
                            Color.red(color) > 40 && Color.red(color) > Color.green(color) * 1.8 &&
                                Color.red(color) > Color.blue(color) * 1.8
                        }
                    }
                val shown = capture(scenario, "shared-$kind-shown")
                assertTrue(redPixels(shown) > 1, "The actual $kind trace must be visible")
                scenario.onActivity { intensity.value = 0.0 }
                val hidden = capture(scenario, "shared-$kind-zero")
                assertEquals(0, redPixels(hidden), "Zero brightness must clear the retained signal")
                var guidePixels = 0
                for (y in bounds.top.roundToInt() until bounds.bottom.roundToInt()) {
                    for (x in bounds.left.roundToInt() until bounds.right.roundToInt()) {
                        val color = hidden.getPixel(x, y)
                        if (Color.red(color) > 100 && abs(Color.red(color) - Color.green(color)) < 25) guidePixels += 1
                    }
                }
                assertTrue(guidePixels > 80, "The scope chrome remains visible")
                if (kind != "vector") {
                    val guideX = (bounds.left + 6 * density).roundToInt() until
                        (bounds.right - 6 * density).roundToInt()
                    for (lineY in listOf(bounds.top + 27 * density, bounds.bottom - 3 * density)) {
                        val y = lineY.roundToInt()
                        val kept = guideX.count { x ->
                            (y - 1..y + 1).any { row ->
                                val color = hidden.getPixel(x, row)
                                Color.red(color) > 100 && abs(Color.red(color) - Color.green(color)) < 25
                            }
                        }
                        assertTrue(kept > guideX.count() * 0.8, "The actual $kind 0/100 guide remains visible")
                    }
                }
                scenario.onActivity { intensity.value = 1.0 }
                val restored = capture(scenario, "shared-$kind-restored")
                assertEquals(redPixels(shown), redPixels(restored), "Restoring brightness rebuilds the same measured signal")
                scenario.onActivity {
                    publication.value = bundle.copy(revision = 2,
                        samples = com.opencapture.opencine.media.ScopeSamples.EMPTY, vectorscopePoints = emptyList())
                }
                val retired = capture(scenario, "shared-$kind-retired")
                assertEquals(0, redPixels(retired), "An empty successor publication cannot keep the retired signal")
            }
        }
    }

    @Test fun nativeTextureHostRetiresOldWindowWithoutReleasingCurrentSurface() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val surfaces = mutableListOf<android.view.Surface>()
            val program = com.opencapture.opencine.runtime.MonitorDecoderTextureProgram { surfaces += it }
            var updates = 0
            val host = com.opencapture.opencine.runtime.MonitorTexturePictureHost(
                instrumentation.targetContext, program, updated = { updates += 1 })
            val listener = requireNotNull(host.surfaceTextureListener)
            val old = android.graphics.SurfaceTexture(false)
            val current = android.graphics.SurfaceTexture(false)
            try {
                old.setDefaultBufferSize(16, 16)
                current.setDefaultBufferSize(32, 16)
                listener.onSurfaceTextureAvailable(old, 16, 16)
                assertTrue(surfaces.single().isValid, "The actual direct decoder surface is valid")
                listener.onSurfaceTextureAvailable(current, 32, 16)
                assertTrue(!surfaces.first().isValid, "Replacement releases the old native output surface")
                assertTrue(surfaces.last().isValid)
                listener.onSurfaceTextureDestroyed(old)
                listener.onSurfaceTextureUpdated(old)
                assertTrue(surfaces.last().isValid, "Late teardown cannot release the replacement")
                assertEquals(0, updates, "Old window updates cannot refresh source presentation")
                listener.onSurfaceTextureUpdated(current)
                assertEquals(1, updates)
                listener.onSurfaceTextureDestroyed(current)
                assertTrue(!surfaces.last().isValid, "Native ownership ends with the current window")
                listener.onSurfaceTextureUpdated(current)
                assertEquals(1, updates, "Retired current-window updates are also refused")
            } finally {
                old.release()
                current.release()
            }
        }
    }

    @Test fun sharedHistogramKeepsTheSignalWhenEdgeLightsAreHidden() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val display = ScopeHistogramDisplay.EMPTY.copy(red = FloatArray(256) {
                if (it in 100 until 156) 20f else 0f
            })
            val traffic = ScopeTrafficLightsReading.NONE.let {
                it.copy(red = it.red.copy(crush = true))
            }
            var bounds = Rect.Zero
            var density = 1f
            fun render(lights: Boolean): Bitmap {
                scenario.onActivity { activity ->
                    density = activity.resources.displayMetrics.density
                    activity.setContent {
                        Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.Black),
                            contentAlignment = Alignment.Center) {
                            MonitorHistogramScopePlot(display, traffic, lights,
                                Modifier.size(250.dp, 77.dp).onGloballyPositioned {
                                    bounds = it.boundsInWindow()
                                })
                        }
                    }
                }
                return capture(scenario, "shared-histogram-${if (lights) "shown" else "hidden"}")
            }
            fun redPixels(image: Bitmap, xRange: IntRange): Int =
                (bounds.top.roundToInt() until bounds.bottom.roundToInt()).sumOf { y ->
                    xRange.count { x ->
                        val color = image.getPixel(x, y)
                        Color.red(color) > 180 && Color.green(color) < 170 && Color.blue(color) < 170
                    }
                }
            val shown = render(true)
            val hidden = render(false)
            val edge = bounds.left.roundToInt() until (bounds.left + 17 * density).roundToInt()
            val signal = (bounds.left + 20 * density).roundToInt() until
                (bounds.left + 230 * density).roundToInt()
            assertTrue(redPixels(shown, edge) > 60 * density * density,
                "The source's crushed red channel must light its edge block")
            assertEquals(0, redPixels(hidden, edge), "Hiding traffic lights removes their edge block")
            val measured = redPixels(hidden, signal)
            assertTrue(measured > 30 * density * density, "The ready-to-draw histogram remains visible")
            assertEquals(measured, redPixels(shown, signal),
                "The traffic-light preference cannot change the measured signal trace")
        }
    }

    @Test fun readoutBloomExtendsOutsideContentWithoutChangingLayoutOrForeground() {
        assumeTrue(Build.VERSION.SDK_INT >= 31)
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            var bounds = Rect.Zero
            var density = 1f
            scenario.onActivity { activity ->
                density = activity.resources.displayMetrics.density
                activity.setContent {
                    Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.White),
                        contentAlignment = Alignment.Center) {
                        Box(Modifier.size(20.dp).onGloballyPositioned { bounds = it.boundsInWindow() }
                            .monitorReadoutShadow().background(androidx.compose.ui.graphics.Color.Cyan))
                    }
                }
            }
            val image = capture(scenario)
            assertEquals(20f * density, bounds.width, 1f, "Bloom must not enlarge the hit target")
            val halo = image.getPixel((bounds.left - 2f * density).roundToInt(), bounds.center.y.roundToInt())
            assertTrue(Color.red(halo) < 230, "Shadow must extend outside the content bounds")
            val foreground = image.getPixel(bounds.center.x.roundToInt(), bounds.center.y.roundToInt())
            assertTrue(Color.red(foreground) < 5 && Color.green(foreground) > 250 && Color.blue(foreground) > 250,
                "Foreground stays sharp and keeps its original color")
        }
    }

    @Test fun referenceMaterialsBlurBackdropAndKeepForegroundSharp() {
        assumeTrue(Build.VERSION.SDK_INT >= 31)
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val treatments = listOf("compact" to MonitorMaterial.Compact, "expanded" to MonitorMaterial.Expanded,
                "zoom" to MonitorMaterial.Zoom, "scope" to MonitorMaterial.Scope, "info" to MonitorMaterial.Info,
                "delivery" to MonitorMaterial.Delivery, "record" to MonitorMaterial.Record)
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            val colors = org.json.JSONObject(context.assets.open("monitor_backdrop_color_samples.json")
                .bufferedReader().use { it.readText() })
            for ((name, material) in treatments) {
                scenario.onActivity { it.material = material }
                val image = capture(scenario, name)
                val scale = minOf(image.width / 900f, image.height / 600f)
                fun pixel(x: Float, y: Float) = image.getPixel((x * scale).roundToInt(), (y * scale).roundToInt())
                val left = Color.red(pixel(300f, 200f)); val right = Color.red(pixel(600f, 200f))
                val low = left + (right - left) * .1f; val high = left + (right - left) * .9f
                fun crossing(level: Float): Int = (350..550).first { Color.red(pixel(it.toFloat(), 200f)) >= level }
                val spread = crossing(high) - crossing(low)
                // Browser reference 10–90 sigma spread: compact46, expanded52, zoom60, scope20.
                val oracle = colors.getJSONObject(when (name) { "info" -> "information"; "record" -> "recording"; else -> name })
                for (x in listOf(225, 375, 525, 675)) {
                    val rgb = oracle.getJSONArray(x.toString())
                    val color = pixel(x.toFloat(), 410f)
                    listOf(Color.red(color), Color.green(color), Color.blue(color)).forEachIndexed { channel, actual ->
                        assertTrue(abs(actual - rgb.getInt(channel)) <= 2, "$name color x$x channel$channel=$actual")
                    }
                }
                val expected = material.blurDp * 2.56f
                assertTrue(abs(spread - expected) <= maxOf(5f, expected * .15f), "$name spread=$spread expected=$expected")
                val expectedLeft = material.tint.red * 255 * material.tint.alpha
                val expectedRight = 255 * (1 - material.tint.alpha) + expectedLeft
                assertTrue(abs(left - expectedLeft) < 3f, "$name left=$left")
                assertTrue(abs(right - expectedRight) < 3f, "$name right=$right")
                assertTrue(Color.red(pixel(447f, 60f)) < 4 && Color.red(pixel(453f, 60f)) > 250, "outside plate stays sharp")
                assertTrue(Color.red(pixel(420f, 448f)) > 250, "foreground remains opaque white")
                assertTrue(Color.red(pixel(420f, 443f)) < 240, "no blurred foreground halo")
            }
        }
    }

    @Test fun sampledImageReplacementResizeMirrorAndNestedPanelsStayIndependent() {
        assumeTrue(Build.VERSION.SDK_INT >= 31)
        val intent = Intent(ApplicationProvider.getApplicationContext(), BackdropRenderActivity::class.java)
            .putExtra("sampled", true)
        ActivityScenario.launch<BackdropRenderActivity>(intent).use { scenario ->
            capture(scenario, "sampled")
            scenario.onActivity { it.mirror = true; it.nested = true }
            var image = capture(scenario, "mirrored-nested")
            var scale = minOf(image.width / 900f, image.height / 600f)
            assertTrue(Color.red(image.getPixel((300 * scale).toInt(), (200 * scale).toInt())) > 100)
            repeat(8) { scenario.onActivity { it.fixtureScale = if (it.fixtureScale == 1f) .8f else 1f }; capture(scenario) }
            scenario.onActivity { it.replaceSource(Color.GREEN) }
            image = capture(scenario, "replacement")
            scale = minOf(image.width / 900f, image.height / 600f)
            val green = image.getPixel((300 * scale).toInt(), (200 * scale).toInt())
            assertTrue(Color.green(green) > 100 && Color.red(green) < 20, "new source replaces old pixels")
            scenario.onActivity { it.replaceSource(null) }
            image = capture(scenario, "unavailable")
            val cleared = image.getPixel((300 * scale).toInt(), (200 * scale).toInt())
            assertTrue(
                abs(Color.red(cleared) - 8) <= 1 &&
                    abs(Color.green(cleared) - 9) <= 1 &&
                    abs(Color.blue(cleared) - 10) <= 1,
                "missing source is canvas 0x08090A",
            )
            scenario.onActivity {
                it.replaceSource(Color.GREEN)
                it.secondSource.image = Bitmap.createBitmap(100, 80, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.BLUE) }
                it.splitSources = true
            }
            image = capture(scenario, "multiple-sources")
            val leftTile = image.getPixel((300 * scale).toInt(), (200 * scale).toInt())
            val rightTile = image.getPixel((600 * scale).toInt(), (200 * scale).toInt())
            assertTrue(Color.green(leftTile) > 100 && Color.blue(leftTile) < 20)
            assertTrue(Color.blue(rightTile) > 100 && Color.green(rightTile) < 20)
            scenario.moveToState(Lifecycle.State.CREATED)
            scenario.moveToState(Lifecycle.State.RESUMED)
            scenario.recreate()
            capture(scenario, "recreated")
        }
    }

    private fun capture(scenario: ActivityScenario<BackdropRenderActivity>, name: String? = null): Bitmap {
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        Thread.sleep(160) // wait for actual display presentation, not just Compose apply
        val latch = CountDownLatch(1)
        var image: Bitmap? = null
        var status = -1
        scenario.onActivity { activity ->
            val bitmap = Bitmap.createBitmap(activity.window.decorView.width, activity.window.decorView.height, Bitmap.Config.ARGB_8888)
            image = bitmap
            // Test-only window readback verifies actual HWUI output. Production never PixelCopies chrome.
            PixelCopy.request(activity.window, bitmap, { result -> status = result; latch.countDown() }, Handler(Looper.getMainLooper()))
        }
        assertTrue(latch.await(5, TimeUnit.SECONDS), "window capture timed out")
        assertEquals(PixelCopy.SUCCESS, status)
        val bitmap = checkNotNull(image)
        if (name != null) {
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            File(context.getExternalFilesDir(null), "backdrop-$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
        return bitmap
    }
}
