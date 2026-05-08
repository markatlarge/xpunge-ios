// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XpungeSDK",
    platforms: [.iOS(.v14), .macOS(.v10_15)],
    products: [
        .library(name: "XpungeSDK", targets: ["XpungeSDK"]),
    ],
    targets: [
        .target(
            name: "XpungeSDK",
            path: "Sources/XpungeSDK",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "XpungeExample",
            dependencies: ["XpungeSDK"],
            path: "Example",
            resources: [.copy("test.jpg")]
        ),
    ]
)
