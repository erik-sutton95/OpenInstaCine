package com.opencapture.openinstacine.monitor.diagnostics

import com.opencapture.openinstacine.monitor.BuildConfig
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame

/** The holder wires the host values this app shipped with before diagnostics moved to OpenCine. */
class AppDiagnosticsTest {
    @Test
    fun holderWiresThisAppsNamesDestinationAndRedaction() {
        val host = AppDiagnostics.host
        assertEquals("OpenInstaCine", host.product)
        assertEquals("com.opencapture.openinstacine@0.1.0+107", host.release("0.1.0", "107"))
        assertEquals(
            "com.opencapture.openinstacine@${BuildConfig.VERSION_NAME}+${BuildConfig.VERSION_CODE}",
            host.currentRelease,
        )
        // A local release build is local, never production; only a CI channel names another.
        assertEquals(if (BuildConfig.DEBUG) "development" else "local", host.environment)
        assertEquals(BuildConfig.SOURCE_REVISION, host.sourceRevision)
        assertEquals(BuildConfig.SENTRY_DSN_ANDROID, host.reportingDsn)
        assertEquals("openinstacine-android", host.reportingClient)
        assertEquals("support@opencapture.org", host.supportEmail)
        assertEquals("openpocketcine.operator", host.preferencesName)
        assertEquals("192.168.42.", AppDiagnostics.gate.cameraIPv4Prefix)
        // Luna keeps no network readable (A6-10): DJI-looking and ordinary SSIDs are both redacted.
        assertEquals("ssid=<redacted>", host.redact("ssid=OsmoPocket3-A1B2"))
        assertEquals("ssid=<redacted>", host.redact("ssid=EdgeRouter-5G"))
        assertEquals("ssid=<redacted>", host.redact("ssid=CafeWiFi"))
        assertSame(AppDiagnostics.gate, AppDiagnostics.reporting.gate)
        assertSame(AppDiagnostics.consent, AppDiagnostics.reporting.consent)
        assertSame(AppDiagnostics.origin, AppDiagnostics.reporting.origin)
    }
}
