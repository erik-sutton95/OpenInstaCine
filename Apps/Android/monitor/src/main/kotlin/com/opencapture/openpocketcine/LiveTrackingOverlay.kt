package com.opencapture.openpocketcine

import com.opencapture.opencine.appkit.LocalOperatorHaptics
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import com.opencapture.monitorui.MonitorFocusMark
import com.opencapture.monitorui.MonitorRect
import com.opencapture.monitorui.MonitorTrackingBracketValue
import com.opencapture.monitorui.MonitorTrackingLayer
import com.opencapture.monitorui.MonitorTrackingRect
import com.opencapture.openpocketcine.session.FocusOverlay
import com.opencapture.openpocketcine.session.LiveTrackingChrome
import com.opencapture.openpocketcine.session.TrackingBox
import com.opencapture.openpocketcine.session.TrackingHud

@Composable
fun LiveFocusTrackingLayer(hud: TrackingHud, focus: Pair<Float, Float>?, mirrored: Boolean,
    showTapFocusBox: Boolean, modifier: Modifier = Modifier, aeLocked: Boolean = false,
    flippedVertically: Boolean = false, focusLocked: Boolean = false) {
    fun bracket(box: TrackingBox, color: Color, width: Float): MonitorTrackingBracketValue {
        val drawn = box.flipped(mirrored, flippedVertically)
        return MonitorTrackingBracketValue(MonitorTrackingRect(drawn.x, drawn.y, drawn.width, drawn.height), color, width)
    }
    val brackets = hud.dimmedFaces.map { bracket(it, LiveDesign.text.copy(alpha = 0.20f), 1.6f) }.toMutableList()
    val showFocus = when (val overlay = hud.overlay) {
        is FocusOverlay.Search -> {
            brackets += bracket(overlay.box, LiveDesign.text.copy(alpha = 0.88f), 1.5f)
            showTapFocusBox
        }
        is FocusOverlay.Subject -> { brackets += bracket(overlay.box, LiveDesign.good, 2f); false }
        is FocusOverlay.Face -> { brackets += bracket(overlay.box, LiveDesign.text.copy(alpha = 0.92f), 1.6f); false }
        FocusOverlay.Focus -> showTapFocusBox
    }
    val mark = if (showFocus && focus != null) MonitorFocusMark(
        Offset(if (mirrored) 1f - focus.first else focus.first,
            if (flippedVertically) 1f - focus.second else focus.second),
        if (aeLocked) LiveDesign.aeLock else LiveDesign.accent, aeLocked, focusLocked) else null
    MonitorTrackingLayer(brackets, mark, modifier)
}

@Composable
fun LiveTrackingCancelButton(box: TrackingBox, feedWidth: Float, feedHeight: Float,
    mirrored: Boolean, flippedVertically: Boolean = false, onClick: () -> Unit) {
    val rect = LiveTrackingChrome.cancelRect(box, feedWidth, feedHeight, mirrored, flippedVertically)
    val haptics = LocalOperatorHaptics.current
    com.opencapture.monitorui.MonitorTrackingCancelButton(MonitorRect(rect.x, rect.y, rect.width, rect.height),
        LiveDesign.good, LiveDesign.background, onClick = onClick, feedback = { haptics.selection() })
}
