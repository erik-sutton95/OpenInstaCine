package com.opencapture.openpocketcine.session

import com.opencapture.openpocketcine.ShutterAngle
import com.opencapture.opencine.media.ExtraMirrorHold
import com.opencapture.opencine.media.FeedPresentPolicy
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
    fun camcapVideoFormatKeepsNano27KAnd4by3() {
        val blob =
            byteArrayOf(
                0x01, 0x07, 0x00, 0x02,
                0x2D, 0x01, 0x00,
                0x67, 0x05, 0x00,
            )
        val formats = CameraCommands.parseVideoFormats(blob)
        assertEquals(2, formats.size)
        assertTrue(formats.contains(VideoFormat(VideoResolution.P2_7K, VideoFrameRate.FPS24)))
        assertTrue(formats.contains(VideoFormat(VideoResolution.P4K_4X3, VideoFrameRate.FPS50)))
        assertEquals(
            listOf(VideoAspect.SIXTEEN_NINE, VideoAspect.FOUR_THREE),
            VideoFormat.aspects(formats, null),
        )
        assertEquals(
            listOf(VideoResolution.P1080, VideoResolution.P4K),
            VideoFormat.resolutions(emptyList(), VideoResolution.P4K),
        )
    }

    @Test
    fun zoomPinAndColorModesFollowTheBody() {
        val pro = CameraModel(name = "Osmo Pocket 4 Pro", family = "pocket")
        val pocket4 = CameraModel(name = "Osmo Pocket 4", family = "pocket")
        val pocket3 = CameraModel(name = "Osmo Pocket 3", family = "pocket")
        // activeZoomStops, ceilingNote, stopWithinCycle and pocket3ZoomMax are
        // covered row by row in camfov-vectors.tsv (CamFovVectorTest).
        // The chip rides the same pin as every other control, with
        // CamFov::matches standing in for equality.
        fun held(ask: Double, live: Double?, ageMs: Long): Double? =
            CameraValuePin.reconcile(
                CameraValuePin(ask, CameraValuePin.SETTLE_MS),
                live,
                ageMs,
                CamFov::matches,
            ).first
        // Fresh ask: the chip holds the target through the round trip.
        assertEquals(3.0, held(3.0, 1.0, 0L))
        assertEquals(3.0, held(3.0, null, 0L))
        // Body confirmed — the pin has done its job, live takes over.
        assertNull(held(3.0, 3.0, 0L))
        assertNull(held(3.0, 2.97, 0L))
        // Body clamped, or moved the lens on its own (a FORMAT change resets to
        // 1×). It never reports 3×, so only the deadline can free the chip.
        assertNull(held(3.0, 1.0, CameraValuePin.SETTLE_MS))
        assertNull(held(4.0, 2.0, 5_000L))
        assertNull(held(3.0, null, 5_000L))
        // A pin that outlived its ask must not win the readout.
        assertEquals(1.0, CamFov.readout(live = 1.0, preview = null, fallback = 3.0))
        assertEquals(
            listOf(
                CameraCommands.COLOR_NORMAL,
                CameraCommands.COLOR_HDR,
                CameraCommands.COLOR_DLOG,
                CameraCommands.COLOR_DLOG2,
            ),
            CameraModel.colorModesFor(pro.name, "pocket"),
        )
        assertEquals(
            listOf(
                CameraCommands.COLOR_NORMAL,
                CameraCommands.COLOR_HDR,
                CameraCommands.COLOR_DLOG,
            ),
            CameraModel.colorModesFor(pocket4.name, "pocket"),
        )
        assertEquals(
            listOf(
                CameraCommands.COLOR_NORMAL,
                CameraCommands.COLOR_HDR,
                CameraCommands.COLOR_DLOG_M,
            ),
            CameraModel.colorModesFor(pocket3.name, "pocket"),
        )
        assertTrue(CameraCommands.COLOR_DLOG2 !in CameraModel.colorModesFor(pocket3.name, "pocket"))
        assertTrue(CameraCommands.COLOR_DLOG !in CameraModel.colorModesFor(pocket3.name, "pocket"))
        assertTrue(
            CameraCommands.COLOR_DLOG2 in CameraModel.colorModesFor("OsmoPocket4P-ABCD", "pocket"),
        )
        assertTrue(
            CameraCommands.COLOR_DLOG2 !in CameraModel.colorModesFor("OsmoPocket4-ABCD", "pocket"),
        )
        assertEquals(
            listOf(
                CameraCommands.COLOR_NORMAL,
                CameraCommands.COLOR_HDR,
                CameraCommands.COLOR_DLOG_M,
            ),
            CameraModel.colorModesFor("OsmoPocket3-ABCD", "pocket"),
        )
        val fromJson =
            CameraModel.fromJson(
                """{"name":"OsmoPocket4P-ABCD","family":"pocket","zoomStops":[1,3,6,12]}""",
            )
        assertEquals(listOf(1.0, 3.0, 6.0, 12.0), fromJson.zoomStops)
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
    fun statusJsonRoundTripsHudFields() {
        val src =
            CameraStatus(
                iso = 400,
                shutterDenom = 50,
                fps = 24,
                expoMode = CameraCommands.EXPO_MANUAL,
                isoIndex = 0x05,
                colorMode = CameraCommands.COLOR_DLOG,
                resolutionCode = CameraCommands.RES_4K,
                fpsIndex = 1,
                wbMode = CameraCommands.WB_CUSTOM,
                wbKelvin = 5600,
                wbTint = -5,
                focusMode = CameraCommands.FOCUS_CONTINUOUS,
                audioChannel = CameraCommands.AUDIO_STEREO,
                vocalBoost = 1,
                audioDspBlob = "c0041a0500" + "00".repeat(21),
                audioDspAt2 = CameraCommands.WIND_ON,
            )
        val decoded = CameraStatus.fromJson(src.toJson())
        assertEquals(400, decoded.iso)
        assertEquals(50, decoded.shutterDenom)
        assertEquals(24, decoded.fps)
        assertEquals(CameraCommands.EXPO_MANUAL, decoded.expoMode)
        assertEquals(0x05, decoded.isoIndex)
        assertEquals(CameraCommands.COLOR_DLOG, decoded.colorMode)
        assertEquals(CameraCommands.RES_4K, decoded.resolutionCode)
        assertEquals(5600, decoded.wbKelvin)
        assertEquals(-5, decoded.wbTint)
        assertEquals(CameraCommands.FOCUS_CONTINUOUS, decoded.focusMode)
        assertEquals(CameraCommands.AUDIO_STEREO, decoded.audioChannel)
        assertEquals(1, decoded.vocalBoost)
        assertEquals(1, decoded.windNr)
        assertTrue(decoded.audioDspBlob.startsWith("c0041a"))
        val selfie = CameraStatus(gimbalFace = CameraCommands.GIMBAL_FACE_SELFIE)
        assertEquals(
            CameraCommands.GIMBAL_FACE_SELFIE,
            CameraStatus.fromJson(selfie.toJson()).gimbalFace,
        )
        assertEquals(
            CameraCommands.GIMBAL_FACE_UNKNOWN,
            CameraStatus.fromJson("{}").gimbalFace,
        )
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
    fun expoModeWireExtraAndWaitKeyMatchIos() {
        assertEquals("auto", CameraCommands.expoWireExtra(CameraCommands.EXPO_AUTO))
        assertEquals("manual", CameraCommands.expoWireExtra(CameraCommands.EXPO_MANUAL))
        assertEquals(null, CameraCommands.expoWireExtra(-1))
    }

    @Test
    fun camcapShutterTwentyFivePDiffersFromSixtyP() {
        val p25 = CameraCommands.parseShutterDenoms(hex(SHUTTER_25P))
        val p60 = CameraCommands.parseShutterDenoms(hex(SHUTTER_60P))
        assertTrue(p25.contains(25))
        assertTrue(p25.contains(50))
        assertTrue(p60.contains(50))
        assertTrue(!p60.contains(25))
        assertTrue(p25 != p60)
        val wheel = CameraCommands.shutterWheelDenoms(p60, 48)
        assertEquals(p60, wheel)
        assertTrue(!wheel.contains(48))
        assertTrue(!wheel.contains(13))
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
    fun dLogStars400AndDLog2Stars1600() {
        val dlog2 = CameraCommands.parseIsoIndices(hex("0108000006030405060708"))
        assertEquals(listOf(0x03, 0x04, 0x05, 0x06, 0x07, 0x08), dlog2)
        assertEquals("400", CameraCommands.baseIsoLabel(CameraCommands.COLOR_DLOG))
        assertEquals("1600", CameraCommands.baseIsoLabel(CameraCommands.COLOR_DLOG2))
        assertEquals(null, CameraCommands.baseIsoLabel(CameraCommands.COLOR_NORMAL))
        assertEquals(null, CameraCommands.baseIsoLabel(CameraCommands.COLOR_HDR))
        assertEquals(null, CameraCommands.baseIsoLabel(-1))
        assertTrue(dlog2.contains(0x05))
        assertTrue(dlog2.contains(0x07))
        assertEquals("400", CameraCommands.isoLabel(0x05))
        assertEquals("1600", CameraCommands.isoLabel(0x07))
        val withJunk = CameraCommands.parseIsoIndices(hex("0109000007030405060708ff"))
        assertEquals(listOf(0x03, 0x04, 0x05, 0x06, 0x07, 0x08), withJunk)
        assertTrue(!withJunk.contains(0xFF))
        val autoOnly = CameraCommands.parseIsoIndices(hex("010300000100"))
        assertEquals(listOf(0x00), autoOnly)
        assertEquals("400", CameraCommands.markedIsoLabel(CameraCommands.COLOR_DLOG_M))
        assertEquals(null, CameraCommands.baseIsoLabel(CameraCommands.COLOR_DLOG_M))
        assertEquals(
            CameraCommands.COLOR_DLOG,
            CameraCommands.colorModeForZoom(3.0, CameraCommands.COLOR_DLOG2),
        )
        assertEquals(
            CameraCommands.COLOR_DLOG,
            CameraCommands.colorModeForZoom(1.1, CameraCommands.COLOR_DLOG2),
        )
        assertEquals(null, CameraCommands.colorModeForZoom(1.0, CameraCommands.COLOR_DLOG2))
        assertEquals(null, CameraCommands.colorModeForZoom(3.0, CameraCommands.COLOR_DLOG))
        assertTrue(CameraCommands.shouldRestoreDLog2(1.0))
        assertTrue(!CameraCommands.shouldRestoreDLog2(2.9))
        assertTrue(!CameraCommands.shouldRestoreDLog2(3.0))
    }

    @Test
    fun colorModeWireBytesMatchIos() {
        // The byte the core packs for `CMD_SET_COLOR_MODE`, per body.
        val cases = listOf(
            Triple(CameraCommands.COLOR_NORMAL, "", 0x3F),
            Triple(CameraCommands.COLOR_HDR, "", 0x3C),
            Triple(CameraCommands.COLOR_DLOG, "", 0x17),
            Triple(CameraCommands.COLOR_DLOG2, "", 0x41),
            Triple(CameraCommands.COLOR_NORMAL10, "", 0x3D),
            Triple(CameraCommands.COLOR_DLOG_M, "", 0x00),
            Triple(CameraCommands.COLOR_NORMAL, "Osmo Pocket 3", 0x00),
            Triple(CameraCommands.COLOR_DLOG_M, "Osmo Pocket 3", 0x3D),
            Triple(CameraCommands.COLOR_HDR, "Osmo Pocket 3", 0x3C),
            Triple(CameraCommands.COLOR_NORMAL, "Xtra Muse", 0x00),
            Triple(CameraCommands.COLOR_NORMAL, "Osmo Pocket 4", 0x3F),
            Triple(CameraCommands.COLOR_NORMAL, "Osmo Nano", 0x00),
            Triple(CameraCommands.COLOR_NORMAL10, "Osmo Nano", 0x3F),
            Triple(CameraCommands.COLOR_DLOG_M, "Osmo Nano", 0x3D),
        )
        for ((mode, body, wire) in cases) {
            assertEquals(wire, CameraCommands.wireColorMode(mode, body), "mode $mode on '$body'")
        }
    }

    @Test
    fun statusJsonRoundTripsParityFields() {
        val src =
            CameraStatus(
                evComp = 0x10,
                isoLimit = 0x07,
                availableColorModes = listOf(0x3F, 0x3C),
                focusX = 0.25,
                focusY = 0.75,
                hasCameraFocusPoint = true,
                focusTrack = 2,
                zoomLens = 217,
                zoomFactor = 1.0,
                glamourEnabled = false,
                selfieFlip = true,
                windNr = 1,
                directionalAudio = 0,
                audioMetersLeft = -12.0,
                audioMetersRight = -14.0,
                audioPeakLeft = -6.0,
                audioPeakRight = -8.0,
            )
        val json = src.toJson()
        assertTrue(json.contains("\"windNR\":"))
        assertTrue(json.contains("\"evComp\":16"))
        val decoded = CameraStatus.fromJson(json)
        assertEquals(0x10, decoded.evComp)
        assertEquals(0x07, decoded.isoLimit)
        assertEquals(listOf(0x3F, 0x3C), decoded.availableColorModes)
        assertEquals(0.25, decoded.focusX, 1e-6)
        assertEquals(0.75, decoded.focusY, 1e-6)
        assertEquals(true, decoded.hasCameraFocusPoint)
        assertEquals(2, decoded.focusTrack)
        assertEquals(217, decoded.zoomLens)
        assertEquals(1.0, decoded.zoomFactor ?: 0.0, 1e-6)
        assertEquals(false as Boolean?, decoded.glamourEnabled)
        assertEquals(true as Boolean?, decoded.selfieFlip)
        assertEquals(1, decoded.windNr)
        assertEquals(0, decoded.directionalAudio)
        assertEquals(-12.0, decoded.audioMetersLeft, 1e-6)
        assertEquals(-14.0, decoded.audioMetersRight, 1e-6)
        assertEquals(-6.0, decoded.audioPeakLeft, 1e-6)
        assertEquals(-8.0, decoded.audioPeakRight, 1e-6)
    }

    @Test
    fun statusJsonParsesCoreWindAndDirectionalRaws() {
        val json =
            """{"windNR":26,"directionalAudio":218,"evComp":16,"zoomLens":651,"zoomFactor":3.0,"glamourEnabled":true}"""
        val decoded = CameraStatus.fromJson(json)
        assertEquals(1, decoded.windNr)
        assertEquals(0, decoded.directionalAudio)
        assertEquals(0x10, decoded.evComp)
        assertEquals(651, decoded.zoomLens)
        assertEquals(3.0, decoded.zoomFactor ?: 0.0, 1e-6)
        assertEquals(true as Boolean?, decoded.glamourEnabled)
    }

    @Test
    fun cameraModelJsonUsesPocketDefaults() {
        val parsed =
            CameraModel.fromJson(
                """{"name":"Osmo Pocket 4","datalinkPort":9004,"tcpPoke":true,"wpa3":false,"verified":true,"isDrone":false,"pairingToken":"osmo"}""",
            )
        assertEquals("pocket", parsed.family)
        assertEquals(8, parsed.liveViewEnableReceiver)
        assertEquals(false, parsed.usesNanoLiveViewGate)
        assertEquals(true, parsed.supportsTapFocus)
        assertEquals(true, parsed.supportsFocusMode)
        assertEquals(true, parsed.usesCapturedLiveEnable)
        assertEquals(false, parsed.needsFirstPictureFormatPoke)
    }

    @Test
    fun cameraModelJsonParsesNanoFields() {
        val parsed =
            CameraModel.fromJson(
                """{"name":"Osmo Nano","family":"nano","liveViewEnableReceiver":65,"usesNanoLiveViewGate":true,"supportsTapFocus":false,"supportsFocusMode":false,"usesCapturedLiveEnable":true}""",
            )
        assertEquals("nano", parsed.family)
        assertEquals(65, parsed.liveViewEnableReceiver)
        assertEquals(true, parsed.usesNanoLiveViewGate)
        assertEquals(false, parsed.supportsTapFocus)
        assertEquals(false, parsed.supportsFocusMode)
        assertEquals(false, parsed.needsFirstPictureFormatPoke)
    }

    @Test
    fun cameraModelJsonReadsPortableBodyCapabilities() {
        val pro = CameraModel.fromJson("""{"name":"Osmo Pocket 4 Pro","hasGimbal":true,"supportsZoom":true}""")
        assertEquals(true, pro.hasGimbal)
        assertEquals(true, pro.supportsZoom)
        val nano = CameraModel.fromJson("""{"name":"Osmo Nano","family":"nano","hasGimbal":false,"supportsZoom":false}""")
        assertEquals(false, nano.hasGimbal)
        assertEquals(false, nano.supportsZoom)
        // Missing keys fail closed rather than re-deriving from family.
        val legacy = CameraModel.fromJson("""{"name":"Osmo Pocket 4","family":"pocket"}""")
        assertEquals(false, legacy.hasGimbal)
        assertEquals(false, legacy.supportsZoom)
    }

    @Test
    fun cameraModelJsonParsesPocket3FormatPoke() {
        val parsed =
            CameraModel.fromJson(
                """{"name":"Osmo Pocket 3","family":"pocket","needsFirstPictureFormatPoke":true}""",
            )
        assertEquals(true, parsed.needsFirstPictureFormatPoke)
        val byName =
            CameraModel.fromJson(
                """{"name":"OsmoPocket3-AAAA","family":"pocket"}""",
            )
        assertEquals(true, byName.needsFirstPictureFormatPoke)
        assertEquals(true, CameraModel.looksLikePocket3("Osmo Pocket 3"))
        assertEquals(false, CameraModel.looksLikePocket3("Osmo Pocket 4"))
        assertEquals(50, CameraModel.isoAutoRangeFloorFor("Osmo Pocket 3"))
        assertEquals(50, CameraModel.isoAutoRangeFloorFor("OsmoPocket3-AAAA"))
        assertEquals(50, CameraModel.isoAutoRangeFloorFor("Xtra Muse"))
        assertEquals(50, CameraModel.isoAutoRangeFloorFor("Osmo Pocket 4"))
        assertEquals(100, CameraModel.isoAutoRangeFloorFor("Osmo Pocket 4 Pro"))
        assertEquals(100, CameraModel.isoAutoRangeFloorFor("OsmoPocket4P-AAAA"))
        assertEquals(100, CameraModel.isoAutoRangeFloorFor("DJI Osmo camera"))
        assertEquals(50, parsed.isoAutoRangeFloor)
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
