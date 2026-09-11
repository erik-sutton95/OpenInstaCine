package com.opencapture.openpocketcine.feed

import com.opencapture.openpocketcine.lut.LutCatalog
import com.opencapture.openpocketcine.lut.LutCategory
import com.opencapture.openpocketcine.lut.LutEntry
import com.opencapture.openpocketcine.session.CameraCommands
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

class CameraLutIntegrationTest {
    private val official = LutEntry(
        "camera:insta360-luna-ilog-rec709-v2", "I-Log → Rec.709", LutCategory.CAMERA,
        "Luna_I-Log_to_Rec709_BT1886_s33_v2.cube", MonitorTransfer.ILOG,
    )

    @Test
    fun cameraCatalogListsAutoAndOnlySuppliedSdrEntry() {
        val entries = LutCatalog.cameraEntries(
            listOf(official.fileName!!, "AnHDRLook.cube", "DJI_Official_Pocket4P_DLog2_Rec709_33.cube"),
            listOf(official),
        )
        assertEquals(listOf("auto", official.id), entries.map { it.id })
        assertEquals(listOf("Auto", "I-Log → Rec.709"), entries.map { it.title })
        assertEquals(listOf(LutCatalog.auto), LutCatalog.cameraEntries(emptyList(), listOf(official)))
    }

    @Test
    fun selectionPersistenceKeepsNeutralAutoAndExplicitCameraId() {
        assertEquals("auto", LutCatalog.normalizedSelection("auto"))
        assertEquals("auto", LutCatalog.normalizedSelection("djiAuto"))
        assertEquals(official.id, LutCatalog.normalizedSelection(official.id))
        val previous = LutCatalog.cameraLooks
        try {
            LutCatalog.configureCameraLooks(listOf(official))
            assertEquals(official.title, LutCatalog.titleFor(official.id))
            assertEquals(LutCategory.CAMERA, LutCatalog.categoryOf(official.id))
        } finally {
            LutCatalog.configureCameraLooks(previous)
        }
    }

    @Test
    fun manualConversionUsesDeclaredLutInputOnlyForExposure() {
        val sourceColor = CameraCommands.COLOR_NORMAL
        val source = assertIs<LutLookSource.Asset>(
            LutLookResolver.resolve(official.id, true, sourceColor, "generic", "Luna Ultra", listOf(official)),
        )
        assertEquals(official.fileName, source.fileName)
        assertEquals(official.title, LutLookResolver.sourceTitle(source))
        assertEquals(65_536, LutLookResolver.exposureColorMode(source, sourceColor))
        assertEquals(MonitorTransfer.REC709, MonitorTransfer.fromColorMode(sourceColor))
        assertEquals(sourceColor, LutLookResolver.exposureColorMode(LutLookSource.Custom("Look.cube"), sourceColor))
    }

    @Test
    fun autoAndDisabledLutLeaveCurrentPreviewUnconverted() {
        for (selection in listOf("auto", "djiAuto")) {
            assertEquals(
                LutLookSource.Off,
                LutLookResolver.resolve(selection, true, CameraCommands.COLOR_NORMAL, "generic", "Luna Ultra", listOf(official)),
            )
        }
        assertEquals(
            LutLookSource.Off,
            LutLookResolver.resolve(official.id, false, CameraCommands.COLOR_NORMAL, "generic", "Luna Ultra", listOf(official)),
        )
    }
}
