package com.opencapture.openinstacine.monitor

import com.opencapture.opencine.appkitnative.LiveStreamSource
import com.opencapture.opencine.insta360.luna.LunaBackend
import com.opencapture.opencine.insta360.luna.LunaRoute
import com.opencapture.opencine.insta360.luna.LunaStationNetwork
import com.opencapture.opencine.streaming.StreamConnectionRoute
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** Live streaming's route and source come from what the session already knows. */
class LiveStreamingTest {
    private val router = LunaRoute.Station(LunaStationNetwork("Studio", "secret", hotspot = false))
    private val hotspot = LunaRoute.Station(LunaStationNetwork("Phone", "secret", hotspot = true))
    private val stationHost = "192.168.1.40"

    @Test
    fun cameraWiFiIsTheCameraAccessPoint() {
        assertEquals(StreamConnectionRoute.CAMERA_WIFI,
            LiveStreaming.route(live = true, LunaRoute.CameraWiFi(), LunaBackend.CAMERA_HOST))
        assertEquals(StreamConnectionRoute.CAMERA_WIFI,
            LiveStreaming.route(live = true, LunaRoute.CameraWiFi(restoreAccessPoint = true), LunaBackend.CAMERA_HOST))
    }

    @Test
    fun aRouterSetupIsSharedWiFi() {
        assertEquals(StreamConnectionRoute.SHARED_WIFI, LiveStreaming.route(live = true, router, stationHost))
    }

    @Test
    fun aHotspotSetupIsTheDeviceHotspot() {
        assertEquals(StreamConnectionRoute.DEVICE_HOTSPOT, LiveStreaming.route(live = true, hotspot, stationHost))
    }

    @Test
    fun aSetupStillOnTheAccessPointAddressIsCameraWiFi() {
        assertEquals(StreamConnectionRoute.CAMERA_WIFI, LiveStreaming.route(live = true, router, LunaBackend.CAMERA_HOST))
        assertEquals(StreamConnectionRoute.CAMERA_WIFI, LiveStreaming.route(live = true, hotspot, null))
    }

    @Test
    fun noLiveCameraOrNoLunaRouteIsNoRoute() {
        assertNull(LiveStreaming.route(live = false, router, stationHost))
        assertNull(LiveStreaming.route(live = false, LunaRoute.CameraWiFi(), LunaBackend.CAMERA_HOST))
        // The debug local replay is not a Luna port: no route was ever requested.
        assertNull(LiveStreaming.route(live = true, null, null))
    }

    @Test
    fun theSourceIsTheDecodedPictureWithAnUnstatedRate() {
        assertEquals(LiveStreamSource(1920, 1080, null, null), LiveStreaming.source(hasPicture = true, 1920, 1080))
        assertEquals(LiveStreamSource(1080, 1920, null, null), LiveStreaming.source(hasPicture = true, 1080, 1920))
    }

    @Test
    fun noPictureIsNoSource() {
        assertNull(LiveStreaming.source(hasPicture = false, 1920, 1080))
        assertNull(LiveStreaming.source(hasPicture = true, 0, 1080))
    }
}
