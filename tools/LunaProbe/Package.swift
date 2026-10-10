// swift-tools-version: 5.9
// Lab CLI for verifying Insta360Protocol (sibling OpenCine package) against a real Luna Ultra.
import PackageDescription

let package = Package(
    name: "LunaProbe",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../../../OpenCine")],
    targets: [
        .executableTarget(
            name: "LunaProbe",
            dependencies: [.product(name: "Insta360Protocol", package: "OpenCine")])
    ]
)
