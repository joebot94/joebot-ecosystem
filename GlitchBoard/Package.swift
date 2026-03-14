// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GlitchBoard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GlitchBoard", targets: ["GlitchBoard"])
    ],
    dependencies: [
        .package(path: "../JoebotSDK")
    ],
    targets: [
        .executableTarget(
            name: "GlitchBoard",
            dependencies: [
                .product(name: "JoebotSDK", package: "JoebotSDK")
            ]
        )
    ]
)
