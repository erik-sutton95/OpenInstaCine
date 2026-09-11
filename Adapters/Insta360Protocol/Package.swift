// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Insta360Protocol",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "Insta360Protocol", targets: ["Insta360Protocol"])],
    targets: [
        .target(name: "Insta360Protocol"),
        .testTarget(name: "Insta360ProtocolTests", dependencies: ["Insta360Protocol"])
    ]
)
