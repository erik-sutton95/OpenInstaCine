package com.opencapture.openinstacine.monitor.media

import com.opencapture.opencine.runtime.MonitorMediaReadSource
import com.opencapture.opencine.runtime.MonitorMediaReadStream
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

/** The app's HTTP client for camera media reads; the shared native pump owns copying, length and limits. */
object MediaTransfer {
    private val client: OkHttpClient =
        OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(15, TimeUnit.SECONDS)
            .callTimeout(0, TimeUnit.SECONDS)
            .followRedirects(false)
            .followSslRedirects(false)
            .retryOnConnectionFailure(false)
            .build()

    /** Native driver preserves this client's timeout, redirect and retry configuration. */
    fun nativeSource(url: String): MonitorMediaReadSource {
        val call = client.newCall(Request.Builder().url(url).header("Accept", "*/*").get().build())
        return object : MonitorMediaReadSource {
            override fun cancel() { call.cancel() }
            override fun open(): MonitorMediaReadStream {
                val response = call.execute()
                val body = response.body
                return object : MonitorMediaReadStream {
                    override val status = response.code
                    override val contentLength = body.contentLength().takeIf { it > 0 }
                    override val input = body.byteStream()
                    override fun close() { response.close() }
                }
            }
        }
    }
}
