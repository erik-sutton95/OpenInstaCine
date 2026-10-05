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
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
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
import org.junit.Test
import org.junit.runner.RunWith

/** Pixel evidence from the real HWUI/RenderEffect modifier, not an emulated blur model. */
@RunWith(AndroidJUnit4::class)
class MonitorBackdropRenderTest {
    @Test fun sharedTrackingMarksRenderProjectedEdgesAndClearAnEmptySuccessor() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val marks = androidx.compose.runtime.mutableStateOf(listOf(com.opencapture.monitorui.MonitorTrackingBracketValue(
                com.opencapture.monitorui.MonitorTrackingRect(0.2, 0.3, 0.3, 0.4),
                androidx.compose.ui.graphics.Color.Green)))
            val focus = androidx.compose.runtime.mutableStateOf<com.opencapture.monitorui.MonitorFocusMark?>(
                com.opencapture.monitorui.MonitorFocusMark(androidx.compose.ui.geometry.Offset(.8f, .45f),
                    androidx.compose.ui.graphics.Color.Red, aeLocked = true, focusLocked = true))
            var bounds = Rect.Zero
            var density = 1f
            scenario.onActivity { activity ->
                density = activity.resources.displayMetrics.density
                activity.setContent {
                    Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.Black)) {
                        com.opencapture.monitorui.MonitorTrackingLayer(marks.value, focus.value,
                            Modifier.size(300.dp, 200.dp).onGloballyPositioned { bounds = it.boundsInWindow() })
                    }
                }
            }
            fun pixels(image: Bitmap, columns: IntRange, rows: IntRange, channel: Int): Int {
                var count = 0
                for (y in (bounds.top + rows.first * density).roundToInt() until
                    (bounds.top + (rows.last + 1) * density).roundToInt()) {
                    for (x in (bounds.left + columns.first * density).roundToInt() until
                        (bounds.left + (columns.last + 1) * density).roundToInt()) {
                        val c = image.getPixel(x, y)
                        val rgb = listOf(Color.red(c), Color.green(c), Color.blue(c))
                        if (rgb[channel] > 100 && rgb.indices.filter { it != channel }.all { rgb[it] < 30 }) count++
                    }
                }
                return count
            }
            val active = capture(scenario, "shared-tracking-active")
            assertTrue(pixels(active, 55..85, 55..90, 1) > 40 * density * density)
            assertEquals(0, pixels(active, 99..111, 58..62, 1), "Bracket arms must leave the upper center open")
            assertTrue(pixels(active, 200..280, 65..110, 0) > 20 * density * density)
            scenario.onActivity {
                marks.value = listOf(com.opencapture.monitorui.MonitorTrackingBracketValue(
                    com.opencapture.monitorui.MonitorTrackingRect(0.5, 0.3, 0.3, 0.4),
                    androidx.compose.ui.graphics.Color.Green))
                focus.value = null
            }
            val projected = capture(scenario, "shared-tracking-projected")
            assertEquals(0, pixels(projected, 55..85, 55..90, 1))
            assertTrue(pixels(projected, 145..175, 55..90, 1) > 40 * density * density)
            assertEquals(0, pixels(projected, 200..280, 65..110, 0), "Retired focus and its lock tags must clear")
            scenario.onActivity { marks.value = emptyList() }
            assertEquals(0, pixels(capture(scenario, "shared-tracking-cleared"), 0..299, 0..199, 1))
        }
    }

    @Test fun sharedNDChipClearsTheAccentWhenPictureMeasurementDisappears() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val reading = androidx.compose.runtime.mutableStateOf<com.opencapture.opencine.media.MonitorNDFilterSuggestion?>(
                com.opencapture.opencine.media.MonitorNDFilterRecommendation.suggestion(6.0, "\u2014"))
            var bounds = Rect.Zero
            var density = 1f
            scenario.onActivity { activity ->
                density = activity.resources.displayMetrics.density
                activity.setContent {
                    Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.Black)) {
                        com.opencapture.monitorui.MonitorNDFilterChip(reading.value,
                            modifier = Modifier.size(84.dp, 30.dp).onGloballyPositioned { bounds = it.boundsInWindow() },
                            emptyLabel = "\u2014")
                    }
                }
            }
            fun accentPixels(image: Bitmap): Int {
                var count = 0
                for (y in bounds.top.roundToInt() until bounds.bottom.roundToInt()) {
                    for (x in bounds.left.roundToInt() until bounds.right.roundToInt()) {
                        val c = image.getPixel(x, y)
                        val r = Color.red(c); val g = Color.green(c); val b = Color.blue(c)
                        if (maxOf(r, g, b) - minOf(r, g, b) > 80) count++
                    }
                }
                return count
            }
            val hot = capture(scenario, "shared-ND-hot")
            assertTrue(accentPixels(hot) > 20 * density * density)
            scenario.onActivity { reading.value = null }
            assertEquals(0, accentPixels(capture(scenario, "shared-ND-absent")))
            scenario.onActivity { reading.value = com.opencapture.opencine.media.MonitorNDFilterRecommendation.suggestion(0.0, "\u2014") }
            assertEquals(0, accentPixels(capture(scenario, "shared-ND-zero")))
        }
    }

    @Test fun sharedLevelOverlayClearsKnownGreenAndReplacesBubbleWithUnavailable() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val display = androidx.compose.runtime.mutableStateOf<com.opencapture.monitorui.MonitorLevelDisplay>(
                com.opencapture.monitorui.MonitorLevelDisplay.Gauges(0.0, 0.0))
            var bounds = Rect.Zero
            var density = 1f
            scenario.onActivity { activity ->
                density = activity.resources.displayMetrics.density
                activity.setContent {
                    Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.Black)) {
                        com.opencapture.monitorui.MonitorLevelOverlay(display.value,
                            com.opencapture.monitorui.MonitorScopeRect(0f, 0f, 300f, 300f),
                            com.opencapture.monitorui.MonitorScopeRect(0f, 0f, 300f, 300f), true,
                            Modifier.size(300.dp).onGloballyPositioned { bounds = it.boundsInWindow() })
                    }
                }
            }
            fun greenPixels(image: Bitmap): Int {
                var count = 0
                for (y in bounds.top.roundToInt() until bounds.bottom.roundToInt()) {
                    for (x in bounds.left.roundToInt() until bounds.right.roundToInt()) {
                        val c = image.getPixel(x, y)
                        if (Color.green(c) > 100 && Color.green(c) > Color.red(c) * 2
                                && Color.green(c) > Color.blue(c) * 3 / 2) count++
                    }
                }
                return count
            }
            val gauges = capture(scenario, "shared-level-known-zero")
            assertTrue(greenPixels(gauges) > 100 * density * density)
            scenario.onActivity { display.value = com.opencapture.monitorui.MonitorLevelDisplay.Unavailable }
            assertEquals(0, greenPixels(capture(scenario, "shared-level-unavailable")))
            scenario.onActivity { display.value = com.opencapture.monitorui.MonitorLevelDisplay.Bubble(0.0, 0.0) }
            assertTrue(greenPixels(capture(scenario, "shared-level-known-bubble")) > 40 * density * density)
            scenario.onActivity { display.value = com.opencapture.monitorui.MonitorLevelDisplay.Unavailable }
            assertEquals(0, greenPixels(capture(scenario, "shared-level-retired-bubble")))
        }
    }

    @Test fun sharedFalseColorReferenceRetainsResolvedKeyRendersGapsAndClearsSuccessor() {
        val source = mutableListOf(
            com.opencapture.monitorui.MonitorFalseColorReferenceSegment(0, 0.0, 0.25, 1.0, 0.0, 0.0),
            com.opencapture.monitorui.MonitorFalseColorReferenceSegment(1, 0.75, 1.0, 0.0, 0.0, 1.0))
        val held = com.opencapture.monitorui.MonitorFalseColorReferenceValues("Source A", source,
            axisLabels = listOf("crush", "18%", "clip"))
        source.clear()
        val successor = com.opencapture.monitorui.MonitorFalseColorReferenceValues("Source B", source)
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val values = androidx.compose.runtime.mutableStateOf(held)
            var density = 1f
            var bounds = Rect.Zero
            scenario.onActivity { activity ->
                density = activity.resources.displayMetrics.density
                activity.setContent {
                    Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.Black)) {
                        com.opencapture.monitorui.MonitorFalseColorReference(values.value,
                            Modifier.onGloballyPositioned { bounds = it.boundsInWindow() })
                    }
                }
            }
            fun color(image: Bitmap, x: Int): Int = image.getPixel(
                (bounds.left + x * density).roundToInt(), (bounds.top + 25 * density).roundToInt())
            val image = capture(scenario, "shared-false-color-reference")
            val red = color(image, 27)
            assertTrue(Color.red(red) > 240 && Color.green(red) < 10 && Color.blue(red) < 10)
            val blue = color(image, 237)
            assertTrue(Color.blue(blue) > 240 && Color.red(blue) < 10 && Color.green(blue) < 10)
            val gap = color(image, 132)
            assertTrue(abs(Color.red(gap) - Color.green(gap)) < 4 && abs(Color.green(gap) - Color.blue(gap)) < 4)
            scenario.onActivity { values.value = successor }
            val cleared = capture(scenario, "shared-false-color-cleared")
            for (x in listOf(27, 132, 237)) {
                val c = color(cleared, x)
                assertTrue(abs(Color.red(c) - Color.green(c)) < 4 && abs(Color.green(c) - Color.blue(c)) < 4)
            }
        }
    }

    @Test fun sharedTrafficMeterPlacesOverUnderBarsAndClearsTheNextReading() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val reading = androidx.compose.runtime.mutableStateOf(ScopeTrafficLightsReading.NONE)
            var density = 1f
            var bounds = Rect.Zero
            scenario.onActivity { activity ->
                density = activity.resources.displayMetrics.density
                activity.setContent {
                    Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.Black)) {
                        com.opencapture.monitorui.MonitorTrafficLightsMeter(reading.value,
                            Modifier.size(74.dp, 168.dp).onGloballyPositioned { bounds = it.boundsInWindow() })
                    }
                }
            }
            fun pixels(image: Bitmap, lane: IntRange, rows: IntRange, component: Int): Int {
                var count = 0
                val x0 = (bounds.left + lane.first * density).roundToInt()
                val x1 = (bounds.left + (lane.last + 1) * density).roundToInt()
                val y0 = (bounds.top + rows.first * density).roundToInt()
                val y1 = (bounds.top + (rows.last + 1) * density).roundToInt()
                for (y in y0 until y1) for (x in x0 until x1) {
                    val color = image.getPixel(x, y)
                    val channels = listOf(Color.red(color), Color.green(color), Color.blue(color))
                    val dominant = channels[component]
                    if (dominant > 45 && channels.indices.filter { it != component }
                            .all { dominant > channels[it] * 1.4 }) count++
                }
                return count
            }
            val neutral = capture(scenario, "shared-traffic-neutral")
            scenario.onActivity { reading.value = ScopeTrafficLightsReading(
                com.opencapture.opencine.media.ScopeChannelLight(clip = true, crush = false, level = 0.9),
                com.opencapture.opencine.media.ScopeChannelLight(clip = false, crush = true, level = 0.1),
                com.opencapture.opencine.media.ScopeChannelLight(clip = false, crush = false, level = 0.5)) }
            val active = capture(scenario, "shared-traffic-active")
            assertTrue(pixels(active, 14..26, 42..84, 0) - pixels(neutral, 14..26, 42..84, 0) > 100 * density * density)
            assertTrue(pixels(active, 31..43, 92..137, 1) - pixels(neutral, 31..43, 92..137, 1) > 100 * density * density)
            assertTrue(pixels(active, 14..26, 92..137, 0) < 5 * density * density)
            assertTrue(pixels(active, 31..43, 42..84, 1) < 5 * density * density)
            assertTrue(pixels(active, 48..60, 42..137, 2) < 5 * density * density)
            scenario.onActivity { reading.value = ScopeTrafficLightsReading.NONE }
            val cleared = capture(scenario, "shared-traffic-cleared")
            assertEquals(0, pixels(cleared, 14..26, 42..84, 0))
            assertEquals(0, pixels(cleared, 31..43, 92..137, 1))
        }
    }

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
