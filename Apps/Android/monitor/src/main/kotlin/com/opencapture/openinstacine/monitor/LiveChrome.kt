package com.opencapture.openinstacine.monitor

import com.opencapture.opencine.cameracontrols.chromeClickable
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.semantics.disabled
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.layoutId
import androidx.compose.ui.platform.LocalConfiguration
import com.opencapture.opencine.insta360.shell.ConnectionPhase
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.opencine.vocabulary.CaptureShutterPolicy
import kotlin.math.max
import kotlin.math.roundToInt
import java.util.Locale

val ChromeShape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)

@Composable
fun Modifier.monitorGlass(shape: Shape = ChromeShape): Modifier = liveChromeGlass(shape)

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

typealias LiveMonitorLayout = com.opencapture.monitorui.LiveMonitorLayout

typealias ChromeRect = com.opencapture.monitorui.MonitorRect

@Composable
fun AuxCircleButton(modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit, glyph: @Composable (Color) -> Unit) {
    val tablet = minOf(LocalConfiguration.current.screenWidthDp, LocalConfiguration.current.screenHeightDp) >= 600
    val side = com.opencapture.monitorui.MonitorLayoutPolicy.systemButtonSize(tablet)
    com.opencapture.monitorui.MonitorAuxCircleButton(
        modifier
            .size(side.dp)
            .alpha(if (enabled) 1f else 0.4f)
            .monitorGlass(RoundedCornerShape(14.dp))
            .then(if (enabled) Modifier.chromeClickable(onClick = onClick)
                else Modifier.semantics { disabled() })
            .semantics { role = Role.Button },
        glyph = glyph,
    )
}

/** Only the native photo service and integration mode editor remain in the app. */
@Composable
internal fun LiveCaptureButton(
    model: AppModel,
    enabled: Boolean,
    diameter: Float,
    modifier: Modifier = Modifier,
) {
    val status by model.session.status.collectAsState()
    val photo = CaptureShutterPolicy.isStillCapture(status.shootingMode)
    com.opencapture.opencine.appkit.MonitorCaptureButton(
        control = model.session.control, diameter = diameter,
        enabled = enabled && (!photo || model.session.phase == com.opencapture.opencine.insta360.shell.ConnectionPhase.LIVE),
        modifier = modifier,
        photo = photo,
        confirm = model.recordConfirmationEnabled,
        takePhoto = model::pressShutter,
    )
}
