// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Observatory",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Observatory", targets: ["Observatory"])
    ],
    dependencies: [
        .package(path: "../JoebotSDK")
    ],
    targets: [
        .executableTarget(
            name: "Observatory",
            dependencies: [
                .product(name: "JoebotSDK", package: "JoebotSDK")
            ]
        )
    ]
)
