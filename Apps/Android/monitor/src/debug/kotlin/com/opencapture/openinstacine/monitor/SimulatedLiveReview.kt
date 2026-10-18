package com.opencapture.openinstacine.monitor

import com.opencapture.monitorui.ReviewLiveValues
import com.opencapture.opencine.insta360.shell.EncodedVideoFrame
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.takeWhile
import java.util.concurrent.atomic.AtomicLong
import com.opencapture.opencine.core.CameraCommand
import com.opencapture.opencine.core.CameraRecordingFormat
import com.opencapture.opencine.core.CameraRecordingObservations
import com.opencapture.opencine.core.CameraSession
import com.opencapture.opencine.core.CameraSessionID
import com.opencapture.opencine.core.CameraTimecode
import com.opencapture.opencine.core.CommandReceipt
import com.opencapture.opencine.core.CommandRejection
import com.opencapture.opencine.core.CommandStage
import com.opencapture.opencine.core.ConnectionState
import com.opencapture.opencine.core.ControlAuthority
import com.opencapture.opencine.core.ControlEpoch
import com.opencapture.opencine.core.ISOValue
import com.opencapture.opencine.core.MonotonicInstant
import com.opencapture.opencine.core.ObservationOrigin
import com.opencapture.opencine.core.ObservedValue
import com.opencapture.opencine.core.OperationID
import com.opencapture.opencine.core.PowerStatus
import com.opencapture.opencine.core.Rational
import com.opencapture.opencine.core.RecordingState
import com.opencapture.opencine.core.SessionCloseReason
import com.opencapture.opencine.core.SettingKey
import com.opencapture.opencine.core.SettingValue
import com.opencapture.opencine.core.ShutterValue
import com.opencapture.opencine.core.StorageVolume
import com.opencapture.opencine.core.WhiteBalanceValue
import com.opencapture.opencine.insta360.shell.CameraCapability
import com.opencapture.opencine.insta360.shell.CameraIdentity
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import com.opencapture.opencine.insta360.shell.label
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Debug only, SIMULATED (`ReviewLaunch` LIVE): the review Luna backend, live from the start with the
 * shared review values and procedural encoded frames. No radio, network or decoder owner;
 * every setter is refused. The existing session owns actual decode and presentation.
 */
internal class SimulatedLiveBackend(
    values: ReviewLiveValues = ReviewLiveValues.SIMULATED,
    input: Flow<ByteArray> = emptyFlow(),
) : ReviewLunaBackend(
    camera = CameraIdentity("review-simulated-1", "SIMULATED Luna Ultra", "Luna Ultra"),
    initialPhase = ConnectionPhase.LIVE,
    firmware = "SIMULATED",
    capabilities = setOf(CameraCapability.LIVE_VIDEO, CameraCapability.ZOOM, CameraCapability.FOCUS),
    values = values,
) {
    private val generation = AtomicLong(1)
    override val frameConnectionGeneration: Long get() = generation.get()
    override val frames: Flow<EncodedVideoFrame> = input.takeWhile { generation.get() == 1L }.map {
        // Asset repeats never reset the actual producer clock. A retired backend rejects every
        // previously emitted unit through the production session's existing generation check.
        EncodedVideoFrame(it, System.nanoTime() / 1_000, connectionGeneration = 1)
    }
    override fun disconnect() { generation.incrementAndGet() }
    override fun close() = disconnect()
}

/**
 * Debug only, SIMULATED: the common session the LIVE review presents, reporting the shared review
 * values the way a connected Luna's session does (iOS reports them through `LunaCameraSession`).
 * Every command is refused.
 */
internal class ReviewLiveSession(values: ReviewLiveValues = ReviewLiveValues.SIMULATED) : CameraSession {
    override val id = CameraSessionID()
    private fun <T : Any> reported(value: T) = ObservedValue(value, ObservationOrigin.CAMERA_REPORTED, MonotonicInstant.ZERO)
    private val state = MutableStateFlow(
        com.opencapture.opencine.core.CameraSnapshot(
            session = id, epoch = ControlEpoch(1), connection = ConnectionState.Ready, authority = ControlAuthority.Owner,
            settings = mapOf(
                SettingKey.ISO to reported(SettingValue.Iso(ISOValue.Manual(values.iso))),
                SettingKey.SHUTTER to reported(SettingValue.Shutter(ShutterValue.Duration(Rational(1, values.shutterDenominator)))),
                SettingKey.WHITE_BALANCE to reported(SettingValue.WhiteBalance(WhiteBalanceValue.Kelvin(values.whiteBalanceKelvin))),
                SettingKey.FRAME_RATE to reported(SettingValue.FrameRate(Rational(values.framesPerSecond, 1))),
            ),
            recording = reported(RecordingState.IDLE),
            power = PowerStatus(battery = reported(values.batteryPercent / 100.0)),
            storage = reported(listOf(StorageVolume("review-card", freeBytes = reported(values.storageFreeBytes),
                totalBytes = reported(values.storageTotalBytes)))),
            timecode = reported(CameraTimecode(values.timecodeHours, values.timecodeMinutes, values.timecodeSeconds, frames = 0)),
            recordingFormat = CameraRecordingObservations(
                dimensions = CameraRecordingFormat.Dimensions.measured(values.recordWidth, values.recordHeight)
                    ?.let(::reported) ?: ObservedValue.unknown,
                profile = reported(reviewLiveColor.label),
            ),
        ),
    )
    override val snapshots: StateFlow<com.opencapture.opencine.core.CameraSnapshot> = state
    override suspend fun submit(command: CameraCommand) =
        CommandReceipt(command.operation, id, command.intent, CommandStage.Rejected(CommandRejection.Unsupported))
    override suspend fun outcome(operation: OperationID): CommandReceipt? = null
    override fun receipt(operation: OperationID): CommandReceipt? = null
    override suspend fun close(reason: SessionCloseReason) = closeNow(reason)
    override fun closeNow(reason: SessionCloseReason) {
        state.value = state.value.copy(connection = ConnectionState.Disconnected(reason))
    }
}
