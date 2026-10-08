package com.opencapture.openinstacine.monitor

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import com.opencapture.opencine.appkit.ShellModel
import com.opencapture.openinstacine.monitor.media.MediaLibraryScreen

/** Complete shared settings and catalog composition beneath the shell's cover lifetime. */
@Composable
fun ShellPage(model: AppModel, cover: ShellModel.Cover) {
    when (cover) {
        ShellModel.Cover.SETTINGS -> OperatorSetupScreen(model) { model.shell.dismissCover() }
        ShellModel.Cover.MEDIA -> MediaLibraryScreen(model) { model.shell.dismissCover() }
    }
}

/** The shell's cover, read in composition (recomposes when it changes). */
@Composable
fun AppModel.liveCover(): ShellModel.Cover? = shell.state.collectAsState().value.cover
