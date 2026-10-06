package com.opencapture.openinstacine.monitor.media

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import com.opencapture.opencine.vocabulary.MediaRoute

fun MediaRoute.pathUrl(storage: Int, path: String): HttpUrl = pathUrlString(storage, path).toHttpUrl()
