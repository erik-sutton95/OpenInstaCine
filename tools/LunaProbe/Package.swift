// swift-tools-version: 5.9
// Lab CLI for verifying Adapters/Insta360Protocol against a real Luna Ultra.
import PackageDescription

let package = Package(
    name: "LunaProbe",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../../Adapters/Insta360Protocol")],
    targets: [
        .executableTarget(
            name: "LunaProbe",
            dependencies: [.product(name: "Insta360Protocol", package: "Insta360Protocol")])
    ]
)
