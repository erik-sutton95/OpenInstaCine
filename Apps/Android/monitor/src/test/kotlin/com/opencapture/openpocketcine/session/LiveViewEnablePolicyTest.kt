package com.opencapture.openpocketcine.session

import com.opencapture.opencine.decoder.HevcDecoder
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import com.opencapture.opencine.media.LiveAccessUnit
import com.opencapture.opencine.media.LiveVideoCodec

class LiveViewEnablePolicyTest {

    @Test
    fun prepareAfterForegroundDoesNotHoldIdr() {
        val decoder = HevcDecoder()
        decoder.prepareAfterForeground()
        assertTrue(!decoder.awaitingIdr)
    }

    @Test
    fun resetClearsIdrHoldAndPicture() {
        val decoder = HevcDecoder()
        decoder.beginIDRHold()
        assertTrue(decoder.awaitingIdr)
        decoder.reset()
        assertTrue(!decoder.awaitingIdr)
        assertTrue(!decoder.hasFormat)
        assertTrue(!decoder.hasPicture.value)
        assertTrue(!decoder.isPresentationReady)
    }

    @Test
    fun recoveryPolicyDoesNotRetryAtOneHertz() {
        val policy = SessionRecoveryPolicy.monitor
        assertEquals(SessionRecoveryDecision.Retry(0), policy.decision(0, jitter = 0.5))
        val afterFirst = policy.decision(1, jitter = 0.5)
        assertTrue(afterFirst is SessionRecoveryDecision.Retry)
        assertEquals(500L, (afterFirst as SessionRecoveryDecision.Retry).afterMs)
        val afterSecond = policy.decision(2, jitter = 0.5)
        assertEquals(1_000L, (afterSecond as SessionRecoveryDecision.Retry).afterMs)
        assertEquals(SessionRecoveryDecision.Stop, policy.decision(8, jitter = 0.5))
        assertTrue(policy.state(0) is SessionRecoveryUi.Retrying)
        assertTrue(policy.state(8) is SessionRecoveryUi.WaitingForOperator)
    }

    @Test
    fun recoveryDetailCountsAttemptsWithoutNamingSisterApps() {
        val retrying = SessionRecoveryUi.Retrying(attempt = 3, maxAttempts = 8)
        val detail = SessionRecoveryCopy.detail(retrying, "Pocket 4 Pro")
        assertTrue(detail.contains("attempt 3 of 8"))
        assertTrue(!detail.contains("OpenZCine", ignoreCase = true))
    }

    @Test
    fun dropStormPausesAfterThreeDropsInTwoMinutes() {
        val guard = SessionDropStormGuard()
        assertTrue(!guard.noteDrop(0))
        assertTrue(!guard.noteDrop(15_000))
        assertTrue(guard.noteDrop(30_000))
        assertEquals(3, guard.dropsInWindow)
        guard.reset()
        assertEquals(0, guard.dropsInWindow)
    }

    @Test
    fun hevcIdrHoldDetectsCodecFromCsd() {
        val hevcCsd = byteArrayOf(0, 0, 0, 1, 0x40, 0x01, 0, 0, 0, 1, 0x42, 0x01)
        assertEquals(LiveVideoCodec.HEVC, LiveAccessUnit.detectCodec(hevcCsd, "32,33"))
        val avcCsd = byteArrayOf(0, 0, 0, 1, 0x67, 0x42, 0, 0, 0, 1, 0x68, 0xCE.toByte())
        assertEquals(LiveVideoCodec.AVC, LiveAccessUnit.detectCodec(avcCsd, "7,8"))
        assertTrue(LiveAccessUnit.isIdrPicture("20,33,34"))
        assertTrue(LiveAccessUnit.isIdrPicture("16,6,8"))
        assertTrue(LiveAccessUnit.isIdrPicture("5,7,8"))
        assertTrue(!LiveAccessUnit.isIdrPicture("1,33,34"))
        assertTrue(!LiveAccessUnit.isIdrPicture("8"))
        assertTrue(
            LiveAccessUnit.isIdrPicture("8", byteArrayOf(0, 0, 0, 1, 0x28, 0x01)),
            "HEVC IDR_N_LP must count as IDR even if JNI summarized it as AVC PPS",
        )
    }

    @Test
    fun leftoverPFramesAndIdrNlpDoNotConfigureAsAvc() {
        // Pocket leftover GOP: TRAIL_R / AUD / SUFFIX_SEI. No VPS/SPS/PPS.
        val leftover =
            byteArrayOf(
                0, 0, 0, 1, 0x02, 0x01,
                0, 0, 0, 1, 0x46, 0x01,
                0, 0, 0, 1, 0x50, 0x01,
            )
        assertNull(LiveAccessUnit.detectCodec(leftover, "1,35,40"))
        // HEVC IDR_N_LP first byte 0x28 == AVC PPS (nal_ref_idc=1). Must wait for VPS.
        val idrNlp = byteArrayOf(0, 0, 0, 1, 0x28, 0x01)
        assertNull(LiveAccessUnit.detectCodec(idrNlp, "20"))
        assertNull(LiveAccessUnit.detectCodec(idrNlp, "8"))
        // IDR then VPS in one AU still latches HEVC from 0x40, not AVC from 0x28.
        val idrThenVps = byteArrayOf(0, 0, 0, 1, 0x28, 0x01, 0, 0, 0, 1, 0x40, 0x01)
        assertEquals(LiveVideoCodec.HEVC, LiveAccessUnit.detectCodec(idrThenVps, "20,32"))
        assertEquals(LiveVideoCodec.AVC, LiveAccessUnit.detectCodec(byteArrayOf(0, 0, 0, 1, 0x68, 0xCE.toByte()), "8"))
    }

    @Test
    fun zoomChipLensesMatchCamFovStops() {
        assertEquals(217, CameraCommands.lensForZoomFactor(1.0))
        assertEquals(CamFov.lensPosition(2.0), CameraCommands.lensForZoomFactor(2.0))
        assertEquals(651, CameraCommands.lensForZoomFactor(3.0))
        assertEquals(CamFov.lensPosition(4.0), CameraCommands.lensForZoomFactor(4.0))
        assertEquals(1302, CameraCommands.lensForZoomFactor(6.0))
        assertEquals(2604, CameraCommands.lensForZoomFactor(12.0))
        val payload = CameraCommands.zoomLens(217)
        assertEquals(0x0A, payload[0].toInt() and 0xFF)
        assertEquals(0x4E, payload[1].toInt() and 0xFF)
        assertEquals(217, (payload[2].toInt() and 0xFF) or ((payload[3].toInt() and 0xFF) shl 8))
    }
}
