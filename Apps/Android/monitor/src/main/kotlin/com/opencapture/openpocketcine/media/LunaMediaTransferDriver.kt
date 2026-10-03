package com.opencapture.openpocketcine.media

import com.opencapture.opencine.insta360.shell.LunaMediaTransferPort
import com.opencapture.opencine.media.MediaByteSink
import com.opencapture.opencine.media.MediaTransferReceipt
import com.opencapture.opencine.runtime.MonitorMediaReadSource
import com.opencapture.opencine.runtime.MonitorMediaStreamPump

/** Only the existing app HTTP client creates sockets; the native owner copies to the owned sink. */
class LunaMediaTransferDriver(
    private val source: (String) -> MonitorMediaReadSource = MediaTransfer::nativeSource,
) : LunaMediaTransferPort {
    private val pump = MonitorMediaStreamPump()
    override suspend fun transfer(url: String, sink: MediaByteSink): MediaTransferReceipt = transfer(url, null, sink)
    override suspend fun transfer(url: String, expectedByteCount: Long?, sink: MediaByteSink): MediaTransferReceipt =
        pump.transfer(source(url), expectedByteCount, sink)
}
