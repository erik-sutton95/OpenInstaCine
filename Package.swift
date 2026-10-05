// swift-tools-version: 6.0
import PackageDescription

// The portable, UI-free, I/O-free core for OpenPocketCine: UDP datalink byte math,
// BLE advert decode, status decode, and saved-camera
// records. Pure Foundation, so it builds and tests natively on macOS (`swift test`)
// without a device. The iOS app (ios/) imports this and supplies CoreBluetooth /
// Network / Hotspot I/O. Android consumes the same target via a JNI facade
// (`just android-core`) — keep this module UI-free and platform-agnostic.
// Shared UI (MonitorPresentation, MonitorUI) comes from the OpenCine package,
// consumed by ios/project.yml, not from this manifest.
let package = Package(
    name: "OpenPocketViewCore",
    // macOS 13: OpenCine's minimum (host `swift test` only; no macOS app ships).
    platforms: [.iOS(.v17), .macOS(.v13), .watchOS(.v10)],
    products: [
        .library(name: "OpenPocketViewCore", targets: ["OpenPocketViewCore"]),
        // JNI facade consumed by the Android app (`just android-core`). The JNI
        // shims are `#if os(Android)`-gated; on Darwin only the wire helpers
        // compile, so iOS/macOS behavior is unchanged.
        .library(
            name: "OpenPocketCineAndroid", type: .dynamic, targets: ["OpenPocketCineAndroidFacade"]),
    ],
    dependencies: [
        // Portable media math (OpenCineMedia), shared gimbal motion (OpenCineMotion) and the
        // second-screen relay wire (OpenCineRelay).
        // The OpenCine platform package. Sibling checkout until OpenCine is published.
        .package(path: "../OpenCine")
    ],
    targets: [
        .target(
            name: "OpenPocketViewCore",
            dependencies: [
                .product(name: "OpenCineCore", package: "OpenCine"),
                .product(name: "OpenCineMedia", package: "OpenCine"),
                .product(name: "OpenCineMotion", package: "OpenCine"),
                .product(name: "OpenCineRelay", package: "OpenCine"),
                // Live chrome layout policy (`MonitorLayoutRegion`, `GimbalCluster`).
                .product(name: "MonitorPresentation", package: "OpenCine"),
            ]
        ),
        .testTarget(
            name: "OpenPocketViewCoreTests",
            // Insta360Apple: the shell reach is checked against what the Luna integration declares.
            dependencies: ["OpenPocketViewCore", .product(name: "Insta360Apple", package: "OpenCine")]
        ),
        .target(
            name: "OpenPocketCineAndroidFacade",
            dependencies: [
                "OpenPocketViewCore",
                .product(name: "OpenCineJNISupport", package: "OpenCine"),
            ]
        ),
        .testTarget(
            name: "OpenPocketCineAndroidFacadeTests",
            dependencies: ["OpenPocketCineAndroidFacade", "OpenPocketViewCore"]
        ),
    ]
)
