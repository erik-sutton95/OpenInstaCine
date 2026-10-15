package com.opencapture.openinstacine.monitor

import android.os.Looper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.opencine.insta360.luna.LunaBackend
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The Keystore-sealed camera Wi-Fi store blocks in Keystore2 backoff (OPENPOCKETCINE-ANDROID-13 ANR on
 * Pocket), so the Luna backend must never call it on Main. SIMULATED store; actual backend and main looper.
 */
@RunWith(AndroidJUnit4::class)
class LunaCredentialThreadTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val camera = "00:11:22:33:44:55"

    private fun backend(
        savedWifi: (String) -> Pair<String, String>? = { null },
        forgetWifi: (String) -> Unit = {},
    ) = LunaBackend(
        instrumentation.targetContext, savedWifi = savedWifi, forgetWifi = forgetWifi,
        clientIdentityPreferences = "test.luna-credential-thread",
    )

    @Test fun connectReadsSavedWifiOffMain() {
        val onMain = AtomicReference<Boolean>()
        val read = CountDownLatch(1)
        val luna = backend(savedWifi = { onMain.set(Looper.myLooper() == Looper.getMainLooper()); read.countDown(); null })
        try {
            instrumentation.runOnMainSync { luna.connect(camera) }
            assertTrue(read.await(5, TimeUnit.SECONDS), "connect never read the saved Wi-Fi")
            assertEquals(false, onMain.get())
        } finally {
            instrumentation.runOnMainSync { luna.close() }
        }
    }

    @Test fun forgetDropsSavedWifiOffMain() {
        val onMain = AtomicReference<Boolean>()
        val luna = backend(forgetWifi = { onMain.set(Looper.myLooper() == Looper.getMainLooper()) })
        try {
            runBlocking(Dispatchers.Main) { luna.forget(camera) }
            assertEquals(false, onMain.get())
        } finally {
            instrumentation.runOnMainSync { luna.close() }
        }
    }
}
