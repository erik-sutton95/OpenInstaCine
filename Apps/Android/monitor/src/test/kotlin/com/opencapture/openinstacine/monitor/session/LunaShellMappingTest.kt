package com.opencapture.openinstacine.monitor.session

import com.opencapture.opencine.cameracontrols.CaptureLists
import com.opencapture.opencine.cameracontrols.captureQuickFocusControl
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.FocusOption
import com.opencapture.opencine.vocabulary.GimbalMode
import com.opencapture.opencine.vocabulary.GimbalSpeed
import com.opencapture.opencine.vocabulary.VideoFormat
import com.opencapture.opencine.vocabulary.VideoFrameRate
import com.opencapture.opencine.vocabulary.VideoResolution
import com.opencapture.opencine.vocabulary.fromColorMode

import com.opencapture.opencine.insta360.shell.CameraColorProfile
import com.opencapture.opencine.insta360.shell.CameraExposure
import com.opencapture.opencine.insta360.shell.CameraFocusMode
import com.opencapture.opencine.insta360.shell.CameraGimbalMode
import com.opencapture.opencine.insta360.shell.CameraGimbalSpeed
import com.opencapture.opencine.insta360.shell.CameraReadout
import com.opencapture.opencine.insta360.shell.CameraRecordFormat
import com.opencapture.opencine.insta360.shell.CameraShootingMode
import com.opencapture.opencine.insta360.shell.CameraStorage
import com.opencapture.openinstacine.monitor.feed.MonitorTransfer
import com.opencapture.opencine.vocabulary.MediaFile
import kotlin.test.*
import org.junit.Test

/** Port checks for iOS `LunaShellMapping`: Luna readout to the shared CameraStatus and back. */
class LunaShellMappingTest {
    @kotlin.test.Test fun actualLookProfileDeclaresOnlyTheShippedConversion() {
        val profile = LunaCameraLUTProfile.value
        kotlin.test.assertEquals("camera:insta360-luna-ilog-rec709-v2", profile.cameraLooks.single().id)
        val source = com.opencapture.opencine.vocabulary.LutLookResolver.resolve(
            com.opencapture.opencine.vocabulary.LutCatalog.AUTO, true, CameraCommands.COLOR_ILOG, profile)
        kotlin.test.assertEquals(com.opencapture.opencine.vocabulary.LutLookSource.Asset(
            "Luna_I-Log_to_Rec709_BT1886_s33_v2.cube",
            com.opencapture.opencine.media.MonitorTransfer.ILOG, "I-Log → Rec.709"), source)
        kotlin.test.assertEquals(com.opencapture.opencine.vocabulary.LutLookSource.Off,
            com.opencapture.opencine.vocabulary.LutLookResolver.resolve(
                com.opencapture.opencine.vocabulary.LutCatalog.AUTO, true, CameraCommands.COLOR_DLOG2, profile))
    }

    private val m = LunaShellMapping

    private val formats = listOf(
        CameraRecordFormat(211, 7680, 4320, 25.0), CameraRecordFormat(48, 3840, 2160, 25.0),
        CameraRecordFormat(49, 3840, 2160, 24.0), CameraRecordFormat(248, 2688, 1520, 24.0),
        CameraRecordFormat(51, 2720, 1530, 24.0), CameraRecordFormat(454, 1728, 3072, 25.0),
        CameraRecordFormat(439, 3840, 1632, 25.0), CameraRecordFormat(52, 1920, 1080, 25.0),
    )

    private val readout = CameraReadout(
        batteryPercent = 66, charging = true,
        storages = listOf(
            CameraStorage(2, true, 50_384_863_232, 50_490_900_480),
            CameraStorage(3, false, 0, 0),
        ),
        shootingMode = CameraShootingMode.VIDEO,
        videoExposure = CameraExposure(3, 400, 0.02),
        exposureBiasTenths = -3,
        whiteBalanceKelvin = 5600,
        color = CameraColorProfile.LOG,
        recordFormat = formats[1],
        recordFormats = formats,
        zoom = 2.5,
        focusMode = CameraFocusMode.CONTINUOUS, faceMetering = false,
    )

