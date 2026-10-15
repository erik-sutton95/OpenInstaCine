package com.opencapture.openinstacine.monitor.pairing

import com.opencapture.opencine.appkit.NearbyCardCopy
import com.opencapture.opencine.appkit.PairingWizard
import com.opencapture.opencine.core.NearbyCamera
import com.opencapture.opencine.core.RouteKind
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import com.opencapture.openinstacine.monitor.AppModel
import com.opencapture.openinstacine.monitor.pairingWizard
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** The pair page and nearby cards in the words this app's main showed (PairingExperience, NearbyCameraRow). */
class PairingWizardCopyTest {
    private fun wizard(granted: Boolean = true, needsSettings: Boolean = false, radioOn: Boolean = true) =
        pairingWizard("label", null, vpnActive = false, granted = granted, needsSettings = needsSettings, radioOn = radioOn)

    @Test
    fun theWizardKeepsTheLunaPages() {
        val wizard = wizard()
        assertEquals(
            listOf(
                "Turn the Luna on and keep this phone nearby. It shows up by the last characters of its serial number.",
                "If the camera asks to allow this phone, tap Allow on its screen. First-time pairing can wait up to 90 seconds.",
                "We read the camera's Wi-Fi over Bluetooth, then join it for you.",
                "Exposure, LUTs and scopes go live as soon as the video link is up.",
            ),
            wizard.bodies,
        )
        // A4-44: the Luna's own lines (iOS CamerasExperience), not the Pocket's Approve prompt and 5.8 GHz wait.
        assertEquals(listOf("Look for the connection request", "Tap Allow on the camera screen"), wizard.approveLines)
        assertEquals(
            listOf("Leave the camera on. It brings up its own 5 GHz Wi-Fi", "Close the Insta360 app on other phones so the camera is free"),
            wizard.joinLines,
        )
        assertEquals(null, wizard.blocker)
    }

    @Test
    fun discoveryBlockersTakeThePrimaryAction() {
        assertEquals("Open Settings", wizard(granted = false, needsSettings = true).blocker)
        assertTrue(wizard(granted = false).blocker!!.startsWith("Allow "))
        assertEquals("Turn Bluetooth on", wizard(radioOn = false).blocker)
    }

    @Test
    fun theLiveLabelIsThePhase() {
        assertEquals("Scanning for camera…", PairingWizard.phaseLabel(ConnectionPhase.SCANNING))
        assertEquals("Approve on the camera screen", PairingWizard.phaseLabel(ConnectionPhase.AWAITING_APPROVAL))
        assertEquals("Joining camera Wi-Fi…", PairingWizard.phaseLabel(ConnectionPhase.JOINING_WIFI))
        assertEquals("Opening datalink…", PairingWizard.phaseLabel(ConnectionPhase.OPENING_DATALINK))
    }

    @Test
    fun nearbyCardsReadAsTheIPhoneApp() {
        val camera = NearbyCamera("n1", name = "Luna Ultra 1A2B", model = "Luna Ultra", routes = setOf(RouteKind.CAMERA_ACCESS_POINT))
        assertEquals(
            NearbyCardCopy("Luna Ultra 1A2B", "Insta360 · nearby", "Needs approval on the camera"),
            AppModel.nearbyCard(camera),
        )
    }
}
