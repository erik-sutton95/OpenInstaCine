package com.opencapture.openinstacine.monitor.session

import com.opencapture.opencine.decoder.HevcDecoder
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import com.opencapture.opencine.media.CompressedAccessUnitAdmission
import com.opencapture.opencine.media.DecoderInputOwnership
import com.opencapture.opencine.media.DecoderRandomAccessHold

class KnownReferenceLossTest {

    @Test
    fun canceledRepairWaitingForCodecLockCannotMutateANewInputLifetime() {
        for (referenceLossOnly in listOf(true, false)) {
            for (retirement in 0..2) {
                val lock = Any()
                val decoder = HevcDecoder(lock = lock)
                val owner = decoder.claimInputOwner()
                decoder.randomAccess.onIrapAccepted()
                decoder.noteReferenceDiscontinuity()
                val input = decoder.captureInputOwnership()
                val entered = CountDownLatch(1)
                val result = AtomicReference<Boolean?>()
                val worker = Thread {
                    entered.countDown()
                    result.set(decoder.rebuildPresentationIfNeeded(referenceLossOnly, input))
                }
                var generation = -1
                try {
                    synchronized(lock) {
                        worker.start()
                        assertTrue(entered.await(2, TimeUnit.SECONDS))
                        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2)
                        while (worker.state != Thread.State.BLOCKED && System.nanoTime() < deadline) Thread.sleep(1)
                        assertEquals(Thread.State.BLOCKED, worker.state, "Old repair is waiting inside codec admission")
                        // Cancellation alone cannot interrupt Java monitor entry.
                        worker.interrupt()
                        when (retirement) {
                            0 -> decoder.advanceInputEpoch(owner, input.epoch + 1)
                            1 -> decoder.claimInputOwner()
                            else -> decoder.reset()
                        }
                        decoder.randomAccess.onIrapAccepted()
                        decoder.noteReferenceDiscontinuity()
                        generation = decoder.randomAccess.generation
                    }
                    worker.join(2_000)
                    assertFalse(worker.isAlive, "Guarded mutation must finish after the codec lock releases")
                    assertEquals(false, result.get())
                    assertEquals(generation, decoder.randomAccess.generation, "Retired repair cannot replace the new codec")
                    assertTrue(decoder.referenceRecoveryNeeded, "Current loss belongs to the new owner")
                    assertTrue(decoder.rebuildPresentationIfNeeded(referenceLossOnly, decoder.captureInputOwnership()))
                } finally {
                    worker.interrupt()
                    worker.join(2_000)
                    decoder.reset()
                }
            }
        }
    }

    @Test
    fun coldDecoderIntentionalHoldAndResetDoNotInventReferenceLoss() {
        val hold = DecoderRandomAccessHold()
        hold.onNewDecoder()
        hold.noteBrokenReferences()
        assertFalse(hold.referenceRecoveryNeeded, "There were no good references to lose at startup")
        hold.onIrapAccepted()
        hold.beginHold()
        assertFalse(hold.referenceRecoveryNeeded)
        hold.onNewDecoder()
        assertFalse(hold.referenceRecoveryNeeded, "Intentional replacement is already owned")
        hold.onIrapAccepted()
        hold.noteBrokenReferences()
        assertTrue(hold.referenceRecoveryNeeded)
        hold.onNewDecoder()
        assertTrue(hold.referenceRecoveryNeeded, "Repair must retain its loss until a current IRAP")
        hold.onIrapAccepted()
        assertFalse(hold.referenceRecoveryNeeded)
        hold.noteBrokenReferences()
        hold.reset()
        assertFalse(hold.referenceRecoveryNeeded)
    }

    @Test
    fun retiredInputCannotArmOrClearTheCurrentReferenceLoss() {
        val ownership = DecoderInputOwnership(Any())
        val owner = ownership.claim()
        val hold = DecoderRandomAccessHold()
        hold.onIrapAccepted()
        ownership.advance(owner, 1)
        ownership.withCurrent(owner, 0, Unit) { hold.noteBrokenReferences() }
        assertFalse(hold.referenceRecoveryNeeded)
        ownership.withCurrent(owner, 1, Unit) { hold.noteBrokenReferences() }
        assertTrue(hold.referenceRecoveryNeeded)
        ownership.withCurrent(owner, 0, Unit) { hold.onIrapAccepted() }
        assertTrue(hold.referenceRecoveryNeeded)
        ownership.withCurrent(owner, 1, Unit) { hold.onIrapAccepted() }
        assertFalse(hold.referenceRecoveryNeeded)
    }
}
