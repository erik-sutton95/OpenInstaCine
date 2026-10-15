package com.opencapture.openinstacine.monitor

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.opencine.core.CameraCommand
import com.opencapture.opencine.core.CameraSession
import com.opencapture.opencine.core.CameraSessionID
import com.opencapture.opencine.core.CameraSnapshot
import com.opencapture.opencine.core.CommandReceipt
import com.opencapture.opencine.core.ConnectionState
import com.opencapture.opencine.core.ControlAuthority
import com.opencapture.opencine.core.ObservationOrigin
import com.opencapture.opencine.core.ObservedValue
import com.opencapture.opencine.core.OperationID
import com.opencapture.opencine.core.RecordingState
import com.opencapture.opencine.core.SessionCloseReason
import com.opencapture.opencine.insta360.shell.CameraColorProfile
import com.opencapture.opencine.insta360.shell.CameraReadout
import com.opencapture.opencine.insta360.shell.CameraRecordFormat
import com.opencapture.opencine.insta360.shell.CameraShootingMode
import com.opencapture.openinstacine.monitor.session.PocketCameraSession
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** SIMULATED actual facade, manually completed backend requests and a manual pin clock. */
@RunWith(AndroidJUnit4::class)
class LunaNativeCapturePinTest {
    private class HeldBackend : FakeShellBackend() {
        val formats = mutableListOf<CompletableDeferred<Boolean>>()
        val colors = mutableListOf<CompletableDeferred<Boolean>>()
        val meters = mutableListOf<CompletableDeferred<Boolean>>()
        override suspend fun setRecordFormat(id: Long): Boolean =
            CompletableDeferred<Boolean>().also(formats::add).await()
        override suspend fun setColorProfile(profile: CameraColorProfile): Boolean =
            CompletableDeferred<Boolean>().also(colors::add).await()
        override suspend fun setFaceMetering(on: Boolean): Boolean =
            CompletableDeferred<Boolean>().also(meters::add).await()
    }
    private class Core : CameraSession {
        override val id = CameraSessionID()
        override val snapshots = MutableStateFlow(CameraSnapshot(id,
            connection = ConnectionState.Ready, authority = ControlAuthority.Owner,
            recording = ObservedValue(RecordingState.IDLE, ObservationOrigin.CAMERA_REPORTED, null)))
        override suspend fun submit(command: CameraCommand): CommandReceipt = error("Native controls use the actual backend")
        override suspend fun outcome(operation: OperationID): CommandReceipt? = null
        override fun receipt(operation: OperationID): CommandReceipt? = null
        override suspend fun close(reason: SessionCloseReason) = Unit
        override fun closeNow(reason: SessionCloseReason) = Unit
    }
    private val a = CameraRecordFormat(48, 3840, 2160, 25.0)
    private val b = CameraRecordFormat(49, 3840, 2160, 30.0)
    private val c = CameraRecordFormat(50, 3840, 2160, 50.0)
    private val backend = HeldBackend()
    private val core = Core()
    private lateinit var facade: PocketCameraSession
    private var now = 10_000L
    private var reported = report(a, CameraColorProfile.STANDARD)
    private fun report(format: CameraRecordFormat?, color: CameraColorProfile?) = CameraReadout(
        shootingMode = CameraShootingMode.VIDEO, recording = false,
        recordFormat = format, recordFormats = listOf(a, b, c), color = color, faceMetering = false)

