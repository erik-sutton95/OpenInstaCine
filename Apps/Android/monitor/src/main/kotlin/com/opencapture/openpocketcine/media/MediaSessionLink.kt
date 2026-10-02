package com.opencapture.openpocketcine.media

import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import com.opencapture.openpocketcine.session.DumlFrame
import com.opencapture.openpocketcine.session.PocketCameraSession

/**
 * Session/datalink surface the media browser needs. Live enable goes through
 * [PocketCameraSession.restartLiveViewAfterMedia], not a raw `0xa8` write.
 */
interface MediaSessionLink {
    val isLive: Boolean
    val cameraId: String
    val cameraName: String
    val inPlayback: Boolean
    val internalTotalMb: Int
    val videoPackets: Int
    val hasVideoFormat: Boolean

    fun sendCommand(kind: Int)

    fun sendDuml(cmdSet: Int, cmdId: Int, payload: ByteArray)

    fun enableLiveView(): Boolean

    fun addFrameListener(listener: (DumlFrame) -> Unit): () -> Unit
}

class PocketCameraMediaLink(
    private val session: PocketCameraSession,
    private val lastCameraId: () -> String?,
    private val rememberCameraId: (String) -> Unit,
) : MediaSessionLink {
    override val isLive: Boolean
        get() = session.phaseFlow.value == ConnectionPhase.LIVE

    override val cameraId: String
        get() {
            val id = session.connectedCamera?.id
            if (!id.isNullOrEmpty()) {
                rememberCameraId(id)
                return id
            }
            return lastCameraId() ?: "unknown"
        }

    override val cameraName: String
        get() = session.connectedCamera?.model?.name.orEmpty()

    override val inPlayback: Boolean
        get() = session.status.value.inPlayback

    override val internalTotalMb: Int
        get() = session.status.value.internalTotalMb

    override val videoPackets: Int
        get() = session.videoPackets

    override val hasVideoFormat: Boolean
        get() = session.hasVideoFormat

    // The Luna session has no DUML datalink, so the DJI media commands and frames go nowhere
    // (the upstream link found the driver by reflection on a `datalink` field this session lacks).
    override fun sendCommand(kind: Int) = Unit

    override fun sendDuml(cmdSet: Int, cmdId: Int, payload: ByteArray) = Unit

    override fun enableLiveView(): Boolean = session.restartLiveViewAfterMedia()

    override fun addFrameListener(listener: (DumlFrame) -> Unit): () -> Unit = {}
}

fun MediaSessionLink.sendEnterPlayback() {
    if (SwiftCore.isAvailable) {
        sendCommand(SwiftCore.CMD_ENTER_PLAYBACK)
    } else {
        sendDuml(MediaCommands.SET_CAMERA, MediaCommands.CMD_PLAYBACK, MediaCommands.enterPlaybackPayload())
    }
}

fun MediaSessionLink.sendExitPlayback() {
    sendDuml(MediaCommands.SET_CAMERA, MediaCommands.CMD_PLAYBACK, MediaCommands.exitPlaybackPayload())
}

fun MediaSessionLink.sendMediaList(counter: Int, cursor: Long) {
    sendDuml(
        MediaCommands.SET_GENERAL,
        MediaCommands.CMD_MEDIA_LIST,
        MediaListCommand.listPayload(counter, cursor),
    )
}

fun MediaSessionLink.sendMediaListTrigger() {
    sendDuml(MediaCommands.SET_GENERAL, MediaCommands.CMD_MEDIA_LIST, MediaListCommand.triggerPayload)
}
