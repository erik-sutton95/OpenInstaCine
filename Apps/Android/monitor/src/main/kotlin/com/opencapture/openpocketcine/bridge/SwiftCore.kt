package com.opencapture.openpocketcine.bridge

import android.util.Log

/**
 * JNI binding to `libOpenPocketCineAndroid.so` — OpenPocketViewCore plus
 * `OpenPocketCineAndroidFacade`. Staged by `:app:stageSwiftCore` / `just android-core`.
 */
object SwiftCore {
    val isAvailable: Boolean by lazy {
        try {
            System.loadLibrary("OpenPocketCineAndroid")
            true
        } catch (e: UnsatisfiedLinkError) {
            // Nothing that reads this flag can work without the core, and the
            // app degrades quietly instead of crashing. Say so once in logcat,
            // or a stripped / wrong-ABI build looks like a dead camera.
            //
            // Wrapped because reporting a failure must never become one: JVM
            // unit tests have no `.so` to load and no `android.util.Log` to
            // load it with, and the stub throws rather than no-op.
            runCatching { Log.e("SwiftCore", "libOpenPocketCineAndroid.so did not load", e) }
            false
        }
    }

    /** Media browse enter-playback command kind (the DUML transport is not linked here). */
    const val CMD_ENTER_PLAYBACK = 12

    external fun coreVersion(): String

    /** Packed-2D RGBA8 cube (`n³ × 4`) for GLES upload. Input-referred LUT exposure. */
    external fun packImportedLut(utf8: ByteArray, exposureStops: Double, colorMode: Int): ByteArray?

    /** Generated Creative look (Mono / Contrast / Warm / Cool). */
    external fun packCreativeLut(title: String, exposureStops: Double, colorMode: Int): ByteArray?

    /** Overlay paint cube for FALSE (`0` Video / `1` IRE / `2` Limits / `3` CineStop). */
    external fun packFalseColorPaint(scaleOrdinal: Int, colorMode: Int, iso: Int): ByteArray?

    /** Overlay weight cube paired with [packFalseColorPaint]. */
    external fun packFalseColorWeight(scaleOrdinal: Int, colorMode: Int, iso: Int): ByteArray?

    /**
     * `[highlightNative, midtoneNative, midtoneHalfNative, peakingGateScale]`
     * on encoded camera codes (iOS `ScopeDisplayScale.signalNative`).
     */
    external fun feedAssistScalars(
        colorMode: Int,
        iso: Int,
        highlightIRE: Float,
        midtoneIRE: Float,
    ): FloatArray?

    /**
     * `CameraSoftAP` / first-picture / handshake gates. `kind` is the Swift
     * function name; [requestJSON] is the argument bag. Bool results are
     * `"true"` / `"false"`; handshake / first-picture enums use core raw values
     * (`keepSocket`, `rebindUDP`, `fail`, `wait`, `resendEnable`, …).
     */
    external fun cameraSoftAPDecision(kind: String, requestJSON: String): String?

    /** Probe JSON for playback conform preview. See `AndroidSessionWire.conformPreviewJSON`. */
    external fun conformPreviewJSON(request: String): String?
}
