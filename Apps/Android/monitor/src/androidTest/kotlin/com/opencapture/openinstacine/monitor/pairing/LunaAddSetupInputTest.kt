package com.opencapture.openinstacine.monitor.pairing

import android.graphics.Rect
import android.os.Build
import android.os.SystemClock
import android.view.MotionEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.opencine.appkit.AddSetupFlowView
import com.opencapture.opencine.appkit.DiscoveryPermissions
import com.opencapture.opencine.appkit.StationNetworkSetup
import com.opencapture.opencine.core.IntegrationID
import com.opencapture.opencine.core.RouteKind
import com.opencapture.opencine.core.SavedCamera
import com.opencapture.opencine.core.SavedRoute
import com.opencapture.openinstacine.monitor.BackdropRenderActivity
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * A saved Luna's Add setup through real input (SIMULATED camera, no radio): the shared chooser
 * offers Wi-Fi and Hotspot, and Wi-Fi opens the shared wizard, which says this camera cannot list
 * networks instead of asking for it to be turned on.
 */
@RunWith(AndroidJUnit4::class)
class LunaAddSetupInputTest {
    private val ap = SavedRoute(key = "ap", kind = RouteKind.CAMERA_ACCESS_POINT, network = "Luna Ultra TEST01.OSC", bluetooth = true)
    private val camera = SavedCamera(
        id = "AA:BB", integration = IntegrationID("com.opencapture.insta360.luna"), advertisedName = "Luna Ultra",
        model = "Insta360 Luna Ultra", routes = listOf(ap), preferredRoute = ap.id,
    )

    @Test fun addSetupOffersWiFiAndHotspotAndWiFiNeedsNoCameraScan() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    Box(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
                        AddSetupFlowView(lunaAddSetupFlow(camera, failed = null, done = {}) { page ->
                            StationNetworkSetup(
                                brand = INSTA_STATION_BRAND,
                                wifiNameAccess = rememberPermissionGate("wifi-name", DiscoveryPermissions.wifiName, DiscoveryPermissions.wifiNameRequest),
                                savedNetworks = emptyList(),
                                currentSsid = { null }, hotspotActive = { false },
                                scan = null,
                                connect = { null }, cancel = {}, complete = {},
                                camera = camera, startPage = page, cameraScansNetworks = false,
                            )
                        })
                    }
                }
            }
            awaitText("How should this camera connect?")
            awaitTag("stationSetup.wifi")
            awaitTag("stationSetup.phoneHotspot")
            tap(awaitTag("stationSetup.wifi"))
            awaitText("This camera can’t list networks")
            awaitText("Choose a known network, or Other network.")
        }
    }

    private fun find(root: AccessibilityNodeInfo, matches: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo? {
        if (matches(root)) return root
        for (index in 0 until root.childCount) root.getChild(index)?.let { child -> find(child, matches)?.let { return it } }
        return null
    }

    private fun await(what: String, matches: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        repeat(50) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) automation.clearCache()
            automation.rootInActiveWindow?.let { root -> find(root, matches)?.let { return it } }
            SystemClock.sleep(100)
        }
        error("Not shown: $what")
    }

    private fun awaitText(text: String) = await(text) { it.text?.toString() == text }

    private fun awaitTag(tag: String) = await(tag) { it.viewIdResourceName == tag }

    private fun tap(node: AccessibilityNodeInfo) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val bounds = Rect().also(node::getBoundsInScreen)
        val down = SystemClock.uptimeMillis()
        for (action in listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP)) {
            val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, bounds.exactCenterX(), bounds.exactCenterY(), 0)
            assertTrue(instrumentation.uiAutomation.injectInputEvent(event, true))
            event.recycle()
        }
        instrumentation.waitForIdleSync()
    }
}
