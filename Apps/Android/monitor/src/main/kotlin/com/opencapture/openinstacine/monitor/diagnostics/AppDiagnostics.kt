package com.opencapture.openinstacine.monitor.diagnostics

import com.opencapture.opencine.appkit.diagnostics.DiagnosticsHost
import com.opencapture.opencine.appkit.diagnostics.FeedIncidentOrigin
import com.opencapture.opencine.appkit.diagnostics.FeedIncidentRuntime
import com.opencapture.opencine.appkit.diagnostics.ManualProblemReport
import com.opencapture.opencine.appkit.diagnostics.ReliabilityReporting
import com.opencapture.opencine.appkit.diagnostics.ReliabilityReportingConsent
import com.opencapture.opencine.appkit.diagnostics.ReliabilityReportingDSN
import com.opencapture.opencine.appkit.diagnostics.ReliabilityReportingGate
import com.opencapture.opencine.appkit.diagnostics.ReliabilityReportingHostPolicy
import com.opencapture.opencine.vocabulary.PrivacyRedactor
import com.opencapture.openinstacine.monitor.BuildConfig
import com.opencapture.opencine.media.FeedIncidentSink
import com.opencapture.opencine.media.FeedIncidentSource
import com.opencapture.opencine.media.FeedIncidentSessionContext
import com.opencapture.opencine.media.FeedIncidentSnapshot
import com.opencapture.opencine.media.FeedIncidentBreadcrumb
import com.opencapture.opencine.media.FeedRepairRecord
import android.os.SystemClock

/** The app's diagnostics: OpenCine's runtime with this app's names, destination, Sentry and OkHttp. */
internal object AppDiagnostics {
    val host =
        DiagnosticsHost(
            product = "OpenInstaCine",
            releasePackage = "com.opencapture.openinstacine",
            versionName = BuildConfig.VERSION_NAME,
            versionCode = BuildConfig.VERSION_CODE,
            debug = BuildConfig.DEBUG,
            sourceRevision = BuildConfig.SOURCE_REVISION,
            reportingDsn = BuildConfig.SENTRY_DSN_ANDROID,
            reportingClient = "openinstacine-android",
            supportEmail = "support@opencapture.org",
            preferencesName = "openpocketcine.operator",
            redact = PrivacyRedactor::redact,
        )
    val dsn = ReliabilityReportingDSN()
    val consent = ReliabilityReportingConsent(dsn)
    val gate = ReliabilityReportingGate(consent, ReliabilityReportingHostPolicy(), cameraIPv4Prefix = "192.168.42.")
    val origin = FeedIncidentOrigin({ BuildConfig.BUILD_IDENTITY }, host.redact)
    val reporting =
        ReliabilityReporting(host, consent, dsn, gate, origin, ::SentryReliabilitySink) {
            manualReport.noteCameraPathClear()
        }
    val incidents = FeedIncidentRuntime(reporting)
    val manualReport = ManualProblemReport(host, dsn, gate, OkHttpManualReportUpload)

    private var incidentOwner: Any? = null
    private var ownedIncidentSink: FeedIncidentSource? = null

    /** Host submissions belong to one facade; the runtime owns persistence and reporting policy. */
    fun incidentSink(owner: Any, sink: FeedIncidentSink = incidents): FeedIncidentSink = object : FeedIncidentSink {
        private var source: FeedIncidentSource? = null
        override fun beginSession(context: FeedIncidentSessionContext) = synchronized(AppDiagnostics) {
            if (incidentOwner !== owner) ownedIncidentSink?.endSession(SystemClock.elapsedRealtime() / 1_000.0)
            source = sink.beginBoundSession(context)
            incidentOwner = owner
            ownedIncidentSink = source
        }
        override fun endSession(nowSeconds: Double) = synchronized(AppDiagnostics) {
            if (incidentOwner === owner) {
                source?.endSession(nowSeconds)
                source = null
                incidentOwner = null
                ownedIncidentSink = null
            }
        }
        private fun submit(action: (FeedIncidentSource) -> Unit) = synchronized(AppDiagnostics) {
            if (incidentOwner === owner) source?.let(action)
        }
        override fun ingestSnapshot(snapshot: FeedIncidentSnapshot) = submit { it.ingestSnapshot(snapshot) }
        override fun recordBreadcrumb(breadcrumb: FeedIncidentBreadcrumb) = submit { it.recordBreadcrumb(breadcrumb) }
        override fun recordRepair(repair: FeedRepairRecord) = submit { it.recordRepair(repair) }
        override fun noteDecoderGeneration(generation: Int) = submit { it.noteDecoderGeneration(generation) }
        override fun noteSocketGeneration(generation: Int) = submit { it.noteSocketGeneration(generation) }
        override fun noteExhausted(nowSeconds: Double) = submit { it.noteExhausted(nowSeconds) }
        override fun noteUnexpectedDisconnect(nowSeconds: Double) = submit { it.noteUnexpectedDisconnect(nowSeconds) }
        override fun noteTestSource(source: com.opencapture.opencine.media.FeedIncidentTestSource) = submit { it.noteTestSource(source) }
    }

    // The root owns one camera backend. A retired facade cannot reopen its successor's gate.
    private var cameraSessionOwner: Any? = null
    @Synchronized fun beginCameraSession(owner: Any) {
        cameraSessionOwner = owner
        reporting.setCameraSessionActive(true)
    }
    @Synchronized fun endCameraSession(owner: Any) {
        if (cameraSessionOwner !== owner) return
        cameraSessionOwner = null
        reporting.setCameraSessionActive(false)
    }
}
