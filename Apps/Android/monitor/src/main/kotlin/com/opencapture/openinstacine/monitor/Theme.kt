package com.opencapture.openinstacine.monitor

import androidx.compose.runtime.Composable
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import com.opencapture.monitorui.MonitorAppTheme

/** OpenCine's shared operator colours, design tokens and type under this app's names. */
typealias BrandColors = com.opencapture.monitorui.MonitorBrandColors
typealias LiveDesign = com.opencapture.monitorui.MonitorDesign
typealias LiveType = com.opencapture.monitorui.MonitorType

object OpcFonts {
    val sora = com.opencapture.monitorui.MonitorTypography.fontFamily
    val plex =
        FontFamily(
            Font(R.font.ibm_plex_sans_regular, FontWeight.Normal),
            Font(R.font.ibm_plex_sans_medium, FontWeight.Medium),
            Font(R.font.ibm_plex_sans_semibold, FontWeight.SemiBold),
            Font(R.font.ibm_plex_sans_bold, FontWeight.Bold),
        )
    val mono = sora
}

@Composable
fun OpenInstaCineTheme(content: @Composable () -> Unit) = MonitorAppTheme(content)
