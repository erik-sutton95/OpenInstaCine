package com.opencapture.openinstacine.monitor

import android.content.Context
import com.opencapture.opencine.appkit.ShellModel
import com.opencapture.opencine.appkit.stored
import com.opencapture.opencine.core.CameraCommand
import com.opencapture.opencine.core.CameraSession
import com.opencapture.opencine.core.CameraSessionID
import com.opencapture.opencine.core.CameraSnapshot
import com.opencapture.opencine.core.CommandReceipt
import com.opencapture.opencine.core.CommandRejection
import com.opencapture.opencine.core.CommandStage
import com.opencapture.opencine.core.ConnectedCamera
import com.opencapture.opencine.core.ConnectionState
import com.opencapture.opencine.core.ControlAuthority
import com.opencapture.opencine.core.ControlEpoch
import com.opencapture.opencine.core.ISOValue
import com.opencapture.opencine.core.MonotonicInstant
import com.opencapture.opencine.core.ObservationOrigin
import com.opencapture.opencine.core.ObservedValue
import com.opencapture.opencine.core.OperationID
import com.opencapture.opencine.core.Rational
import com.opencapture.opencine.core.RecordingState
import com.opencapture.opencine.core.RouteKind
import com.opencapture.opencine.core.SavedCamera
import com.opencapture.opencine.core.SavedRoute
import com.opencapture.opencine.core.SessionCloseReason
import com.opencapture.opencine.core.SettingKey
import com.opencapture.opencine.core.SettingValue
import com.opencapture.opencine.core.ShutterValue
import com.opencapture.opencine.core.WhiteBalanceValue
import com.opencapture.opencine.insta360.luna.LunaFailures
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Debug only, SIMULATED (SHELL-03 review): drives the real root through cameras, live, Settings and
 * Media with a scripted session. No camera, no network, never a command on a wire.
 */
object ShellReview {
    private val camera = SavedCamera(
        id = "review-simulated-1", integration = LunaFailures.INTEGRATION, advertisedName = "SIMULATED Luna Ultra",
        model = "Luna Ultra", routes = listOf(SavedRoute(key = "ap", kind = RouteKind.CAMERA_ACCESS_POINT, network = "SIMULATED")),
    )

    /** One SIMULATED saved camera in this debug build's own preferences, so the cameras page shows. */
    fun seed(context: Context) {
        AppModel.camerasStore(
            context.getSharedPreferences("openpocketcine.cameras", Context.MODE_PRIVATE).stored("document"),
            context.getSharedPreferences(AppModel.LEGACY_CAMERAS, Context.MODE_PRIVATE).stored("records-json"),
        ).save(listOf(camera))
    }

    /** Applies one review step; returns the state line the review logs. */
    fun step(model: AppModel, step: String): String {
        val shell = model.shell
        when (step) {
            "live" -> if (shell.state.value.monitor == null) shell.present(ConnectedCamera(camera, ReviewSession()))
            "settings" -> shell.open(ShellModel.Cover.SETTINGS)
            "media" -> shell.open(ShellModel.Cover.MEDIA)
            "back" -> shell.dismissCover()
            "close" -> shell.close()
        }
        return state(model, step)
    }

    fun state(model: AppModel, step: String): String {
        val shell = model.shell
        return "step=$step route=${shell.route} cover=${shell.state.value.cover} " +
            "monitor=${shell.state.value.monitor?.id?.take(8)} hostsMounted=${shell.hostsMounted} hostsUnmounted=${shell.hostsUnmounted}"
    }

    /** A SIMULATED camera: reported values only, every command refused. */
    private class ReviewSession : CameraSession {
        override val id = CameraSessionID()
        private fun <T : Any> reported(value: T) = ObservedValue(value, ObservationOrigin.CAMERA_REPORTED, MonotonicInstant.ZERO)
        private val state = MutableStateFlow(
            CameraSnapshot(
                session = id, epoch = ControlEpoch(1), connection = ConnectionState.Ready, authority = ControlAuthority.Owner,
                settings = mapOf(
                    SettingKey.ISO to reported(SettingValue.Iso(ISOValue.Manual(800))),
                    SettingKey.SHUTTER to reported(SettingValue.Shutter(ShutterValue.Duration(Rational(1, 50)))),
                    SettingKey.WHITE_BALANCE to reported(SettingValue.WhiteBalance(WhiteBalanceValue.Kelvin(5600))),
                ),
                recording = reported(RecordingState.IDLE),
            ),
        )
        override val snapshots: StateFlow<CameraSnapshot> = state

        override suspend fun submit(command: CameraCommand) =
            CommandReceipt(command.operation, id, command.intent, CommandStage.Rejected(CommandRejection.Unsupported))

        override suspend fun outcome(operation: OperationID): CommandReceipt? = null
        override fun receipt(operation: OperationID): CommandReceipt? = null
        override suspend fun close(reason: SessionCloseReason) = closeNow(reason)

        override fun closeNow(reason: SessionCloseReason) {
            state.value = state.value.copy(connection = ConnectionState.Disconnected(reason))
        }
    }
}
