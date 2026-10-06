package com.opencapture.openpocketcine.session

import com.opencapture.opencine.media.ExtraMirrorHold
import com.opencapture.opencine.media.FeedPresentPolicy
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraModel
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.ControlHud
import com.opencapture.opencine.vocabulary.FormatPin
import com.opencapture.opencine.vocabulary.ShutterAngle
import com.opencapture.opencine.vocabulary.VideoAspect
import com.opencapture.opencine.vocabulary.VideoFormat
import com.opencapture.opencine.vocabulary.VideoFrameRate
import com.opencapture.opencine.vocabulary.VideoResolution
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CameraControlTest {
    @Test
    fun emptyCapabilityPortraitKeepsReportedResolution() {
        val current = VideoFormat(VideoResolution.P3K_9X16, VideoFrameRate.FPS25)
        val formats = VideoFormat.pickerFormats(emptyList(), CameraModel("Osmo Pocket 3"), -1)
        val aspects = VideoFormat.aspects(formats, current.resolution.aspect)
        val resolutions = VideoFormat.resolutions(
            formats, current.resolution,
            if (aspects.size > 1) VideoAspect.NINE_SIXTEEN else null,
        )
        assertEquals(listOf(VideoResolution.P3K_9X16), resolutions)
        assertEquals(listOf("3K"), resolutions.map { it.tabTitle })
    }

    @Test
    fun emptyCapabilityPreservesReportedSizesWithoutInventingAnAspect() {
        for (current in listOf(
            VideoResolution.P3K_1X1, VideoResolution.P2_7K,
            VideoResolution.P4K_4X3, VideoResolution(0xFE),
        )) {
            assertEquals(listOf(current), VideoFormat.resolutions(emptyList(), current))
        }
        assertEquals(listOf(VideoResolution.P1080, VideoResolution.P4K), VideoFormat.resolutions(emptyList(), null))
        assertTrue(VideoFormat.resolutions(emptyList(), VideoResolution.P3K_9X16, VideoAspect.SIXTEEN_NINE).isEmpty())
    }

    @Test
    fun pocket3PickerFallbackIncludesNormalVideoSizesOnly() {
        val model = CameraModel(name = "Osmo Pocket 3")
        val formats = VideoFormat.pickerFormats(emptyList(), model, CameraCommands.SHOOT_VIDEO)
        assertTrue(VideoFormat.resolutions(formats, VideoResolution.P4K, VideoAspect.SIXTEEN_NINE).contains(VideoResolution.P2_7K))
        assertTrue(VideoFormat.resolutions(formats, null, VideoAspect.ONE_ONE).contains(VideoResolution.P3K_1X1))
        assertTrue(formats.none { it.resolution.aspect == VideoAspect.NINE_SIXTEEN })
        assertTrue(
            !VideoFormat.allowsOperatorSet(
                VideoFormat(VideoResolution.P3K_9X16, VideoFrameRate.FPS25),
                emptyList(),
                model,
                CameraCommands.SHOOT_VIDEO,
            ),
        )
        assertTrue(!VideoFormat.aspects(formats, null).contains(VideoAspect.FOUR_THREE))
        val reported = listOf(VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS25))
        assertEquals(reported, VideoFormat.pickerFormats(reported, model, 1))
        for (mode in listOf(-1, 2, 26)) {
            assertTrue(VideoFormat.pickerFormats(emptyList(), model, mode).isEmpty())
        }
        for (name in listOf("Osmo Pocket 4 Pro", "Osmo Nano", "Unknown")) {
            assertTrue(VideoFormat.pickerFormats(emptyList(), CameraModel(name), 1).isEmpty())
        }
    }

    @Test
    fun isoStepsSkipAutoAndStopAtEnds() {
        assertEquals(0x04, CameraCommands.isoStepped(0x03, 1, CameraCommands.ISO_INDEX_ALL))
        assertNull(CameraCommands.isoStepped(0x0B, 1, CameraCommands.ISO_INDEX_ALL))
        assertNull(CameraCommands.isoStepped(0x00, 1, CameraCommands.ISO_INDEX_ALL))
        assertEquals(0x04, CameraCommands.isoStepped(0x05, -1, listOf(0x04, 0x05, 0x06)))
    }

    @Test
    fun shutterStepsOpenTowardSlower() {
        val denoms = listOf(16_000, 8_000, 100, 50, 25, 4)
        assertEquals(25, CameraCommands.shutterSteppedDenom(50, 1, denoms))
        assertEquals(100, CameraCommands.shutterSteppedDenom(50, -1, denoms))
        assertNull(CameraCommands.shutterSteppedDenom(16_000, -1, denoms))
        assertNull(CameraCommands.shutterSteppedDenom(4, 1, denoms))
        assertEquals(25, CameraCommands.shutterSteppedDenom(48, 1, denoms))
    }

    @Test
    fun whiteBalanceCustomClampMatchesIos() {
        assertEquals(2_000 to 0, CameraCommands.clampWhiteBalanceCustom(1999, 0))
        assertEquals(10_000 to 100, CameraCommands.clampWhiteBalanceCustom(12_000, 140))
        assertEquals(5_600 to -100, CameraCommands.clampWhiteBalanceCustom(5_600, -140))
        val extra = CameraCommands.clampWhiteBalanceCustom(3200, -5)
        assertEquals("3200\u001f-5", "${extra.first}\u001f${extra.second}")
    }

    @Test
    fun videoFormatParsesHighRateRawAndDrumLabels() {
        assertEquals(
            VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS120),
            VideoFormat.parse(CameraCommands.RES_4K, 7),
        )
        assertEquals(VideoResolution.P1080_4X3, VideoResolution.fromRaw(0x0C))
        assertEquals(VideoFrameRate.FPS120, VideoFrameRate.fromDrumLabel("120p"))
    }

    @Test
    fun formatPinHoldsOptimisticUntilSubscribeMatches() {
        val expected = VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS25)
        val pin = FormatPin(expected, deadlineElapsedRealtime = 2_000L)
        val stale =
            CameraStatus(
                fps = 24,
                resolutionCode = CameraCommands.RES_1080,
                fpsIndex = 1,
            )
        val held = VideoFormat.absorbStale(stale, pin, nowElapsedRealtime = 500L)
        assertEquals(CameraCommands.RES_4K, held.first.resolutionCode)
        assertEquals(2, held.first.fpsIndex)
        assertEquals(25, held.first.fps)
        assertEquals(pin, held.second)
        val matched =
            VideoFormat.absorbStale(
                CameraStatus(fps = 25, resolutionCode = CameraCommands.RES_4K, fpsIndex = 2),
                pin,
                nowElapsedRealtime = 500L,
            )
        assertNull(matched.second)
        assertEquals(25, matched.first.fps)
        val expired = VideoFormat.absorbStale(stale, pin, nowElapsedRealtime = 2_000L)
        assertNull(expired.second)
        assertEquals(CameraCommands.RES_1080, expired.first.resolutionCode)
        val optimistic =
            CameraStatus(
                fps = 25,
                resolutionCode = CameraCommands.RES_4K,
                fpsIndex = 2,
            )
        val copy =
            VideoFormat.absorbStale(
                optimistic,
                pin,
                nowElapsedRealtime = 500L,
                formatReported = false,
            )
        assertEquals(pin, copy.second)
        assertEquals(CameraCommands.RES_4K, copy.first.resolutionCode)
        assertEquals(2, copy.first.fpsIndex)
    }

    @Test
    fun extraMirrorHoldsThreePresentsThenCommits() {
        assertTrue(FeedPresentPolicy.shouldHoldPictureAcrossMirror(1, 0.04))
        assertTrue(FeedPresentPolicy.shouldHoldPictureAcrossMirror(3, 0.12))
        assertTrue(!FeedPresentPolicy.shouldHoldPictureAcrossMirror(4, 0.16))
        assertTrue(!FeedPresentPolicy.shouldHoldPictureAcrossMirror(1, 0.2))
        val hold = ExtraMirrorHold()
        assertEquals(ExtraMirrorHold.Step.COMMIT, hold.step(false, 0.0).step)
        assertEquals(ExtraMirrorHold.Step.UNCHANGED, hold.step(false, 0.04).step)
        assertEquals(ExtraMirrorHold.Step.HOLD, hold.step(true, 0.08).step)
        assertEquals(ExtraMirrorHold.Step.HOLD, hold.step(true, 0.12).step)
        assertEquals(ExtraMirrorHold.Step.HOLD, hold.step(true, 0.16).step)
        val commit = hold.step(true, 0.20)
        assertEquals(ExtraMirrorHold.Step.COMMIT, commit.step)
        assertEquals(true, commit.mirrored)
        hold.reset()
        assertEquals(ExtraMirrorHold.Step.COMMIT, hold.step(true, 1.0).step)
    }

    @Test
    fun emptyShutterCapUsesDocumentedVideoLadder() {
        val wheel = CameraCommands.shutterWheelDenoms(emptyList(), 60)
        assertTrue(wheel.contains(60))
        assertTrue(wheel.contains(50))
        assertTrue(wheel.contains(48))
        assertTrue(wheel.contains(8000))
        assertEquals(8000, wheel.first())
        assertEquals(48, ShutterAngle.denom(180.0, 24, wheel))
        val withOdd = CameraCommands.shutterWheelDenoms(emptyList(), 80)
        assertTrue(withOdd.contains(80))
        assertTrue(withOdd.contains(100))
    }

    @Test
    fun controlHudTimeoutStaysOffTheHudLikeIos() {
        assertEquals(null, ControlHud.timeoutNote("Color", announce = false))
        assertEquals(null, ControlHud.timeoutNote("ISO limit GET", announce = false))
        assertEquals(null, ControlHud.timeoutNote("Audio ch GET", announce = false))
        assertEquals("Color timed out", ControlHud.timeoutNote("Color", announce = true))
        assertEquals("ISO limit GET timed out", ControlHud.timeoutNote("ISO limit GET", announce = true))
        assertEquals(222.0, ControlHud.toastCenterY(200.0))
        assertEquals(82.0, ControlHud.toastCenterY(0.0, 60.0))
        assertEquals(222.0, ControlHud.toastCenterY(200.0, null))
        assertEquals(72.0, ControlHud.toastCenterY(50.0, 50.0))
        assertEquals(72.0, ControlHud.toastCenterY(50.0, 40.0))
        assertTrue(!ControlHud.RECORDING_COLOR_LOCK_NOTE.contains("0x"))
    }

    companion object {
        private const val SHUTTER_25P =
            "016d000002000101001e00052180be00409f00009900889300a08f00808c00c48900d08700408600e28400e88300208300808200f48100908100408100f08000c88000a080007880006480005080003c80003280002880001e80001980000c80000a8000088000068000058000048000"
        private const val SHUTTER_60P =
            "0164000002000101001e00051e80be00409f00009900889300a08f00808c00c48900d08700408600e28400e88300208300808200f48100908100408100f08000c88000a080007880006480005080003c80003280000c80000a8000088000068000058000048000"

        private fun hex(s: String): ByteArray {
            return ByteArray(s.length / 2) { i ->
                s.substring(i * 2, i * 2 + 2).toInt(16).toByte()
            }
        }
    }
}
