package com.opencapture.openpocketcine.diagnostics

// Application source compatibility while the neutral model lives in OpenCine Media.
internal typealias FeedIncidentSchema = com.opencapture.opencine.media.FeedIncidentSchema
internal typealias FeedIncidentTestSource = com.opencapture.opencine.media.FeedIncidentTestSource
internal typealias FeedIncidentBounds = com.opencapture.opencine.media.FeedIncidentBounds
internal typealias FeedIncidentLimits = com.opencapture.opencine.media.FeedIncidentLimits
internal typealias FeedIncidentSessionContext = com.opencapture.opencine.media.FeedIncidentSessionContext
internal typealias FeedIncidentKind = com.opencapture.opencine.media.FeedIncidentKind
internal typealias FeedIncidentFailingStage = com.opencapture.opencine.media.FeedIncidentFailingStage
internal typealias FeedIncidentOutcome = com.opencapture.opencine.media.FeedIncidentOutcome
internal typealias FeedIncidentSuppression = com.opencapture.opencine.media.FeedIncidentSuppression
internal typealias FeedDecoderErrorOrigin = com.opencapture.opencine.media.FeedDecoderErrorOrigin
internal typealias FeedIncidentBreadcrumbKind = com.opencapture.opencine.media.FeedIncidentBreadcrumbKind
internal typealias FeedRepairPhase = com.opencapture.opencine.media.FeedRepairPhase
internal typealias FeedIncidentRates = com.opencapture.opencine.media.FeedIncidentRates
internal typealias FeedIncidentAges = com.opencapture.opencine.media.FeedIncidentAges
internal typealias FeedIncidentQueue = com.opencapture.opencine.media.FeedIncidentQueue
internal typealias FeedIncidentDecoder = com.opencapture.opencine.media.FeedIncidentDecoder
internal typealias FeedIncidentLifecycle = com.opencapture.opencine.media.FeedIncidentLifecycle
internal typealias FeedIncidentSnapshot = com.opencapture.opencine.media.FeedIncidentSnapshot
internal typealias FeedIncidentBreadcrumb = com.opencapture.opencine.media.FeedIncidentBreadcrumb
internal typealias FeedIncidentNativeBreadcrumb = com.opencapture.opencine.media.FeedIncidentNativeBreadcrumb
internal typealias FeedRepairRecord = com.opencapture.opencine.media.FeedRepairRecord
internal typealias FeedIncidentErrorCount = com.opencapture.opencine.media.FeedIncidentErrorCount
internal typealias FeedIncidentHeader = com.opencapture.opencine.media.FeedIncidentHeader
internal typealias FeedIncidentBundle = com.opencapture.opencine.media.FeedIncidentBundle
internal typealias FeedIncidentVerdict = com.opencapture.opencine.media.FeedIncidentVerdict
internal typealias FeedIncidentPersistenceJob = com.opencapture.opencine.media.FeedIncidentPersistenceJob
internal typealias FeedIncidentClassifier = com.opencapture.opencine.media.FeedIncidentClassifier
internal typealias FeedIncidentGrouping = com.opencapture.opencine.media.FeedIncidentGrouping
internal typealias FeedIncidentVendorEnvelope = com.opencapture.opencine.media.FeedIncidentVendorEnvelope
internal typealias FeedIncidentSessionSummary = com.opencapture.opencine.media.FeedIncidentSessionSummary
internal typealias FeedIncidentExport = com.opencapture.opencine.media.FeedIncidentExport
internal typealias FeedIncidentFileNaming = com.opencapture.opencine.media.FeedIncidentFileNaming
internal typealias FeedIncidentSampling = com.opencapture.opencine.media.FeedIncidentSampling
internal typealias FeedIncidentPersistenceReason = com.opencapture.opencine.media.FeedIncidentPersistenceJob.Reason

internal object FeedIncidentBuildIdentity {
    const val MAX_LENGTH = 64
    fun parse(raw: String?): String =
        com.opencapture.opencine.media.FeedIncidentBuildIdentity.parse(raw, PrivacyRedactor::redact)
}

internal object FeedIncidentPrivacy {
    fun token(raw: String, max: Int = FeedIncidentBounds.STRING_LENGTH): String =
        com.opencapture.opencine.media.FeedIncidentPrivacy.token(raw, max, PrivacyRedactor::redact)
    fun rate(value: Double): Double = com.opencapture.opencine.media.FeedIncidentPrivacy.rate(value)
    fun stamp(value: Double): Double = com.opencapture.opencine.media.FeedIncidentPrivacy.stamp(value)
    fun age(value: Double?): Double? = com.opencapture.opencine.media.FeedIncidentPrivacy.age(value)
    fun isFresh(age: Double?, threshold: Double): Boolean =
        com.opencapture.opencine.media.FeedIncidentPrivacy.isFresh(age, threshold)
    fun isStale(age: Double?, hertz: Double, flowingAlternative: Boolean, threshold: Double): Boolean =
        com.opencapture.opencine.media.FeedIncidentPrivacy.isStale(age, hertz, flowingAlternative, threshold)
    fun gapSeconds(snapshot: FeedIncidentSnapshot, stage: FeedIncidentFailingStage): Double =
        com.opencapture.opencine.media.FeedIncidentPrivacy.gapSeconds(snapshot, stage)
}
