@file:androidx.media3.common.util.UnstableApi
package com.opencapture.openinstacine.monitor.media

import android.content.Context
import com.opencapture.opencine.appkit.MonitorMediaPlaybackModel
import com.opencapture.opencine.appkit.MonitorPlaybackAdmission
import com.opencapture.opencine.appkit.MonitorPlaybackAudioSession
import com.opencapture.opencine.media.MonitorPlaybackLookTiming
import com.opencapture.opencine.media.MonitorPlaybackStartTiming
import com.opencapture.opencine.runtime.MonitorAudioMeterSampler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel

/** Actual SDK resources for one shared logical player. Reopening creates a fresh native owner. */
internal class LunaAndroidPlaybackOwner(context: Context, controller: LunaMediaPlaybackAdapter) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val meterBox = AudioLevelTapBox()
    val meterSink = PlaybackPcmBufferSink(meterBox)
    val meterSampler = MonitorAudioMeterSampler(meterBox)
    val native = Media3PlaybackPort(createPlaybackExoPlayer(context, meterSink), scope)
    val audio = MonitorPlaybackAudioSession(scope, read = meterSampler::step,
        reset = { meterSampler.reset(); meterBox.readAndReset() })
    val playback = MonitorMediaPlaybackModel<LunaMediaLibraryPayload, LunaPlaybackLook>(controller.library,
        native, scope, readyTimeout = null, retryNativeFailures = false,
        candidates = controller::playbackCandidates,
        lookTiming = MonitorPlaybackLookTiming.BEFORE_NATIVE_PREPARATION,
        startTiming = MonitorPlaybackStartTiming.AFTER_NATIVE_ITEM_INSTALLATION,
        resolveLook = { record, _ -> controller.resolvePlaybackLook(record) }).also { owner ->
            owner.setItemAdmission { record ->
                val source = controller.library.actionToken
                val directory = controller.library.cache.directory
                val generation = directory.generation
                MonitorPlaybackAdmission {
                    controller.library.isCurrent(source) && controller.library.state.value.browsing &&
                        directory.generation == generation && controller.library.record(record.asset.id) != null
                }
            }
            native.listedFrameRate = { token ->
                val current = owner.state.value
                if (current.token == token && owner.isActive && owner.state.value.token == token)
                    current.active?.payload?.file?.fps?.toDouble() else null
            }
            native.sourceAdmission = { token -> owner.state.value.token == token && owner.isActive && owner.state.value.token == token }
        }
    fun close() {
        playback.close(); audio.close(); meterSink.close(); meterBox.close(); scope.cancel()
    }
}
