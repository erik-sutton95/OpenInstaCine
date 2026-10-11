package com.opencapture.openinstacine.monitor

import com.opencapture.opencine.media.FeedIncidentBreadcrumb
import com.opencapture.opencine.media.FeedIncidentSessionContext
import com.opencapture.opencine.media.FeedIncidentSink
import com.opencapture.opencine.media.FeedIncidentSnapshot
import com.opencapture.opencine.media.FeedRepairRecord
import java.util.concurrent.CopyOnWriteArrayList

/** SIMULATED: no persistence, SDK, report upload or native camera resources. */
internal class RecordingFeedIncidentSink : FeedIncidentSink {
    val events = CopyOnWriteArrayList<String>()
    val contexts = CopyOnWriteArrayList<FeedIncidentSessionContext>()
    val snapshots = CopyOnWriteArrayList<FeedIncidentSnapshot>()
    override fun beginSession(context: FeedIncidentSessionContext) { contexts += context; events += "begin" }
    override fun endSession(nowSeconds: Double) { events += "end" }
    override fun ingestSnapshot(snapshot: FeedIncidentSnapshot) { snapshots += snapshot; events += "snapshot" }
    override fun recordBreadcrumb(breadcrumb: FeedIncidentBreadcrumb) { events += "breadcrumb" }
    override fun recordRepair(repair: FeedRepairRecord) { events += "repair" }
    override fun noteDecoderGeneration(generation: Int) { events += "decoderGeneration" }
    override fun noteSocketGeneration(generation: Int) { events += "socketGeneration" }
    override fun noteExhausted(nowSeconds: Double) { events += "exhausted" }
    override fun noteUnexpectedDisconnect(nowSeconds: Double) { events += "disconnected" }
}
