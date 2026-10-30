package com.opencapture.openinstacine.monitor.pairing

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.opencapture.opencine.appkit.AddSetupFlow
import com.opencapture.opencine.appkit.DiscoveryPermissions
import com.opencapture.opencine.appkit.StationNetwork
import com.opencapture.opencine.appkit.StationNetworkBrand
import com.opencapture.opencine.appkit.StationNetworkSetup
import com.opencapture.opencine.appkit.StationSetupPage
import com.opencapture.opencine.appkit.stationSetupChooser
import com.opencapture.opencine.core.ConnectTarget
import com.opencapture.opencine.core.RouteDraft
import com.opencapture.opencine.core.RouteKind
import com.opencapture.opencine.core.SavedCamera
import com.opencapture.opencine.platform.SharedWiFiPath
import com.opencapture.openinstacine.monitor.AppModel

/** This app's words and camera access-point naming (`Luna Ultra …`) for OpenCine's station-network wizard. */
val INSTA_STATION_BRAND = StationNetworkBrand(appName = "OpenInstaCine", cameraFamily = "Luna", cameraNetworkPrefix = "luna")

/** A confirmed wizard network as the setup the Luna integration adds and moves the camera to. */
fun StationNetwork.routeDraft(): RouteDraft =
    RouteDraft(if (hotspot) RouteKind.PHONE_HOTSPOT else RouteKind.INFRASTRUCTURE_NETWORK, ssid, password)

/**
 * The Luna add-setup slot (OpenPocketCine's `addSetupFlow`): the shared chooser, then the shared
 * station-network wizard over the backend's saved setups. The Luna cannot list networks, so the
 * wizard offers known networks and Other network. Edit setup reopens a failed setup on its
 * password or hotspot page.
 */
@Composable
internal fun addSetupFlow(model: AppModel, camera: SavedCamera, done: (RouteDraft?) -> Unit): AddSetupFlow {
    val context = LocalContext.current
    val wifi = remember { SharedWiFiPath(context) }
    val failed = (model.cameras.state.collectAsState().value.failures[camera.id]?.target as? ConnectTarget.Saved)
        ?.let { target -> camera.routes.firstOrNull { it.id == target.route }?.kind }
    val saved by produceState(emptyList<StationNetwork>(), camera.id) {
        value = model.session.savedStations().map { StationNetwork(it.ssid, it.password, it.hotspot) }
    }
    return lunaAddSetupFlow(camera, failed, done) { page ->
        StationNetworkSetup(
            brand = INSTA_STATION_BRAND,
            wifiNameAccess = rememberPermissionGate("wifi-name", DiscoveryPermissions.wifiName, DiscoveryPermissions.wifiNameRequest),
            savedNetworks = saved,
            currentSsid = wifi::currentSsid,
            hotspotActive = { wifi.address(true) != null },
            scan = null,
            connect = { network -> done(network.routeDraft()); null },
            cancel = { done(null) }, complete = { done(null) }, camera = camera,
            startPage = page,
            cameraScansNetworks = false,
        )
    }
}

/**
 * The typed shared choice (Wi-Fi, Hotspot) for [camera], followed by [wizard] on the page the
 * choice (or the setup that last failed, [failed]) opens.
 */
internal fun lunaAddSetupFlow(
    camera: SavedCamera,
    failed: RouteKind?,
    done: (RouteDraft?) -> Unit,
    wizard: @Composable (StationSetupPage) -> Unit,
): AddSetupFlow = AddSetupFlow(
    chooser = stationSetupChooser(camera),
    onSelect = {},
    destination = { option -> wizard(startPage(option.kind, failed, camera)) },
    initialSelection = when (failed) {
        RouteKind.PHONE_HOTSPOT -> "phoneHotspot"
        RouteKind.INFRASTRUCTURE_NETWORK -> "wifi"
        else -> null
    },
    onCancel = { done(null) },
)

/** Hotspot opens its page; a failed Wi-Fi setup reopens on its password; otherwise the networks. */
internal fun startPage(kind: RouteKind, failed: RouteKind?, camera: SavedCamera): StationSetupPage = when {
    kind == RouteKind.PHONE_HOTSPOT -> StationSetupPage.Hotspot
    failed == RouteKind.INFRASTRUCTURE_NETWORK ->
        StationSetupPage.Password(camera.routes.firstOrNull { it.kind == RouteKind.INFRASTRUCTURE_NETWORK }?.network.orEmpty())
    else -> StationSetupPage.Networks
}
