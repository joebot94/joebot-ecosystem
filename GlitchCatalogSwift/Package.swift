// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GlitchCatalogSwift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GlitchCatalogSwift", targets: ["GlitchCatalogSwift"])
    ],
    dependencies: [
        .package(path: "../JoebotSDK")
    ],
    targets: [
        .executableTarget(
            name: "GlitchCatalogSwift",
            dependencies: [
                .product(name: "JoebotSDK", package: "JoebotSDK")
            ]
        )
    ]
)
