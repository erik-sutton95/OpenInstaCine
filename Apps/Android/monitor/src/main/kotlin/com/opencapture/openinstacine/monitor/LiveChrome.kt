package com.opencapture.openinstacine.monitor

import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

val ChromeShape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)

fun Modifier.liveModuleFrame(rect: ChromeRect): Modifier =
    offset(rect.x.dp, rect.y.dp).size(rect.width.dp, rect.height.dp)

typealias ChromeRect = com.opencapture.monitorui.MonitorRect
