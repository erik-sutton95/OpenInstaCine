package com.opencapture.openinstacine.monitor.pairing

import com.opencapture.opencine.appkit.StationNetwork
import com.opencapture.opencine.appkit.StationSetupPage
import com.opencapture.opencine.core.IntegrationID
import com.opencapture.opencine.core.RouteDraft
import com.opencapture.opencine.core.RouteKind
import com.opencapture.opencine.core.SavedCamera
import com.opencapture.opencine.core.SavedRoute
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** A saved Luna's Add setup: the shared Wi-Fi or Hotspot choice, then the shared wizard (SIMULATED camera). */
class LunaAddSetupFlowTest {
    private val ap = SavedRoute(key = "ap", kind = RouteKind.CAMERA_ACCESS_POINT, network = "Luna Ultra TEST01.OSC", bluetooth = true)
    private val wifi = SavedRoute(key = "wifi", kind = RouteKind.INFRASTRUCTURE_NETWORK, network = "Studio", bluetooth = true)
    private val camera = SavedCamera(
        id = "AA:BB", integration = IntegrationID("com.opencapture.insta360.luna"), advertisedName = "Luna Ultra",
        model = "Insta360 Luna Ultra", routes = listOf(ap), preferredRoute = ap.id,
    )

    @Test fun addSetupAsksHowTheCameraShouldConnectWithWiFiAndHotspot() {
        val drafts = mutableListOf<RouteDraft?>()
        val flow = lunaAddSetupFlow(camera, failed = null, done = { drafts += it }) {}
        assertEquals("How should this camera connect?", flow.chooser.title)
        assertEquals(listOf("Wi-Fi", "Hotspot"), flow.chooser.options.map { it.title })
        assertEquals(listOf(RouteKind.INFRASTRUCTURE_NETWORK, RouteKind.PHONE_HOTSPOT), flow.chooser.options.map { it.kind })
        assertTrue(flow.chooser.options.all { it.enabled })
        assertNull(flow.initialSelection)
        flow.onCancel()
        assertEquals(listOf<RouteDraft?>(null), drafts)
    }

    @Test fun eachChoiceOpensItsWizardPage() {
        assertEquals(StationSetupPage.Networks, startPage(RouteKind.INFRASTRUCTURE_NETWORK, null, camera))
        assertEquals(StationSetupPage.Hotspot, startPage(RouteKind.PHONE_HOTSPOT, null, camera))
    }

    @Test fun editingAFailedSetupReopensItsPage() {
        val withWifi = camera.copy(routes = listOf(ap, wifi))
        assertEquals("wifi", lunaAddSetupFlow(withWifi, RouteKind.INFRASTRUCTURE_NETWORK, {}) {}.initialSelection)
        assertEquals(StationSetupPage.Password("Studio"), startPage(RouteKind.INFRASTRUCTURE_NETWORK, RouteKind.INFRASTRUCTURE_NETWORK, withWifi))
        assertEquals("phoneHotspot", lunaAddSetupFlow(withWifi, RouteKind.PHONE_HOTSPOT, {}) {}.initialSelection)
    }

    @Test fun aConfirmedNetworkBecomesTheSetupToAdd() {
        assertEquals(RouteDraft(RouteKind.INFRASTRUCTURE_NETWORK, "Studio", "synthetic1"), StationNetwork("Studio", "synthetic1", false).routeDraft())
        assertEquals(RouteDraft(RouteKind.PHONE_HOTSPOT, "Rig", "synthetic2"), StationNetwork("Rig", "synthetic2", true).routeDraft())
    }

    @Test fun theWizardKnowsLunaAccessPointsAreCameraNetworks() {
        assertTrue(ap.network!!.startsWith(INSTA_STATION_BRAND.cameraNetworkPrefix, ignoreCase = true))
        assertEquals("OpenInstaCine", INSTA_STATION_BRAND.appName)
        assertEquals("Luna", INSTA_STATION_BRAND.cameraFamily)
    }
}
