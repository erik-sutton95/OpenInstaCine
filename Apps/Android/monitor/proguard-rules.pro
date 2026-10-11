# JNI downcalls resolve these exact class and native method names.
-keep class com.opencapture.openinstacine.monitor.bridge.SwiftCore {
    native <methods>;
}
-keep class com.opencapture.openpocketcine.feed.OpcVulkan {
    native <methods>;
}