    @Test fun enumsRoundTrip() {
        for (mode in CameraShootingMode.entries) {
            val back = m.cameraShootingMode(m.shootingMode(mode))
            assertEquals(if (mode == CameraShootingMode.PANO) CameraShootingMode.PHOTO else mode, back)
        }
        for (profile in listOf(CameraColorProfile.STANDARD, CameraColorProfile.LOG, CameraColorProfile.DOLBY_VISION, CameraColorProfile.HDR)) {
            assertEquals(profile, m.colorProfile(m.colorMode(profile)))
        }
        assertEquals(CameraCommands.COLOR_NORMAL, m.colorMode(CameraColorProfile.VIVID))
        for (mode in GimbalMode.entries) assertEquals(mode, m.gimbalMode(m.cameraGimbalMode(mode)))
        assertEquals(GimbalMode.DIRECTION_LOCK, m.gimbalMode(CameraGimbalMode.FPV_VERTICAL))
        assertNull(m.gimbalMode(CameraGimbalMode.STABILIZED_VERTICAL))
        for (speed in GimbalSpeed.entries) assertEquals(speed, m.gimbalSpeed(m.cameraGimbalSpeed(speed)))
        assertEquals(GimbalSpeed.FAST, m.gimbalSpeed(CameraGimbalSpeed.SENSITIVE))
        // The I-Log color id is the monitor's I-Log transfer, so scopes and LUTs read log.
        assertEquals(MonitorTransfer.ILOG, MonitorTransfer.fromColorMode(m.colorMode(CameraColorProfile.LOG)))
        assertEquals(MonitorTransfer.REC709, MonitorTransfer.fromColorMode(CameraCommands.COLOR_DOLBY_VISION))
    }

    /** Swift `testFirmware1115GimbalModesAndSquareFormats`. */
    @Test fun firmware1115GimbalModesAndSquareFormats() {
        for (mode in GimbalMode.pickerOrder) assertEquals(mode, m.gimbalMode(m.cameraGimbalMode(mode)))
        assertEquals(CameraGimbalMode.FPV_VERTICAL, m.cameraGimbalMode(GimbalMode.DIRECTION_LOCK))
        assertNull(m.gimbalMode(CameraGimbalMode.LOCK))
        val table = m.formatTable(listOf(120L, 443L).map { CameraRecordFormat(it, if (it == 120L) 3072 else 1520, if (it == 120L) 3072 else 2688, if (it == 120L) 25.0 else 30.0) })
        val square = table.entries.first { it.value == 120L }.key
        assertEquals(VideoResolution.P3K_1X1, square.resolution)
        assertEquals("3K 1:1 · 25p", square.chipLabel)
        assertTrue(443L in table.values)
        assertEquals("FPV-V", m.gimbalModeLabels[GimbalMode.DIRECTION_LOCK])
        assertEquals(listOf(1.0, 2.0, 3.0, 6.0, 15.0), PocketCameraSession.LUNA_ZOOM_CHIPS)
    }

