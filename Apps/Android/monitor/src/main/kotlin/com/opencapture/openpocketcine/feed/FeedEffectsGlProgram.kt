package com.opencapture.openpocketcine.feed

import android.content.Context

internal class FeedEffectsGlProgram(
    context: Context,
    plan: FeedEffectsRenderPlan,
    flipInputVertically: Boolean = false,
) {
    private val runtime = com.opencapture.opencine.runtime.FeedEffectsGlProgram(
        Media3GlBackend(context), plan, flipInputVertically,
        reconstructToDisplay = { sourceWidth, sourceHeight, displayWidth, displayHeight ->
            FeedUpscaleSwitch.rendererReads == FeedUpscaler.FAST &&
                FeedUpscaler.shouldReconstructToDisplay(sourceWidth, sourceHeight, displayWidth, displayHeight)
        },
    )
    fun adopt(next: FeedEffectsRenderPlan) = runtime.adopt(next)
    fun draw(inputTexture: Int, sourceWidth: Float, sourceHeight: Float,
        displayWidth: Float, displayHeight: Float, mirrored: Boolean = false,
        look: Boolean = true, upscale: Boolean = !look) =
        runtime.draw(inputTexture, sourceWidth, sourceHeight, displayWidth, displayHeight, mirrored, look, upscale)
    fun release() = runtime.release()
}
