// swift-tools-version: 5.9
// Lab CLI for verifying Insta360Protocol (sibling OpenCineInsta360 package) against a real Luna Ultra.
import PackageDescription

let package = Package(
    name: "LunaProbe",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../../../OpenCineInsta360")],
    targets: [
        .executableTarget(
            name: "LunaProbe",
            dependencies: [.product(name: "Insta360Protocol", package: "OpenCineInsta360")])
    ]
)
