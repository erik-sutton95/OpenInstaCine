package com.opencapture.openinstacine.monitor.bridge

import android.util.Log

/**
 * JNI binding to `libOpenInstaCineAndroid.so`: OpenInstaViewCore plus
 * `OpenInstaCineAndroidFacade`. Staged by `:app:stageSwiftCore` / `just android-core`.
 */
object SwiftCore : com.opencapture.opencine.cameracontrols.MonitorFeedEffectsPacker {
    override val isAvailable: Boolean by lazy {
        try {
            System.loadLibrary("OpenInstaCineAndroid")
            true
        } catch (e: UnsatisfiedLinkError) {
            // Nothing that reads this flag can work without the core, and the
            // app degrades quietly instead of crashing. Say so once in logcat,
            // or a stripped / wrong-ABI build looks like a dead camera.
            //
            // Wrapped because reporting a failure must never become one: JVM
            // unit tests have no `.so` to load and no `android.util.Log` to
            // load it with, and the stub throws rather than no-op.
            runCatching { Log.e("SwiftCore", "libOpenInstaCineAndroid.so did not load", e) }
            false
        }
    }

    /** Media browse enter-playback command kind (the DUML transport is not linked here). */
    const val CMD_ENTER_PLAYBACK = 12

    external fun coreVersion(): String

    /** Packed-2D RGBA8 cube (`n³ × 4`) for GLES upload. Input-referred LUT exposure. */
    override external fun packImportedLut(utf8: ByteArray, exposureStops: Double, colorMode: Int): ByteArray?

    /** Generated Creative look (Mono / Contrast / Warm / Cool). */
    override external fun packCreativeLut(title: String, exposureStops: Double, colorMode: Int): ByteArray?

    /** Overlay paint cube for FALSE (`0` Video / `1` IRE / `2` Limits / `3` CineStop). */
    override external fun packFalseColorPaint(scaleOrdinal: Int, colorMode: Int, iso: Int): ByteArray?

    /** Overlay weight cube paired with [packFalseColorPaint]. */
    override external fun packFalseColorWeight(scaleOrdinal: Int, colorMode: Int, iso: Int): ByteArray?

    /**
     * `[highlightNative, midtoneNative, midtoneHalfNative, peakingGateScale]`
     * on encoded camera codes (iOS `ScopeDisplayScale.signalNative`).
     */
    override external fun feedAssistScalars(
        colorMode: Int,
        iso: Int,
        highlightIRE: Float,
        midtoneIRE: Float,
    ): FloatArray?

    /** Named Media curves, independent of recording-option bytes and stored legacy ids. Unknown is null. */
    external fun packImportedLutForTransfer(utf8: ByteArray, exposureStops: Double, transferTag: String?): ByteArray?
    external fun packCreativeLutForTransfer(title: String, exposureStops: Double, transferTag: String?): ByteArray?
    external fun packFalseColorPaintForTransfer(scaleOrdinal: Int, transferTag: String?, iso: Int): ByteArray?
    external fun packFalseColorWeightForTransfer(scaleOrdinal: Int, transferTag: String?, iso: Int): ByteArray?
    external fun feedAssistScalarsForTransfer(transferTag: String?, iso: Int, highlightIRE: Float, midtoneIRE: Float): FloatArray?
}
