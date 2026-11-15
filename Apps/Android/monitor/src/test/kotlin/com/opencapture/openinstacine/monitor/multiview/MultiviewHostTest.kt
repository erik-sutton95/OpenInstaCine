package com.opencapture.openinstacine.monitor.multiview

import com.opencapture.opencine.appkit.MultiviewReadout
import com.opencapture.opencine.appkit.MultiviewSettingsCategory
import com.opencapture.opencine.appkit.MultiviewTally
import com.opencapture.opencine.core.NearbyCamera
import com.opencapture.opencine.core.RouteKind
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.openinstacine.monitor.AppModel
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The Android Multiview host's values (iOS `MultiviewSessionTests`): the Auto LUT rule, the tile
 * readouts, the settings popup's categories, the entry guard and the monitor's resume rule while
 * the stage is open. Pictures, Live View and the popup need a device and are hardware-untested.
 */
class MultiviewHostTest {
    private val luna = NearbyCamera(id = "AA:BB:CC:DD:EE:01", name = "Luna A1B2", model = "Insta360 Luna Ultra", routes = setOf(RouteKind.CAMERA_ACCESS_POINT))

    @Test fun autoLutGradesOnlyAnILogPictureAsLiveViewDoes() {
        assertEquals("I-Log to Rec.709", MultiviewLut.conversion("I-Log"))
        assertNull(MultiviewLut.conversion("Standard"))
        assertNull(MultiviewLut.conversion("Dolby Vision"))
        // The tile grades from Live View's color: a photo previews Rec.709 even in I-Log.
        val iLog = CameraStatus(colorMode = CameraCommands.COLOR_ILOG)
        assertEquals(iLog.monitorColorMode, MultiviewLut.previewColorMode(iLog))
        val photo = iLog.copy(shootingMode = 0x05)
        assertEquals(CameraCommands.COLOR_NORMAL, MultiviewLut.previewColorMode(photo))
    }

    @Test fun tileReadoutsAreLiveViewsWords() {
        val status = CameraStatus(iso = 400, shutterDenom = 50, wbMode = CameraCommands.WB_AUTO, fps = 25, colorMode = CameraCommands.COLOR_ILOG)
        val readings = MultiviewTileValues.readings(luna, status, snapshot = null, hasPicture = true)
        assertEquals("Luna A1B2", readings.name)
        assertEquals("Insta360 Luna Ultra", readings.model)
        assertEquals(
            listOf(MultiviewReadout("ISO", "400"), MultiviewReadout("SHUTTER", "1/50"), MultiviewReadout("WB", "Auto"), MultiviewReadout("FOCUS", status.focusLabel)),
            readings.readouts,
        )
        assertTrue(readings.format, readings.format.contains("25p"))
        assertEquals(MultiviewTally.UNAVAILABLE, readings.storage)
        assertEquals("Live", readings.accessibilityValue)
        assertEquals("Reconnecting", MultiviewTileValues.readings(luna, status, null, hasPicture = false).accessibilityValue)
        // Unknown is a dash, never a guess.
        val unknown = MultiviewTileValues.readings(luna, CameraStatus(), null, hasPicture = false)
        assertEquals(listOf("\u2014", "\u2014"), unknown.readouts.take(2).map { it.value })
        assertEquals("\u2014 \u2014 · \u2014", unknown.format)
    }

    @Test fun everySettingsCategoryHasLiveViewsSheet() {
        for (category in MultiviewSettingsCategory.entries) assertNotNull(category.name, category.liveSheet)
    }

    @Test fun multiviewDoesNotOpenDuringAConnectAttempt() {
        assertTrue(AppModel.opensMultiview(offered = true, open = false, borrowed = false, attempts = 0))
        assertFalse(AppModel.opensMultiview(offered = true, open = false, borrowed = false, attempts = 1))
        assertFalse(AppModel.opensMultiview(offered = true, open = true, borrowed = false, attempts = 0))
        assertFalse(AppModel.opensMultiview(offered = false, open = false, borrowed = false, attempts = 0))
        assertFalse(AppModel.opensMultiview(offered = true, open = false, borrowed = true, attempts = 0))
    }

    @Test fun theMonitorNeverRedialsUnderAnOpenStage() {
        assertTrue(AppModel.resumesConnections(borrowed = false, staged = false))
        // The stage's system Wi-Fi join prompt pauses and resumes the activity: no retry then.
        assertFalse(AppModel.resumesConnections(borrowed = false, staged = true))
        assertFalse(AppModel.resumesConnections(borrowed = true, staged = false))
    }

    /** Source rules for what only a device exercises: no unit test can reach these Android paths. */
    @Test fun theHostKeepsPocketsOwnershipRules() {
        val root = File("src/main/kotlin/com/opencapture/openinstacine/monitor")
        val session = File(root, "multiview/MultiviewSession.kt").readText()
        val views = File(root, "multiview/MultiviewTileViews.kt").readText()
        // Closing the stage lets go of the shared Wi-Fi it joined (Pocket `path.release()`).
        assertTrue(session.substringAfter("override fun close()").contains("path.release()"))
        // The decoder's surface is handed back when the picture size arrives (black-tile fix).
        assertTrue(views.contains("tile.pictureSizeChanged()"))
        assertTrue(session.contains("handedSurface?.let(session.decoder::attachSurface)"))
        // The settings preview reads the tile's own GL tap, never a second decoder surface.
        assertFalse(views.substringAfter("fun MultiviewSettingsPreview").substringBefore("\n}\n").contains("attachSurface"))
        // A borrowed model never closes the tile's session.
        val model = File(root, "AppModel.kt").readText().substringAfter("override fun close()").substringBefore("\n    }\n")
        assertTrue(model.indexOf("if (isBorrowed)") in 0 until model.indexOf("session.close()"))
    }
}
