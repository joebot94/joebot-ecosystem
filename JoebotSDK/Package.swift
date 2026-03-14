// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JoebotSDK",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "JoebotSDK", targets: ["JoebotSDK"])
    ],
    targets: [
        .target(name: "JoebotSDK")
    ]
)
