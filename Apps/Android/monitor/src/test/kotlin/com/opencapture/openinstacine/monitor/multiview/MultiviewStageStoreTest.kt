package com.opencapture.openinstacine.monitor.multiview

import com.opencapture.opencine.appkit.MultiviewStageJournal
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The Luna stage journal this app keeps: OpenCine's codec under this app's four-camera validation. */
class MultiviewStageStoreTest {
    private fun camera(slot: Int, id: String, lut: Boolean = false) =
        MultiviewStageJournal.Camera(
            slot = slot, id = id, name = "Luna $id", modelId = null, deviceAddress = "AA:BB:CC:DD:EE:0$slot",
            identity = "LUNA-$id".toByteArray(), address = "192.168.1.3$slot", experimental = false, lutEnabled = lut,
        )

    @Test fun theQualificationIsFourCameras() {
        assertEquals(4, MultiviewQualificationPolicy.tileCount)
    }

    @Test fun stageRoundTripsWithCleanupLedger() {
        val stage = MultiviewStageJournal.Stage(
            ssid = "Studio", hotspot = false, layout = "Grid", focusedIndex = 2,
            cameras = listOf(camera(0, "a", lut = true)), pendingReset = listOf(camera(0, "b")),
            returnedToCameraWiFi = false, fill = true,
        )
        assertEquals(stage, MultiviewStageStore.decode(MultiviewStageStore.encode(stage)!!))
    }

    @Test fun decodeAppliesThisAppsValidation() {
        val ok = MultiviewStageJournal.Stage(
            ssid = "Studio", hotspot = true, layout = "Center stage", focusedIndex = 0, cameras = listOf(camera(0, "a")),
        )
        assertEquals(ok, MultiviewStageStore.decode(MultiviewStageStore.encode(ok)!!))
        assertNull(MultiviewStageStore.encode(ok.copy(focusedIndex = 4)))
        val five = (0..4).map { camera(it % 4, "c$it") }
        assertNull(MultiviewStageStore.encode(ok.copy(cameras = five)))
        // Stored text another build wrote is held to the same rule.
        assertNull(MultiviewStageStore.decode(MultiviewStageJournal.encode(ok.copy(cameras = five))))
        assertNull(MultiviewStageStore.decode("not json"))
    }
}
