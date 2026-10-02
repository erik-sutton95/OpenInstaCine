// JNI facade over OpenPocketViewCore for the Android app.
//
// Hand-written `@_cdecl` shims matching the `external fun` declarations in
// Apps/Android/app/.../bridge/SwiftCore.kt. Coarse boundary: strings, byte
// arrays, and primitives only.
//
// This file compiles empty on Darwin so `swift test` is unaffected.
#if os(Android)

    import OpenCineJNISupport
    import Foundation
    import OpenPocketViewCore

    // MARK: - Info

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_coreVersion")
    public func swiftCoreVersion(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?
    ) -> jstring? {
        javaString(env, AndroidSessionWire.coreVersion)
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_cameraSoftAPDecision")
    public func swiftCoreCameraSoftAPDecision(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?,
        kind: jstring?, requestJSON: jstring?
    ) -> jstring? {
        javaString(
            env,
            AndroidSessionWire.cameraSoftAPDecision(
                kind: swiftString(env, kind) ?? "",
                requestJSON: swiftString(env, requestJSON) ?? "{}"))
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_conformPreviewJSON")
    public func swiftCoreConformPreviewJSON(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, request: jstring?
    ) -> jstring? {
        javaString(
            env,
            AndroidSessionWire.conformPreviewJSON(swiftString(env, request) ?? "{}"))
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_packImportedLut")
    public func swiftCorePackImportedLut(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, utf8: jbyteArray?,
        exposureStops: jdouble, colorMode: jint
    ) -> jbyteArray? {
        guard
            let packed = LUTLibraryWire.packedImportedLUT(
                utf8: swiftBytes(env, utf8) ?? [],
                exposureStops: Double(exposureStops),
                colorModeCode: Int(colorMode))
        else { return nil }
        return javaByteArray(env, packed)
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_packCreativeLut")
    public func swiftCorePackCreativeLut(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, title: jstring?,
        exposureStops: jdouble, colorMode: jint
    ) -> jbyteArray? {
        guard
            let packed = LUTLibraryWire.packedCreativeLook(
                swiftString(env, title) ?? "",
                exposureStops: Double(exposureStops),
                colorModeCode: Int(colorMode))
        else { return nil }
        return javaByteArray(env, packed)
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_packFalseColorPaint")
    public func swiftCorePackFalseColorPaint(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?,
        scaleOrdinal: jint, colorMode: jint, iso: jint
    ) -> jbyteArray? {
        guard
            let packed = FeedEffectsWire.packedFalseColorPaint(
                scaleOrdinal: Int(scaleOrdinal),
                colorModeCode: Int(colorMode),
                iso: Int(iso))
        else { return nil }
        return javaByteArray(env, packed)
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_packFalseColorWeight")
    public func swiftCorePackFalseColorWeight(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?,
        scaleOrdinal: jint, colorMode: jint, iso: jint
    ) -> jbyteArray? {
        guard
            let packed = FeedEffectsWire.packedFalseColorWeight(
                scaleOrdinal: Int(scaleOrdinal),
                colorModeCode: Int(colorMode),
                iso: Int(iso))
        else { return nil }
        return javaByteArray(env, packed)
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_feedAssistScalars")
    public func swiftCoreFeedAssistScalars(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?,
        colorMode: jint, iso: jint, highlightIRE: jfloat, midtoneIRE: jfloat
    ) -> jfloatArray? {
        javaFloatArray(
            env,
            FeedEffectsWire.assistScalars(
                colorModeCode: Int(colorMode),
                iso: Int(iso),
                highlightIRE: Double(highlightIRE),
                midtoneIRE: Double(midtoneIRE)))
    }

    private func javaFloatArray(
        _ env: UnsafeMutablePointer<JNIEnv?>, _ values: [Float]
    ) -> jfloatArray? {
        let fns = table(env)
        guard let array = fns.NewFloatArray!(env, jsize(values.count)) else { return nil }
        values.withUnsafeBufferPointer { buffer in
            fns.SetFloatArrayRegion!(env, array, 0, jsize(values.count), buffer.baseAddress)
        }
        return array
    }

#endif