    @Before fun open() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        backend.frameGeneration = 1
        backend.readout.value = reported
        MonitorConfiguration.install(MonitorConfiguration.identity) { backend }
        try {
            facade = onMain { PocketCameraSession(context, RecordingFeedIncidentSink(), nativePinNow = { now }) }
        } finally {
            MonitorConfiguration.install(MonitorConfiguration.identity) { host ->
                val wifi = com.opencapture.openinstacine.monitor.pairing.CameraWifiCredentialStore(host)
                com.opencapture.opencine.insta360.luna.LunaBackend(host,
                    savedWifi = wifi::load, saveWifi = wifi::save, forgetWifi = wifi::remove)
            }
        }
        onMain { facade.control.bind(core) }
        publish(reported)
    }
    @After fun close() { onMain { facade.close() } }
    private fun publish(value: CameraReadout) {
        reported = value
        onMain { backend.readout.value = value }
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        tick()
    }
    /** Exercise the existing production cached-readout path without waiting for its one-second timer. */
    private fun tick() = onMain {
        val apply = PocketCameraSession::class.java.getDeclaredMethod("applyReadout", CameraReadout::class.java)
        apply.isAccessible = true
        apply.invoke(facade, reported)
        Unit
    }
    private fun format(value: CameraRecordFormat) = onMain { assertTrue(facade.setNativeRecordingFormat(value)) }
    private fun color(value: CameraColorProfile) = onMain { assertTrue(facade.setNativeRecordingColor(value)) }
    private fun shown(format: CameraRecordFormat?, color: CameraColorProfile?) = onMain {
        assertEquals(format, facade.nativeFormat.value)
        assertEquals(color, facade.nativeColor.value)
    }

    @Test fun sameSourceFormatABAFailureCannotRollbackTheLatestChoice() {
        format(b); format(c); format(b)
        onMain { assertEquals(3, backend.formats.size); backend.formats[0].complete(false) }
        shown(b, CameraColorProfile.STANDARD)
    }
    @Test fun sameSourceColorABAFailureCannotRollbackTheLatestChoice() {
        color(CameraColorProfile.LOG); color(CameraColorProfile.DOLBY_VISION); color(CameraColorProfile.LOG)
        onMain { assertEquals(3, backend.colors.size); backend.colors[0].complete(false) }
        shown(a, CameraColorProfile.LOG)
    }
    @Test fun retiredConnectionFailureCannotRollbackARepeatedValueOnTheSuccessor() {
        format(b); color(CameraColorProfile.LOG)
        onMain {
            facade.disconnect()
            backend.frameGeneration = 2
            facade.control.bind(Core())
        }
        publish(report(c, CameraColorProfile.DOLBY_VISION))
        format(b); color(CameraColorProfile.LOG)
        onMain { backend.formats[0].complete(false); backend.colors[0].complete(false) }
        shown(b, CameraColorProfile.LOG)
    }
    @Test fun cachedReportsHoldTheChoiceForThreeSecondsThenReturnToTheReport() {
        format(b); color(CameraColorProfile.LOG)
        tick()
        shown(b, CameraColorProfile.LOG)
        onMain { now += 2_999 }
        tick()
        shown(b, CameraColorProfile.LOG)
        onMain { now += 1 }
        tick()
        shown(a, CameraColorProfile.STANDARD)
        onMain { backend.formats[0].complete(false); backend.colors[0].complete(false) }
        shown(a, CameraColorProfile.STANDARD)
    }
    @Test fun confirmingAndWithdrawingReportsRetireTheirRequestRollback() {
        format(b); color(CameraColorProfile.LOG)
        publish(report(b, CameraColorProfile.LOG))
        onMain { backend.formats[0].complete(false); backend.colors[0].complete(false) }
        shown(b, CameraColorProfile.LOG)
        format(c); color(CameraColorProfile.DOLBY_VISION)
        publish(report(null, null))
        shown(null, null)
        onMain { backend.formats[1].complete(false); backend.colors[1].complete(false) }
        shown(null, null)
    }
    @Test fun anEpochChangeRetiresTheOldRequestEvenWhenItsValueRepeats() {
        format(b); color(CameraColorProfile.LOG)
        onMain { core.snapshots.value = core.snapshots.value.copy(epoch = core.snapshots.value.epoch.next()) }
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        publish(report(c, CameraColorProfile.DOLBY_VISION))
        format(b); color(CameraColorProfile.LOG)
        onMain { backend.formats[0].complete(false); backend.colors[0].complete(false) }
        shown(b, CameraColorProfile.LOG)
    }
    @Test fun aSupersededFaceMeteringFailureCannotRollbackTheLatestChoice() {
        onMain { facade.setFaceMetering(true); facade.setFaceMetering(false); facade.setFaceMetering(true) }
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        onMain { assertEquals(3, backend.meters.size); backend.meters[0].complete(false) }
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        onMain { assertEquals(true, facade.faceMetering.value) }
    }
    @Test fun aRetiredConnectionFaceMeteringFailureCannotRollbackTheSuccessor() {
        onMain { facade.setFaceMetering(true) }
        onMain {
            facade.disconnect()
            backend.frameGeneration = 2
            facade.control.bind(Core())
        }
        publish(report(c, CameraColorProfile.DOLBY_VISION).copy(faceMetering = true))
        onMain { backend.meters[0].complete(false) }
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        onMain { assertEquals(true, facade.faceMetering.value) }
    }
}
