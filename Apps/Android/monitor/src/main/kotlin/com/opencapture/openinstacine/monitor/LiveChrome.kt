package com.opencapture.openinstacine.monitor

import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

val ChromeShape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)

fun Modifier.liveModuleFrame(rect: ChromeRect): Modifier =
    offset(rect.x.dp, rect.y.dp).size(rect.width.dp, rect.height.dp)

/** Occupies [rect] and seats wrapping chrome (InfoPill, capture strip) like iOS `alignment`. */
fun Modifier.liveModuleFrame(rect: ChromeRect, alignment: Alignment): Modifier {
    val vertical =
        when (alignment) {
            Alignment.TopStart, Alignment.TopCenter, Alignment.TopEnd -> Alignment.Top
            Alignment.BottomStart, Alignment.BottomCenter, Alignment.BottomEnd -> Alignment.Bottom
            else -> Alignment.CenterVertically
        }
    return liveModuleFrame(rect).wrapContentHeight(align = vertical, unbounded = true)
}

typealias ChromeRect = com.opencapture.monitorui.MonitorRect
