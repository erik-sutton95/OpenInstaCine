package com.opencapture.openinstacine

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.opencapture.openpocketcine.BrandIdentity
import com.opencapture.openpocketcine.MonitorConfiguration
import com.opencapture.openpocketcine.ShellReview

/**
 * Debug only, SIMULATED (SHELL-03 review): the real app root over the local replay backend (no
 * Bluetooth, no camera) and one SIMULATED saved camera. `adb shell am start -n <pkg>/<this> --es
 * step live|settings|back|media|close` drives the shell; each step logs `ShellReview` with the
 * monitor host counts.
 */
class ShellReviewActivity : com.opencapture.openpocketcine.MainActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        val brand = BrandIdentity("OpenInstaCine", "OPENINSTACINE", 0xFFFFCF00, "Insta360 Luna Ultra", sourceLabel = "SIMULATED · NOT A LIVE CAMERA")
        MonitorConfiguration.install(brand, cameraLooks = LunaCameraLooks.entries) { LocalReplayBackend(it) }
        ShellReview.seed(this)
        super.onCreate(savedInstanceState)
        handle(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent) {
        val step = intent.getStringExtra("step") ?: return
        Log.i("ShellReview", ShellReview.step(model, step))
        // After the composition settles, the counts the host lifetime left behind.
        Handler(Looper.getMainLooper()).postDelayed({ Log.i("ShellReview", ShellReview.state(model, "$step+settled")) }, 1_500)
    }
}
