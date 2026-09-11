package com.opencapture.openpocketcine

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

enum class LegalKind(val title: String) {
    PRIVACY("Privacy"),
    TERMS("Terms"),
    LICENSES("Licenses"),
    NOTICE("NOTICE"),
    ;

    val body: String
        get() =
            when (this) {
                PRIVACY -> PRIVACY_BODY
                TERMS -> TERMS_BODY
                LICENSES -> LICENSES_BODY
                NOTICE -> NOTICE_BODY
            }
}

@Composable
fun LegalDocumentScreen(
    kind: LegalKind,
    onClose: () -> Unit,
) {
    BackHandler(onBack = onClose)
    val shape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)
    Box(
        Modifier
            .fillMaxSize()
            .background(LiveDesign.background)
            .windowInsetsPadding(WindowInsets.safeDrawing),
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 12.dp),
        ) {
            Column(Modifier.padding(start = 45.dp)) {
                Text(
                    MonitorConfiguration.identity.wordmark,
                    style = LiveType.ui(9.5f, FontWeight.Bold).copy(letterSpacing = 0.8.sp),
                    color = LiveDesign.accent,
                )
                Text(
                    kind.title,
                    style = LiveType.title(24f, FontWeight.SemiBold),
                    color = LiveDesign.text,
                )
            }
            Spacer(Modifier.height(12.dp))
            Text(
                kind.body,
                style = LiveType.ui(14f, FontWeight.Normal).copy(lineHeight = 19.sp),
                color = LiveDesign.text,
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .verticalScroll(rememberScrollState())
                        .background(LiveDesign.surface, shape)
                        .border(1.dp, LiveDesign.hairline, shape)
                        .padding(16.dp),
            )
        }
        OperatorCloseButton(
            onClose = onClose,
            modifier =
                Modifier
                    .align(Alignment.TopStart)
                    .padding(start = 16.dp, top = 16.dp),
        )
    }
}

private val PRIVACY_BODY = """
OpenInstaCine connects directly to your Insta360 Luna Ultra over Bluetooth and the camera's own Wi-Fi. It does not create an account or upload analytics or footage.

This phone stores your camera list, this installation's authorization identity, operator preferences and imported LUTs. Camera Wi-Fi credentials are read through encrypted Bluetooth and kept in memory for the connection; they are not written to preferences or diagnostic logs.

The live feed stays on the local camera connection. Diagnostics are shared only when you choose Share Diagnostics. A system share or save action passes the selected local file to the destination you choose.

Android permissions allow Bluetooth discovery and joining the camera Wi-Fi. The app does not collect a location history. Android and Google may process system diagnostics under their own policies.

Camera media browsing, recording, camera settings and cloud delivery are not connected in this initial Luna build. View assists run on this phone.
""".trimIndent()

private val TERMS_BODY = """
OpenInstaCine is free software under the Apache License 2.0. It is an independent field monitor and is not affiliated with or endorsed by Insta360.

The initial Luna version provides live monitoring and local view assists. Camera settings and recording controls are unavailable; use the camera body for those operations.

The software is provided on an AS IS basis, without warranties or conditions of any kind. See the repository LICENSE for the complete terms.
""".trimIndent()

private val LICENSES_BODY = """
OpenInstaCine
Copyright 2026 Erik Sutton and contributors

Shared monitor presentation is extracted from OpenPocketCine and OpenZCine.
Copyright 2026 Erik Sutton and OpenPocketCine contributors.
Licensed under the Apache License, Version 2.0:
https://www.apache.org/licenses/LICENSE-2.0

The CubeLUT parser is adapted from OpenZCine (Apache 2.0).
HUD icons: Lucide (ISC; Feather-derived glyphs also MIT).
Fonts: Sora and IBM Plex Sans (SIL Open Font License).
Full notices and font licenses are bundled with the shared monitor resources.

Luna protocol implementation follows this repository's hardware captures and cited public implementation research. No manufacturer SDK is bundled.
""".trimIndent()

private val NOTICE_BODY = """
OpenInstaCine
Copyright 2026 Erik Sutton and contributors

Derived shared monitor: OpenPocketCine / OpenZCine, Apache 2.0.
Copyright 2026 Erik Sutton and OpenPocketCine contributors.
Lucide icons: ISC / MIT. Sora and IBM Plex Sans: SIL OFL.

Insta360 and Luna are used to identify supported cameras. This independent project is not affiliated with or endorsed by Insta360. Historical internal package names identify the source-compatible shared monitor extraction.
""".trimIndent()
