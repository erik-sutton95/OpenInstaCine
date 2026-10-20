package com.opencapture.openinstacine.monitor.session

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** IA-366: a live picture reached outside the bounded episode clears a waiting recovery card. */
class SessionRecoveryLiveRuleTest {
    @Test
    fun aLivePictureOutsideTheEpisodeRetiresTheWaitingCard() {
        assertTrue(PocketCameraSession.retiresRecoveryOnLive(episodeRunning = false))
    }

    @Test
    fun aRunningEpisodePublishesItsOwnRecovery() {
        assertFalse(PocketCameraSession.retiresRecoveryOnLive(episodeRunning = true))
    }
}
