// swift-tools-version: 6.0
import PackageDescription

// Shared monitor engine vendored from OpenPocketCine. Re-sync with
// `just sync-openpocketcine`. Luna wire codecs stay in Adapters/.
let package = Package(
    name: "SharedMonitorEngine",
    platforms: [.iOS(.v17), .macOS(.v12), .watchOS(.v10)],
    products: [
        .library(name: "MonitorPresentation", targets: ["MonitorPresentation"]),
        .library(name: "MonitorUI", targets: ["MonitorUI"]),
        .library(name: "OpenPocketViewCore", targets: ["OpenPocketViewCore"]),
        .library(name: "MonitorContracts", targets: ["MonitorContracts"]),
        .library(
            name: "OpenPocketCineAndroid", type: .dynamic, targets: ["OpenPocketCineAndroidFacade"]),
    ],
    targets: [
        .target(name: "MonitorPresentation"),
        .target(
            name: "MonitorUI", dependencies: ["MonitorPresentation"],
            resources: [.process("Resources/Fonts"), .copy("Resources/Icons")]
        ),
        .testTarget(name: "MonitorPresentationTests", dependencies: ["MonitorPresentation"]),
        .target(name: "OpenPocketViewCore"),
        .testTarget(
            name: "OpenPocketViewCoreTests",
            dependencies: ["OpenPocketViewCore"],
            exclude: ["Fixtures"]
        ),
        .target(name: "MonitorContracts"),
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