    @Test fun formatTableRoundTripsAndFirstValueWins() {
        val table = m.formatTable(formats)
        assertEquals(211L, table[VideoFormat(VideoResolution.P8K, VideoFrameRate.FPS25)])
        assertEquals(48L, table[VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS25)])
        // 2688x1520 and 2720x1530 are both the shared 2.7K chip; the first listed wins.
        assertEquals(248L, table[VideoFormat(VideoResolution.P2_7K, VideoFrameRate.FPS24)])
        assertEquals(454L, table[VideoFormat(VideoResolution.P3K_9X16, VideoFrameRate.FPS25)])
        assertEquals(439L, table[VideoFormat(VideoResolution.P4K_235, VideoFrameRate.FPS25)])
        for ((format, raw) in table) {
            val source = formats.first { it.id == raw }
            assertEquals(format, m.videoFormat(source), "$raw")
        }
        assertEquals("8K", VideoResolution.P8K.label)
        assertEquals("4K 2.35:1", VideoResolution.P4K_235.label)
        assertEquals("4K 9:16", VideoResolution.P4K_9X16.label)
        assertEquals("3K 9:16", m.resolution(1728, 3072).label)
        assertEquals(m.unknownResolution, m.resolution(4000, 3000))
    }

    /** iOS `testAutofocusModesMapToFocusDrum`: option 93 values 1, 3, 6 are AF-S, AF-C, Product Showcase. */
    @Test fun autofocusModesMapToFocusDrum() {
        assertEquals(listOf("AF-S", "AF-C", "Showcase"), m.focusOptions.map { it.chip })
        for (mode in CameraFocusMode.entries) assertEquals(mode, m.cameraFocusMode(m.focusOption(mode)))
        assertNull(m.cameraFocusMode(FocusOption.SUBJECT_LOCK))
        assertNull(m.cameraFocusMode(FocusOption.REGISTERED_PRIORITY))
        fun shown(s: CameraStatus) = FocusOption.resolve(s.focusMode, s.focusTrack)
        val pins = LunaControlPins()
        val showcase = readout.copy(focusMode = CameraFocusMode.PRODUCT_SHOWCASE)
        var status = m.applySettings(showcase, CameraStatus(), pins, now = 0).first
        assertEquals(FocusOption.PRODUCT_SHOWCASE, shown(status))
        // An optimistic AF-S pin holds until the camera reports it.
        pins.focus = pin(FocusOption.SINGLE, now = 0, settleMs = 3_000)
        status = m.applySettings(showcase, status, pins, now = 1_000).first
        assertEquals(FocusOption.SINGLE, shown(status))
        status = m.applySettings(readout.copy(focusMode = CameraFocusMode.SINGLE), status, pins, now = 1_500).first
        assertEquals(FocusOption.SINGLE, shown(status))
        assertNull(pins.focus)
        // Values the official app never offers read as null and blank the readout rather than guess.
        status = m.applySettings(readout.copy(focusMode = null), status, pins, now = 2_000).first
        assertNull(shown(status))
    }

        /** iOS `testTrackBoxIsCentredAndStaysInFrame`. */
    @Test fun doubleTapTrackBoxIsCentredSquareOnTheSensorAndStaysInFrame() {
        val centre = m.doubleTapTrackBox(0.5, 0.5)
        assertEquals(0.5, centre.x + centre.width / 2, 1e-9)
        assertEquals(0.5, centre.y + centre.height / 2, 1e-9)
        assertEquals(0.2, centre.width, 1e-9)
        assertEquals(centre.width * 16 / 9, centre.height, 1e-9)
        val corner = m.doubleTapTrackBox(0.99, 0.01)
        assertEquals(1.0, corner.x + corner.width, 1e-9)
        assertEquals(0.0, corner.y, 1e-9)
    }

    @Test fun settingsMapOntoSharedStatus() {
        val pins = LunaControlPins()
        val (s, table) = m.applySettings(readout, CameraStatus(shootingMode = CameraCommands.SHOOT_VIDEO), pins, now = 0)
        // ISO, WB and the exposure mode are the Core session's (CorePresentationTest); these are readouts.
        assertEquals(400, s.iso)
        assertEquals("1/50", s.shutterLabel)
        assertEquals(-1, com.opencapture.opencine.vocabulary.EvComp.fromRaw(s.evComp)?.thirds)
        assertEquals("I-Log", s.colorLabel)
        assertEquals("4K · 25p", s.recFormatLabel)
        assertEquals(25, s.fps)
        assertEquals(2.5, s.zoomFactor)
        assertEquals(CameraCommands.FOCUS_CONTINUOUS, s.focusMode)
        assertEquals(m.colorModes, s.availableColorModes)
        assertEquals(table.keys, s.availableVideoFormats.toSet())
        assertTrue(CameraCommands.ISO_160 in s.availableIsoIndices)
        assertEquals("160", CameraCommands.isoLabel(CameraCommands.ISO_160))
        assertEquals(CameraCommands.ISO_160, CameraCommands.isoIndexFromValue(160))
        assertEquals(listOf("Normal", "I-Log", "Dolby Vision"), m.colorModes.map { CameraCommands.colorLabel(it) })
        // The Luna wheel is the session profile's host value, not a camera-name branch.
        assertEquals(m.colorModes, m.profile.labels.colorModes)
        // Auto: ISO 0 and shutter 0 are the camera's choice, so no live readout.
        val auto = m.applySettings(readout.copy(videoExposure = CameraExposure(0, 0, 0.0), whiteBalanceKelvin = 0), s, pins, 0).first
        assertEquals(-1, auto.iso)
        assertEquals(-1, auto.shutterDenom)
        // Nothing read yet leaves the shared unknown state alone.
        assertEquals(CameraStatus(), m.applySettings(CameraReadout(), CameraStatus(), pins, 0).first)
    }

    @Test fun deviceStatusBatteryStorageAndMode() {
        val pins = LunaControlPins()
        val start = CameraStatus(shootingMode = CameraCommands.SHOOT_VIDEO, availableVideoFormats = listOf(VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS25)))
        val s = m.applyDevice(readout, start, pins, now = 0)
        assertEquals(66, s.batteryPercent)
        assertTrue(s.charging)
        assertEquals(50_490, s.internalTotalMb)
        assertEquals(50_384, s.storageFreeMb)
        assertEquals(0, s.sdTotalMb) // SD slot reports NOCARD
        assertEquals(start.availableVideoFormats, s.availableVideoFormats)
        // A mode change on the camera clears the previous mode's wheels.
        val photo = m.applyDevice(readout.copy(shootingMode = CameraShootingMode.PHOTO), s, pins, now = 0)
        assertEquals(CameraCommands.SHOOT_PHOTO, photo.shootingMode)
        assertTrue(photo.isPhoto)
        assertTrue(photo.availableVideoFormats.isEmpty())
        // The operator's pending mode survives a stale report.
        pins.shootingMode = pin(CameraCommands.SHOOT_SLOWMO, now = 0, settleMs = 3_000)
        val pending = m.applyDevice(readout, s.copy(shootingMode = CameraCommands.SHOOT_SLOWMO), pins, now = 1_000)
        assertEquals(CameraCommands.SHOOT_SLOWMO, pending.shootingMode)
    }

    @Test fun lunaModeLabelsAndMediaAddressing() {
        val luna = m.profile
        assertEquals("TimeShift", CameraCommands.shootingModeLabel(CameraCommands.SHOOT_HYPERLAPSE, profile = luna.labels))
        assertEquals("PureVideo", CameraCommands.shootingModeLabel(CameraCommands.SHOOT_SUPER_NIGHT, profile = luna.labels))
        assertEquals("Video", CameraCommands.shootingModeLabel(CameraCommands.SHOOT_VIDEO, profile = luna.labels))
        val path = "/storage_internal/DCIM/Camera01/VID_20260916_124229_002.mp4"
        assertEquals("http://192.168.42.1$path", luna.media.pathUrlString(0, path))
        assertEquals("20260916124229", MediaFile("/DCIM/Camera01/VID_20260916_124229_002.mp4", "").filenameTimestamp)
        assertEquals("20260814125250", MediaFile("DJI_20260814125250_0034_D.MP4", "").filenameTimestamp)
    }

    /**
     * STATE-01 gate (plan 11.2 case 12): two sessions' profiles in one process. Names, focus lists and
     * media hosts come from each session's own profile; nothing is installed globally, so using one
     * never changes what the other shows or fetches.
     */
    @Test fun twoProfilesInOneProcessKeepTheirOwnNamesAndHosts() {
        val luna = m.profile
        val dji = CameraProfile.DJI
        repeat(2) {
            assertTrue("TimeShift" in com.opencapture.opencine.cameracontrols.CaptureLists.shootingModeLabels(null, profile = luna.labels))
            assertTrue("HyperLapse" in com.opencapture.opencine.cameracontrols.CaptureLists.shootingModeLabels(null, profile = dji.labels))
            assertEquals(CameraCommands.SHOOT_HYPERLAPSE, com.opencapture.opencine.cameracontrols.CaptureLists.shootingModeRaw("TimeShift", null, luna.labels))
            assertNull(com.opencapture.opencine.cameracontrols.CaptureLists.shootingModeRaw("TimeShift", null, dji.labels))
            assertEquals("Standard", CameraCommands.colorLabel(CameraCommands.COLOR_NORMAL, profile = luna.labels))
            assertEquals("Normal", CameraCommands.colorLabel(CameraCommands.COLOR_NORMAL, profile = dji.labels))
            assertEquals("Roll Lock", GimbalMode.FOLLOW.label(luna.labels))
            assertEquals("Follow", GimbalMode.FOLLOW.label(dji.labels))
            assertEquals(listOf("AF-S", "AF-C", "Showcase"), com.opencapture.opencine.cameracontrols.captureQuickFocusControl(CameraStatus(), luna.labels.focusLabels).options)
            assertEquals(5, com.opencapture.opencine.cameracontrols.captureQuickFocusControl(CameraStatus(), dji.labels.focusLabels).options.size)
            assertEquals("http://192.168.42.1/DCIM/a.mp4", luna.media.pathUrlString(1, "/DCIM/a.mp4"))
            assertEquals("http://192.168.2.1/v2?storage=1&path=/DCIM/a.mp4", dji.media.pathUrlString(1, "/DCIM/a.mp4"))
        }
    }

    @Test fun timeOfDayTimecode() {
        val m = LunaShellMapping
        // 2026-09-30 08:51:10.54 UTC, Stockholm (UTC+2).
        val t = 1_790_758_270.54
        // Whole seconds: the phone clock never invents a frame field.
        assertEquals("10:51:10", m.timecode(t, 7200))
        // Wraps at midnight, west of GMT too.
        assertEquals("23:59:59", m.timecode(86_399.99, 0))
        assertEquals("23:00:00", m.timecode(3600.0, -7200))
    }
}
