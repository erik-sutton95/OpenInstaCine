package com.opencapture.openpocketcine.session

import com.opencapture.opencine.core.CameraValuePin
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertNotNull

class CameraDialReconciliationTest {

    @Test
    fun gimbalChoiceSurvivesOldAndPartialReportsButReleasesOnConfirmationOrExpiry() {
        val pin = CameraValuePin(GimbalMode.TILT_LOCKED, 2000)
        assertEquals(GimbalMode.TILT_LOCKED, CameraValuePin.reconcile(pin, null, 100).first)
        assertEquals(GimbalMode.TILT_LOCKED, CameraValuePin.reconcile(pin, GimbalMode.FOLLOW, 200).first)
        assertNull(CameraValuePin.reconcile(pin, GimbalMode.TILT_LOCKED, 300).second)
        assertNull(CameraValuePin.reconcile(pin, GimbalMode.FOLLOW, 2000).second)
        val speed = CameraValuePin(GimbalSpeed.SLOW, 2000)
        assertEquals(GimbalSpeed.SLOW, CameraValuePin.reconcile(speed, GimbalSpeed.FAST, 100).first)
        assertNull(CameraValuePin.reconcile(speed, GimbalSpeed.SLOW, 200).second)
    }
}
