@file:androidx.media3.common.util.UnstableApi
package com.opencapture.openpocketcine.media

import androidx.media3.exoplayer.ExoPlayer
import com.opencapture.opencine.media.MonitorPlaybackItemToken
import kotlinx.coroutines.test.runTest
import java.lang.reflect.Proxy
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals

/** Observes the real SDK boundary without constructing Android GL/Surface resources. */
class Media3PlaybackPortTest {
    @Test fun departingPictureCannotClearSuccessorOrInvokeReleasedPlayer() = runTest {
        val calls = mutableListOf<String>()
        val player = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader, arrayOf(ExoPlayer::class.java)) { _, method, _ ->
            calls += method.name
            null
        } as ExoPlayer
        val native = Media3PlaybackPort(player, backgroundScope)
        native.retireItem(MonitorPlaybackItemToken(UUID.randomUUID(), 0))
        val a = native.claimPicture(); val b = native.claimPicture()
        val before = calls.count { it == "clearVideoSurface" }
        native.releasePicture(a)
        assertEquals(before, calls.count { it == "clearVideoSurface" })
        native.releasePicture(b)
        assertEquals(before + 1, calls.count { it == "clearVideoSurface" })
        val token = MonitorPlaybackItemToken(UUID.randomUUID(), 0)
        native.retireItem(token); native.close(token)
        val afterClose = calls.size
        native.releasePicture(b)
        assertEquals(afterClose, calls.size)
        assertEquals(1, calls.count { it == "release" })
    }
    @Test fun outgoingItemCannotReclaimOrCloseAReusedNativePlayer() = runTest {
        val calls = mutableListOf<String>()
        val player = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader, arrayOf(ExoPlayer::class.java)) { _, method, _ ->
            calls += method.name
            null
        } as ExoPlayer
        val native = Media3PlaybackPort(player, backgroundScope)
        val a = MonitorPlaybackItemToken(UUID.randomUUID(), 0)
        val b = MonitorPlaybackItemToken(UUID.randomUUID(), 0)
        native.retireItem(a); native.retireItem(b)
        val before = calls.toList()
        native.retireItem(a.copy(revision = 1)); native.close(a.copy(revision = 2))
        assertEquals(before, calls)
        native.close(b.copy(revision = 1))
        assertEquals(1, calls.count { it == "release" })
    }
    @Test fun replacementDuringRateCallbackCannotStartSuccessorTransport() = runTest {
        val calls = mutableListOf<String>(); var replace: (() -> Unit)? = null
        val player = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader, arrayOf(ExoPlayer::class.java)) { _, method, _ ->
            calls += method.name
            if (method.name == "setPlaybackParameters") { val callback = replace; replace = null; callback?.invoke() }
            null
        } as ExoPlayer
        val native = Media3PlaybackPort(player, backgroundScope)
        val a = MonitorPlaybackItemToken(UUID.randomUUID(), 0); val b = MonitorPlaybackItemToken(UUID.randomUUID(), 0)
        native.retireItem(a); replace = { native.retireItem(b) }
        native.play(0.25, a)
        assertEquals(0, calls.count { it == "setPlayWhenReady" }, "A's SDK continuation cannot start the replacement")
        native.play(1.0, b)
        assertEquals(1, calls.count { it == "setPlayWhenReady" }, "the successor retains transport authority")
        native.close(b)
    }

    @Test fun replacementDuringStopCallbackCannotClearSuccessorNativeItem() = runTest {
        val calls = mutableListOf<String>(); var replace: (() -> Unit)? = null
        val player = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader, arrayOf(ExoPlayer::class.java)) { _, method, _ ->
            calls += method.name
            if (method.name == "stop") { val callback = replace; replace = null; callback?.invoke() }
            null
        } as ExoPlayer
        val native = Media3PlaybackPort(player, backgroundScope)
        val a = MonitorPlaybackItemToken(UUID.randomUUID(), 0); val b = MonitorPlaybackItemToken(UUID.randomUUID(), 0)
        native.retireItem(a); val before = calls.count { it == "clearMediaItems" }
        replace = { native.retireItem(b) }; native.retireItem(a.copy(revision = 1))
        assertEquals(before + 1, calls.count { it == "clearMediaItems" }, "only B's own retirement clears its old native item")
        val after = calls.toList(); native.close(a.copy(revision = 2)); assertEquals(after, calls)
        native.play(1.0, b); assertEquals(1, calls.count { it == "setPlayWhenReady" })
        native.close(b)
    }

}
