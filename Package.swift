// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XpungeSDK",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "XpungeSDK", targets: ["XpungeSDK"]),
    ],
    targets: [
        .target(
            name: "XpungeSDK",
            path: "Sources/XpungeSDK",
            resources: [.process("Resources")]
        ),
    ]
)
