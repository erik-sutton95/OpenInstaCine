package com.opencapture.openinstacine.monitor.assists

import android.content.Context
import com.opencapture.openinstacine.monitor.OperatorPrefs

typealias LiveAssistState = com.opencapture.opencine.appkit.MonitorAssistState

fun createLiveAssistState(context: Context): LiveAssistState {
    val app = context.applicationContext
    return LiveAssistState(
        encoded = OperatorPrefs.assistEncoded(app),
        pinnedNames = OperatorPrefs.cleanViewPinnedTools(app),
        onPersist = { OperatorPrefs.setAssistEncoded(app, it) },
        onPersistPins = { OperatorPrefs.setCleanViewPinnedTools(app, it) },
        playbackNames = OperatorPrefs.playbackVisibleAssistTools(app),
        onPersistPlayback = { OperatorPrefs.setPlaybackVisibleAssistTools(app, it) },
    )
}
