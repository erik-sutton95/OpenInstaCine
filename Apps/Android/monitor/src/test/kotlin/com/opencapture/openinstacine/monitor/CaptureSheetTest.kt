package com.opencapture.openinstacine.monitor

import com.opencapture.opencine.cameracontrols.LiveViewLink
import com.opencapture.openinstacine.monitor.session.vocabularyPhase
import kotlin.test.Test
import kotlin.test.assertEquals

class CaptureSheetTest {
    @Test
    fun everyShellPhaseIsTheSameVocabularyPhase() {
        for (phase in com.opencapture.opencine.insta360.shell.ConnectionPhase.entries) {
            assertEquals(phase.name, phase.vocabularyPhase().name)
        }
    }

    @Test
    fun fpsChipLabelIsLiveViewHealthNotRecordFps() {
        data class Chip(
            val why: String,
            val connection: com.opencapture.opencine.insta360.shell.ConnectionPhase,
            val recovering: Boolean,
            val measured: Double,
            val expected: String,
        )
        val live = com.opencapture.opencine.insta360.shell.ConnectionPhase.LIVE
        val cases = listOf(
            Chip("idle hides fps", com.opencapture.opencine.insta360.shell.ConnectionPhase.IDLE, false, 0.0, "\u2014"),
            Chip("live without frames", live, false, 0.0, "LINK"),
            Chip("recovering", live, true, 12.0, "RECOV"),
            Chip("failed", com.opencapture.opencine.insta360.shell.ConnectionPhase.FAILED, false, 25.0, "FAIL"),
            Chip("live with frames", live, false, 25.0, "25.00"),
        )
        for (case in cases) {
            assertEquals(
                case.expected,
                LiveViewLink.fpsChipLabel(
                    connection = case.connection.vocabularyPhase(),
                    recovering = case.recovering,
                    formattedFPS = "25.00",
                    measuredFPS = case.measured,
                ),
                case.why,
            )
        }
    }
}
