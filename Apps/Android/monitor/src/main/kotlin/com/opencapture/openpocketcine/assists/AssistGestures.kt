package com.opencapture.openpocketcine.assists

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerInputScope

internal suspend fun PointerInputScope.detectTapAndLongPress(
    longPressMs: Long,
    enabled: Boolean,
    onTap: () -> Unit,
    onLongPress: () -> Unit,
) {
    if (!enabled) return
    awaitEachGesture {
        awaitFirstDown(requireUnconsumed = false)
        val up = withTimeoutOrNull(longPressMs) { waitForUpOrCancellation() }
        if (up == null) {
            onLongPress()
            waitForUpOrCancellation()
        } else {
            onTap()
        }
    }
}
