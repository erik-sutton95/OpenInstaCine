// swift-tools-version: 6.0
import PackageDescription

// One shared monitor math/policy implementation. Brand transport codecs stay in
// Adapters. The old OpenPocketViewCore import/product remains a compatibility
// bridge while native shells and JNI callers migrate to neutral contracts.
let package = Package(
    name: "SharedMonitorEngine",
    platforms: [.iOS(.v17), .macOS(.v12)],
    products: [
        .library(name: "MonitorCore", targets: ["MonitorCore"]),
        .library(name: "MonitorContracts", targets: ["MonitorContracts"]),
        .library(name: "OpenPocketViewCore", targets: ["OpenPocketViewCore"]),
        // JNI facade consumed by the Android app (`just android-core`). The JNI
        // shims are `#if os(Android)`-gated; on Darwin only the wire helpers
        // compile, so iOS/macOS behavior is unchanged.
        .library(
            name: "OpenPocketCineAndroid", type: .dynamic, targets: ["OpenPocketCineAndroidFacade"]),
    ],
    targets: [
        .target(name: "MonitorCore"),
        .target(name: "MonitorContracts"),
        .target(
            name: "OpenPocketViewCore",
            dependencies: ["MonitorCore"],
            path: "Adapters/OsmoCompatibility/Sources/OpenPocketViewCore"
        ),
        .testTarget(
            name: "OpenPocketViewCoreTests",
            dependencies: ["OpenPocketViewCore", "MonitorCore"],
            exclude: ["Fixtures"]
        ),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"]),
        // Header-only shim exposing the NDK's <jni.h> to Swift; empty on Darwin.
        .target(name: "CJNI"),
        .target(
            name: "OpenPocketCineAndroidFacade",
            dependencies: ["OpenPocketViewCore", "CJNI"]
        ),
        .testTarget(
            name: "OpenPocketCineAndroidFacadeTests",
            dependencies: ["OpenPocketCineAndroidFacade", "OpenPocketViewCore"]
        ),
    ]
)
